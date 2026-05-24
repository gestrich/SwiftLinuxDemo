# Releases anyone can verify

## The problem this chapter is solving

Every binary on every release page on the internet has the same
problem: you can't see what's inside. Even when the source code is
public and well-audited, the executable on the download page is
opaque. It could have been built from a different commit than the
tag suggests, modified after the build finished, or replaced wholesale
with something malicious — and from the outside, there's no way to
tell.

This is the *supply-chain trust problem.* A whole ecosystem of
open-source projects has grown up to address it over the last few
years, and the four lines of YAML this chapter walks through plug into
that ecosystem directly. By the end you should be able to:

- Read a release pipeline and recognize *which* of those ecosystems is
  doing what.
- Explain to a colleague the difference between *provenance*,
  *attestation*, and *signature*.
- Run `gh attestation verify` against a binary and understand what it
  actually proved, and what it didn't.

## Vocabulary

Three words get used interchangeably in casual writing. The
distinctions are real, and especially matter when reading
[SLSA][slsa-spec] documentation or troubleshooting error messages.

**Provenance** — the *story* of where an artifact came from: which
repository, which commit, which workflow file, which run, when, on
what kind of runner, with which builder identity. Provenance is
descriptive. The best analogy is chain-of-custody for evidence, or
ownership history for a painting.

**Attestation** — the *evidence* for a claim within that provenance:
a signed, structured statement like *"I am asserting these facts
about this artifact."* Attestations are how provenance is
communicated and verified. One artifact can carry several attestations
(build provenance, an SBOM, a vulnerability scan result, …).

**Signature** — the cryptographic primitive underneath: mathematical
proof that an attestation hasn't been tampered with and came from a
specific signer. A signature alone only says *"someone signed this."*
It doesn't say *what* they signed, in what format, or about what.
Attestations are the structured envelope that gives a signature
meaning.

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

## The four projects this chapter touches

The vocabulary above is implemented by a small handful of cooperating
open-source projects. Each one solves a piece of the problem the
others can't.

**[GitHub Actions OIDC][actions-oidc]** is the *identity layer.*
Before any signing can happen, the workflow needs to be able to prove
to an outside party *who it is.* The traditional answer is "the
workflow holds a long-lived secret signing key" — which is exactly
the thing we're trying to avoid (rotation burden, single secret to
steal, etc.). OIDC instead lets the workflow ask GitHub, at runtime,
for a short-lived identity token. The token's contents (`repository`,
`ref`, `workflow`, `sha`, `run_id`) are filled in by GitHub itself
and cryptographically signed. Any party that trusts GitHub's public
keys can therefore trust those claims — without GitHub needing to
hand out long-lived secrets.

**[Sigstore][sigstore]** is the *signing infrastructure.* It accepts
the OIDC token, issues a short-lived signing certificate in return,
and signs the artifact with an ephemeral key that is destroyed within
minutes. Two sub-projects of Sigstore matter here:

- **[Fulcio][fulcio]** — Sigstore's certificate authority. Trades an
  OIDC token for an X.509 cert (~10 min lifetime) whose subject
  identifies the workflow run. This is the piece that lets you
  *sign without owning a long-lived signing key.*
- **[Rekor][rekor]** — Sigstore's public, append-only *transparency
  log.* Every signature Sigstore emits is recorded here. Anyone can
  later confirm that a given signature existed at a given time, was
  issued by Fulcio in response to a real workflow run, and hasn't
  been retroactively forged.

**[SLSA][slsa-spec]** — pronounced *"salsa,"* short for
*Supply-chain Levels for Software Artifacts.* SLSA is a framework
that defines *what an attestation should contain.* Where Sigstore
gives you signed bytes, SLSA tells you what those bytes ought to say:
the artifact's hash, the builder's identity, the source repository,
the commit, the workflow inputs. The actions step this chapter is
about emits attestations in the SLSA Provenance v1 format.

**[in-toto][in-toto]** is the *envelope format* SLSA Provenance lives
inside. SLSA defines the *contents*; in-toto defines the JSON envelope
that wraps those contents and gets signed. You rarely have to write
in-toto yourself, but you'll see the format mentioned in attestation
output (`"_type": "https://in-toto.io/Statement/v1"`).

[actions-oidc]: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
[sigstore]: https://www.sigstore.dev/
[fulcio]: https://docs.sigstore.dev/certificate_authority/overview/
[rekor]: https://docs.sigstore.dev/logging/overview/
[slsa-spec]: https://github.com/slsa-framework/slsa
[in-toto]: https://in-toto.io/

## Why transparency logs matter

Without Rekor, the operational posture would be *"trust us, we signed
this."* With Rekor, anyone — not just the original signer or the
original verifier — can independently confirm:

- the attestation existed at this point in time,
- the signing certificate was issued by Fulcio in response to a real
  workflow run,
- nothing was retroactively forged or backdated.

The motivation is to *reduce centralized trust.* Even if a single
party in the chain were compromised, the public, externally-mirrored
log entries make silent retroactive forgery very hard.

## The step that ties it all together

With the vocabulary in hand, the actual workflow step is surprisingly
small:

```yaml
- name: Attest build provenance
  uses: actions/attest-build-provenance@v2
  with:
    subject-path: 'swift-linux-demo-*.tar.gz'
```

Four lines, six things happening behind the scenes:

1. Compute the SHA-256 hash of each file matching the glob (the
   "subject digest").
2. Use the runner's `id-token: write` permission to ask GitHub for an
   OIDC token. The token's claims include `repository`, `ref`,
   `workflow`, `job_workflow_ref`, `sha`, and `run_id` — and all are
   filled in by GitHub itself.
3. Send the OIDC token to Sigstore's Fulcio CA, which issues a
   short-lived X.509 certificate whose subject identifies the workflow
   run.
4. Generate an in-toto Statement with a SLSA Provenance v1 predicate —
   a JSON document linking the artifact digest to the builder identity,
   source repo, commit, and workflow inputs.
5. Sign the statement with the ephemeral private key, destroy the
   key, and submit the signature + public key to Rekor.
6. Register the resulting bundle (cert + signature + Rekor inclusion
   proof + statement) with GitHub via the Attestations REST API so
   that `gh attestation verify` can find it later.

## Permissions — the three-scope ritual

Three [GitHub Actions permission scopes][actions-permissions] have to
be granted at the workflow or job level for the step above to work:

```yaml
permissions:
  attestations: write   # register the provenance statement with GitHub
  contents: write       # let `gh release create` push assets
  id-token: write       # request the OIDC token Sigstore needs
```

If you remove `id-token: write`, attestation fails with a confusing
error that doesn't mention OIDC at all. Always remember the three
together.

A *job-level* `permissions:` block fully **replaces** the
workflow-level one — it doesn't merge. Anything not listed at the job
level becomes `none` for that job, even if the workflow level granted
it. Two safe patterns:

- Workflow-level grants, no job-level blocks (this repo's choice).
- Workflow-level `permissions: {}` (deny-all) with each job opting in
  to exactly the scopes it needs (GitHub's hardened pattern).

Avoid the middle ground where some jobs have blocks and others don't,
with the workflow level granting permissively — that's how a new job
ends up silently inheriting more than it should.

[actions-permissions]: https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/controlling-permissions-for-github_token

## Why "keyless" — the OIDC trick in one paragraph

Traditional code signing requires a long-lived private key that you
keep secret forever. Sigstore replaces that with three short-lived
things:

- An **OIDC token** (valid minutes) proving the workflow's identity.
- An **X.509 certificate** (~10 min) issued by Fulcio in exchange for
  the OIDC token.
- A **signing keypair** generated in memory and destroyed after a
  single signature.

Trust is rooted not in *"who held the private key"* but in *"who
could obtain an OIDC token with these claims."* The OIDC token can
*only* have `repository: <your-repo>` and `ref: refs/tags/<your-tag>`
if it was actually minted for a real run in that repo on that tag.
GitHub's OIDC issuer is the trust anchor.

Operationally this is huge: there is no key to rotate, no HSM to
fund, no secret to lose.

## What attestation does NOT solve

This is the section most introductions skip, and it's the most
important one for setting expectations.

**1. A compromised maintainer account.** If an attacker has push
access to the repo, they can write malicious code, push it, and
trigger a workflow that builds and attests the malicious binary. The
attestation will be *valid* — it correctly says *"this binary came
from this repo at this commit."* Attestation proves *authenticity*,
not *intent*.

**2. A malicious workflow definition.** If the workflow file itself
does something evil (for example, injecting a backdoor before the
build), you get a perfectly-signed receipt for evil behavior.

**3. A compromised dependency.** If the build pulls in a malicious
upstream package, the resulting binary is honestly attested to be
*"what this workflow produced from this commit"* — *including* the
malicious dependency.

So why is this still valuable? Because it eliminates one entire
attack class: **post-build artifact swap.**

| Threat | Without attestation | With attestation |
|---|---|---|
| Attacker swaps a tarball on the releases page after a legitimate build | Hard to detect — `checksums.txt` can be re-published consistently by the same actor | Verification fails: the new file's hash doesn't match the attestation's subject digest |
| Attacker uploads an unrelated binary claiming "this is v1.2" | No way to disprove the claim from the file alone | No attestation exists for that hash → `gh attestation verify` refuses |
| Attacker steals push access and commits malicious code | Trust is broken silently | Attestation honestly records that the binary was built from a malicious commit. Still bad, but the audit trail is public, permanent, and tied to that exact commit SHA in Rekor |

The trust boundary moves from *"I trust whoever uploaded this file"*
to *"I trust this build identity and workflow definition."* That's a
meaningful shift even though it isn't *"this software is safe."*

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

Much richer trust model, and the chain terminates at a verifiable
Rekor inclusion proof rather than at a tarball on someone's blog.

## Why commit pinning matters

Tags are mutable. A maintainer (or an attacker with push access) can
delete `v1.2.0` and re-push it pointing at a different commit. The
attestation for the *original* `v1.2.0` build still exists and is
still valid for the original binary — but a verifier who only checks
*"came from this repo"* won't notice the swap.

`gh attestation verify --repo <owner>/<repo>` is the easy path; it
passes as long as *any* attestation in the repo matches the binary's
hash. For stronger guarantees, also pin:

- the **commit SHA** (the strongest, most precise pin),
- and/or the **workflow file path** (so a different workflow in the
  same repo can't satisfy verification).

Inspect the verified statement (e.g., with `--format json`) and check
those fields yourself if your policy requires them:

```bash
gh attestation verify swift-linux-demo-linux-x86_64.tar.gz \
  --repo <owner>/<repo> \
  --signer-workflow <owner>/<repo>/.github/workflows/release.yml
```

Verification is only as strong as the policy you actually enforce on
the statement's claims.

## End-user verification

```bash
gh attestation verify swift-linux-demo-linux-x86_64.tar.gz \
  --repo <owner>/<repo>
```

Under the hood, that command:

1. Computes the SHA-256 of your local file.
2. Fetches the attestation bundle from GitHub for that digest.
3. Validates the Sigstore certificate chain back to Fulcio's root.
4. Confirms the Rekor transparency-log inclusion proof.
5. Checks that the certificate's identity claims match the repo you
   passed.
6. (Silently) returns 0 on success.

`gh attestation verify` prints nothing on success by design — only
failures get loud. To see the signed statement (and confirm the
commit SHA, workflow file, and run ID it asserts), add
`--format json` and inspect `verificationResult.statement` and
`signature.certificate`. The [`gh attestation` reference][gh-attest]
documents every option.

[gh-attest]: https://cli.github.com/manual/gh_attestation

## See Also

- <doc:04-DocC-On-Pages>
- The [Sigstore docs][sigstore-docs] — Fulcio, Rekor, Cosign, in
  deeper detail than this chapter.
- The [SLSA v1.0 specification][slsa-v1] — the semantic content of a
  provenance statement.

[sigstore-docs]: https://docs.sigstore.dev/
[slsa-v1]: https://slsa.dev/spec/v1.0/
