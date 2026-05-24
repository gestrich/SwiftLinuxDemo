# Build provenance attestation

A four-line YAML step turns an ordinary release into a cryptographically
verifiable one. This chapter explains the four lines, but more
importantly it explains the *vocabulary*, the *trust model*, and the
limits of what attestation can and cannot prove.

## The problem this solves

When you install a binary, you can't inspect what's inside. Even when the
source code is public, the question remains:

> *How do I know this exact executable was actually built from that source
> code, by the process the maintainer claims?*

That's the supply-chain trust problem. Without a solution, you're trusting
the union of:

- whoever uploaded the binary,
- the hosting platform's access controls,
- the build machine,
- and the maintainer's operational hygiene.

Attestations don't eliminate trust — they *reduce blind trust* by adding
cryptographic proof that connects each step in:

```
Source code  →  Build process  →  Artifact (binary)  →  User verification
```

## Vocabulary — provenance, attestation, signature

These three words get used interchangeably in the wild. The distinctions
matter.

**Provenance** — the *story* of where an artifact came from: which repo,
which commit, which workflow file, which run, when, on what runner, with
which builder identity. Provenance is descriptive. The analogy that fits
best is chain of custody for evidence, or ownership history for a
painting.

**Attestation** — the *evidence* for a claim within that provenance: a
signed, structured statement like *"I am asserting these facts about
this artifact."* Attestations are how provenance is communicated and
verified. One artifact can carry several attestations (build provenance,
SBOM, vulnerability scan, …).

**Signature** — the cryptographic primitive underneath: proof that an
attestation hasn't been tampered with and came from a specific signer. A
signature alone only says "someone signed this." It doesn't say *what*
they signed, in what format, or about what. Attestations are the
structured envelope that gives a signature meaning.

The hierarchy reads:

```
Provenance       (the story)
  └─ communicated via
      Attestations   (structured signed claims)
        └─ authenticated by
            Signatures   (cryptographic proof of origin + integrity)
```

The one-line mental model:

> Attestation proves *how* a binary was produced; provenance is the
> overall history that makes that proof meaningful.

## Who does what

**GitHub** is the *attestation issuer*. When your workflow runs, GitHub
already knows the repo, the workflow file path, the commit SHA, the
runner environment, and a unique run ID — all of which become claims in
the generated SLSA provenance statement.

**Sigstore** is the cryptographic infrastructure GitHub uses under the
hood. Two pieces matter:

- **Fulcio** — a certificate authority that issues short-lived (~10 min)
  signing certificates in exchange for an OIDC identity token. Replaces
  long-lived private keys with ephemeral ones. The signing keypair
  exists for one signature and is destroyed; the certificate is the
  receipt.
- **Rekor** — a public, append-only transparency log. Every signature
  Sigstore emits is recorded here so anyone — not just the original
  signer or verifier — can independently audit the activity. Tamper-
  evident. The closest existing analogy is Certificate Transparency
  logs, not a decentralized consensus blockchain.

**Cosign** is the signing/verification tooling Sigstore ships. GitHub
uses it internally; `gh attestation verify` is effectively a friendly
wrapper.

**in-toto** is a related but broader layer. GitHub's default build
provenance answers "this final artifact came from this build." The
in-toto schema can answer "these exact *steps* happened in this exact
supply chain" — source checkout, dependency resolution, build, test,
sign, package, deploy, each potentially with its own attestation.
What `actions/attest-build-provenance` emits is one in-toto Statement
with a SLSA Provenance v1 predicate — the narrowest useful slice.

## Why transparency logs matter

Without Rekor, the operational posture would be "trust us, we signed
this." With Rekor, anyone can independently verify:

- the attestation existed at this point in time,
- the signing certificate was issued by Fulcio in response to a real
  workflow run,
- nothing was retroactively forged or backdated.

The motivation is to *reduce centralized trust*. Even if a single
party in the chain were compromised, the public, externally-mirrored
log entries make silent retroactive forgery very hard.

## The actual step in this repo

```yaml
- name: Attest build provenance
  uses: actions/attest-build-provenance@v2
  with:
    subject-path: 'swift-linux-demo-*.tar.gz'
```

Four lines, six things happening:

1. Compute the SHA-256 hash of each file matching the glob (the "subject
   digest").
2. Use the runner's `id-token: write` permission to request an OIDC
   token from GitHub. The token's claims include `repository`, `ref`,
   `workflow`, `job_workflow_ref`, `sha`, and `run_id`.
3. Send the OIDC token to Sigstore's Fulcio CA, which issues a
   short-lived (~10 min) X.509 certificate whose subject identifies the
   workflow run.
4. Generate an in-toto Statement with a SLSA Provenance v1 predicate —
   a JSON document linking the artifact digest to the builder identity,
   source repo, commit, and workflow inputs.
5. Sign the statement with the ephemeral private key, destroy the key,
   and submit the signature + public key to Rekor.
6. Register the resulting bundle (cert + signature + Rekor inclusion
   proof + statement) with GitHub via the Attestations REST API so
   `gh attestation verify` can find it later.

## Permissions — the three-scope ritual

Three scopes have to be granted at the workflow or job level:

```yaml
permissions:
  attestations: write   # register the provenance statement with GitHub
  contents: write       # let `gh release create` push assets
  id-token: write       # request the OIDC token Sigstore needs
```

If you remove `id-token: write`, attestation fails with a confusing
error that doesn't mention OIDC. Always remember the three together.

A *job-level* `permissions:` block fully **replaces** the workflow-level
one — it doesn't merge. Anything not listed at the job level becomes
`none` for that job, even if the workflow level granted it. Two safe
patterns:

- Workflow-level grants, no job-level blocks (this repo's choice).
- Workflow-level `permissions: {}` (deny all) with each job opting in
  to exactly the scopes it needs (GitHub's hardened pattern).

Avoid the middle ground where some jobs have blocks and others don't,
with the workflow level granting permissively — that's how a new job
ends up silently inheriting more than it should.

## Why "keyless" — the OIDC trick

Traditional code signing requires a long-lived private key you keep
secret forever. Sigstore replaces that with three short-lived things:

- An **OIDC token** (valid minutes) proving identity.
- An **X.509 certificate** (~10 min) issued by Fulcio in exchange for
  the OIDC token.
- A **signing keypair** generated in memory and destroyed after one
  signature.

Trust is rooted not in "who held the private key" but in "who could
obtain an OIDC token with these claims." The OIDC token can *only* have
`repository: gestrich/SwiftLinuxDemo` and `ref: refs/tags/v0.1.0` if it
was actually minted for a run in this repo on this tag. GitHub's OIDC
issuer is the trust anchor.

Operationally this is huge: there is no key to rotate, no HSM to fund,
no secret to lose.

## What attestation does NOT solve

This is the section most introductions skip, and it's the most
important one for setting expectations.

**1. A compromised maintainer account.** If an attacker has push access
to the repo, they can write malicious code, push it, and trigger a
workflow that builds and attests the malicious binary. The attestation
will be *valid* — it correctly says "this binary came from this repo
at this commit." Attestation proves *authenticity*, not *intent*.

**2. A malicious workflow definition.** If the workflow file itself
does something evil (e.g. injects a backdoor before the build), you
get a perfectly-signed receipt for evil behavior.

**3. A compromised dependency.** If the build pulls in a malicious
upstream package, the resulting binary is honestly attested to be
"what this workflow produced from this commit" — *including* the
malicious dependency.

So why is this still valuable? Because it eliminates one entire attack
class: **post-build artifact swap.**

| Threat | Without attestation | With attestation |
|---|---|---|
| Attacker swaps a tarball on the releases page after a legitimate build | Hard to detect — `checksums.txt` can be re-published consistently by the same actor | Verification fails: the new file's hash doesn't match the attestation's subject digest |
| Attacker uploads an unrelated binary claiming "this is v1.2" | No way to disprove the claim from the file alone | No attestation exists for that hash → `gh attestation verify` refuses |
| Attacker steals push access and commits malicious code | Trust is broken silently | Attestation honestly records that the binary was built from a malicious commit. Still bad, but the audit trail is public, permanent, and tied to that exact commit SHA in Rekor |

The trust boundary moves from *"I trust whoever uploaded this file"*
to *"I trust this build identity and workflow definition."* That's a
meaningful shift even though it isn't "this software is safe."

## Hashes vs attestations

A checksum proves: *this file matches this checksum.* But then — who
published the checksum? Same trust problem, one layer up.

An attestation proves:

- this exact file hash,
- was emitted by this workflow file,
- in this repo,
- from this commit,
- in this specific run,
- and the record of that fact lives in a public transparency log.

Much richer trust model, and the chain terminates at a verifiable Rekor
inclusion proof rather than at a tarball on someone's blog.

## Why commit pinning matters

Tags are mutable. A maintainer (or attacker with push access) can
delete `v0.1.0` and re-push it pointing at a different commit. The
attestation for the *original* `v0.1.0` build still exists and is
still valid for the original binary — but a verifier who only checks
"came from this repo" won't notice the swap.

`gh attestation verify --repo gestrich/SwiftLinuxDemo` is the easy
path; it passes as long as *any* attestation in the repo matches the
binary's hash. For stronger guarantees, also pin:

- the **commit SHA** (the strongest, most precise pin),
- and/or the **workflow file path** (so a different workflow in the
  same repo can't satisfy verification).

Inspect the verified statement (e.g. with `--format json`) and check
those fields yourself if your policy requires them:

```bash
gh attestation verify swift-linux-demo-linux-x86_64.tar.gz \
  --repo gestrich/SwiftLinuxDemo \
  --signer-workflow gestrich/SwiftLinuxDemo/.github/workflows/release.yml
```

Verification is only as strong as the policy you actually enforce on
the statement's claims.

## End-user verification

```bash
gh attestation verify swift-linux-demo-linux-x86_64.tar.gz \
  --repo gestrich/SwiftLinuxDemo
```

Under the hood, that command:

1. Computes the SHA-256 of your local file.
2. Fetches the attestation bundle from GitHub for that digest.
3. Validates the Sigstore certificate chain back to Fulcio's root.
4. Confirms the Rekor transparency-log inclusion proof.
5. Checks that the certificate's identity claims match
   `gestrich/SwiftLinuxDemo`.
6. (Silently) returns 0 on success.

`gh attestation verify` prints nothing on success by design — only
failures get loud. To see the signed statement (and confirm the
commit SHA, workflow file, and run ID it asserts), add
`--format json` and inspect `verificationResult.statement` and
`signature.certificate`.

## See Also

- <doc:04-DocC-On-Pages>
- The [Sigstore docs](https://docs.sigstore.dev/) — Fulcio, Rekor,
  Cosign, in deeper detail than this chapter.
- The [SLSA v1.0 specification](https://slsa.dev/spec/v1.0/) — the
  semantic content of a provenance statement.
