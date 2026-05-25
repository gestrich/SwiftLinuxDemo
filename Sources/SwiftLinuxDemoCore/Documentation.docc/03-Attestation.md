# Releases anyone can verify

## The supply-chain trust problem

Every binary on every release page on the internet has the same
problem: you can't see what's inside. Even when the source code is
public and well-audited, the executable on the download page is
opaque. It could have been built from a different commit than the
tag suggests, modified after the build finished, or replaced wholesale
with something malicious — and from the outside, there's no way to
tell.

A whole ecosystem of open-source projects has grown up over the last
few years to address this. The four-line workflow step further down
plugs straight into that ecosystem, producing a release that anyone
can verify back to a specific commit and workflow run — no shared
secret, no maintainer-managed signing key, no trust placed in the
CDN that served the bytes.

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

## Four projects make this work

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
the commit, the workflow inputs. The
`actions/attest-build-provenance` step below emits attestations in
the SLSA Provenance v1 format.

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

## Two attestations, two questions

A release published by this repo carries **two independent
attestations** — they're built on the same cryptographic substrate
(Sigstore, in-toto envelopes, transparency log) but they answer
different questions and are signed by different parties.

| | Build-provenance attestation | Release-integrity attestation |
|---|---|---|
| Answers | *"Was this byte sequence built by the claimed workflow run?"* | *"Is this the official immutable release for this tag, and is this file one of its named assets?"* |
| Emitted by | `actions/attest-build-provenance@v2`, during the build job | GitHub itself, when an immutable release is published |
| Signed using | Public [Sigstore][sigstore] (Fulcio CA at `sigstore.dev`) | GitHub's own Fulcio instance (`O=GitHub, Inc.`) |
| Signer identity (SAN) | `…/.github/workflows/release.yml@refs/tags/v1.2.0` | `https://dotcom.releases.github.com` |
| Predicate type | `https://slsa.dev/provenance/v1` | `https://in-toto.io/attestation/release/v0.2` |
| Subject | the file + its SHA-256 | the tag PURL + each named asset's SHA-256 |
| Verified with | `gh attestation verify <file> --repo gestrich/SwiftLinuxDemo` | `gh release verify v1.2.0 --repo gestrich/SwiftLinuxDemo` / `gh release verify-asset v1.2.0 <file> --repo gestrich/SwiftLinuxDemo` |
| Available since | August 2023 (GA) | October 2025 (GA) |

The two layers are *complementary*, not redundant. The
build-provenance attestation lets a user trace bytes back to a
specific workflow run and commit — strong supply-chain story, weak
UX (you have to know to verify before installing, and you have to
have downloaded the right file from the right place). The
release-integrity attestation closes the UX gap: as a *consumer*,
you ask GitHub one question — *"is this the official immutable
release for v1.2.0?"* — and GitHub answers with a signed receipt.

The next two sections walk through each path. <doc:03-Attestation#End-user-verification>
ties them together with the two commands you'd run as a downstream
user.

## Path A — the build-provenance attestation

With the vocabulary in hand, the actual workflow step is surprisingly
small:

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

## Path B — the release-integrity attestation

GitHub generates a *second* attestation whenever an
[immutable release][immutable-docs] is published. There's no workflow
step to write for this one — the only setup is a per-repository
toggle.

[immutable-docs]: https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases

### Enabling immutable releases

Either through the UI (`Settings → General → Releases → Enable
release immutability`) or in one shot via the REST API:

```bash
gh api -X PUT /repos/gestrich/SwiftLinuxDemo/immutable-releases
# → {"enabled":true,"enforced_by_owner":false}
```

State can be read back with the same endpoint and a plain `GET`. The
toggle applies only to releases created *after* it's flipped — older
releases stay mutable and have no release-integrity attestation. (For
this repo, `v0.1.0` predates the toggle and only carries a build-
provenance attestation; `v0.2.0` onward have both.)

Once immutability is on, every release that gets published triggers
GitHub to:

- lock the release metadata, the asset list, and the underlying Git
  tag against further changes,
- compute a release-integrity attestation whose subject is the tag's
  [purl][purl] plus each asset name+sha256, and
- sign that attestation with GitHub's own Fulcio CA, with a SAN of
  `https://dotcom.releases.github.com`.

You can confirm a given release is immutable via the API:

```bash
gh release view v1.2.0 --repo gestrich/SwiftLinuxDemo --json isImmutable
# → {"isImmutable":true}
```

[purl]: https://github.com/package-url/purl-spec

### Verifying with `gh release verify` and `verify-asset`

These two commands are the consumer-facing half of the
release-integrity story. Both ship with [GitHub CLI][gh-cli] (the
`gh release verify` subcommand was added in the same release wave as
the public preview of immutable releases in mid-2025; `gh 2.92+`
includes them).

[gh-cli]: https://cli.github.com/

**`gh release verify <tag>`** asks "does an immutable-release
attestation exist for this tag, and is it valid?" It does *not*
verify any local file:

```
$ gh release verify v0.2.0 --repo gestrich/SwiftLinuxDemo
Resolved tag v0.2.0 to sha1:55d3a0b853630a9c2275ca5d0113ec54199bfb05
Loaded attestation from GitHub API
✓ Release v0.2.0 verified!

Assets
checksums.txt                          sha256:abc01f969382a2eddb…
swift-linux-demo-linux-x86_64.tar.gz   sha256:98b80df0bdb244aa…
```

The output prints the set of subject digests the attestation covers
— that's effectively GitHub's signed answer to *"what bytes
constitute this release."*

**`gh release verify-asset <tag> <file>`** is the everyday command.
It SHA-256s your local file, then asks GitHub whether that hash is in
the release-integrity attestation for the named tag:

```
$ gh release verify-asset v0.2.0 ./swift-linux-demo-linux-x86_64.tar.gz \
    --repo gestrich/SwiftLinuxDemo
Calculated digest for swift-linux-demo-linux-x86_64.tar.gz: sha256:98b80df0bdb244aa…
Resolved tag v0.2.0 to sha1:55d3a0b…
Loaded attestation from GitHub API

✓ Verification succeeded! swift-linux-demo-linux-x86_64.tar.gz is present in release v0.2.0
```

And the tamper case is exactly what you'd hope for:

```
$ gh release verify-asset v0.2.0 ./poisoned.tar.gz --repo gestrich/SwiftLinuxDemo
attestation for v0.2.0 does not contain subject sha256:97f2b5cb…
$ echo $?
1
```

— a clear refusal, an explicit hash mismatch, and a non-zero exit code.

### How the release attestation differs from build provenance

The two attestations look superficially similar (both are in-toto
statements signed via Sigstore), but their *trust roots* and
*claims* differ in ways that matter for what each one actually
proves:

- **Different CA.** Build provenance uses public Sigstore (Fulcio at
  `sigstore.dev`). Release integrity uses GitHub's *own* Fulcio
  instance (`O=GitHub, Inc.`). The release-integrity flow's trust
  root is therefore GitHub itself — not a third-party CA. That's a
  weaker decentralization story but a simpler operational one.
- **Different signer identity.** Build provenance's signing
  certificate names the workflow file
  (`.../.github/workflows/release.yml@refs/tags/v0.2.0`). Release
  integrity's certificate names GitHub
  (`https://dotcom.releases.github.com`). A consumer checking the
  release-integrity attestation has no opinion about *which workflow
  built the bytes* — they're trusting GitHub's assertion about
  *"what's in this release"*.
- **Different predicate.** Build provenance uses
  [SLSA Provenance v1][slsa-v1]; release integrity uses
  `https://in-toto.io/attestation/release/v0.2`. The release
  predicate's `subject[]` includes the tag's package-URL plus each
  asset by name + sha256 — exactly the shape that makes
  `verify-asset` cheap to implement.

[slsa-v1]: https://slsa.dev/spec/v1.0/

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

Tags are conventionally immutable but not *technically* immutable
unless you've enabled the immutable-releases setting described above.
Without it, a maintainer (or an attacker with push access) can delete
`v1.2.0` and re-push it pointing at a different commit. The build-
provenance attestation for the *original* `v1.2.0` build still
exists and is still valid for the original binary — but a verifier
who only checks *"came from this repo"* won't notice the swap.

`gh attestation verify --repo gestrich/SwiftLinuxDemo` is the easy
path; it passes as long as *any* attestation in the repo matches the
binary's hash. For stronger guarantees, also pin:

- the **commit SHA** (the strongest, most precise pin),
- and/or the **workflow file path** (so a different workflow in the
  same repo can't satisfy verification).

Inspect the verified statement (e.g., with `--format json`) and check
those fields yourself if your policy requires them, or use the
`--signer-workflow` flag to pin the workflow file inline:

```bash
gh attestation verify swift-linux-demo-linux-x86_64.tar.gz \
  --repo gestrich/SwiftLinuxDemo \
  --signer-workflow gestrich/SwiftLinuxDemo/.github/workflows/release.yml
```

The release-integrity path (Path B above) sidesteps the tag-mutability
problem entirely: enabling immutable releases makes the tag itself
un-rewritable, and `gh release verify-asset` ties the bytes you have
to the *immutable* tag, not just "any tag in this repo." If you only
need one of the two pins, the release path is the lower-friction
choice. If you also need to assert *which workflow built the bytes*,
keep the build-provenance verify alongside it.

Verification is only as strong as the policy you actually enforce on
the statement's claims.

## End-user verification — which command, when

Once you understand the two attestation paths, the practical question
for a downstream user is *which verify command do I run?* The honest
answer is *"probably both, in a script,"* because they answer
different questions.

### The two-command verify

```bash
# (1) Did this file come from the official immutable release for this tag?
gh release verify-asset v1.2.0 swift-linux-demo-linux-x86_64.tar.gz \
  --repo gestrich/SwiftLinuxDemo

# (2) Was the file built by the workflow definition we expect?
gh attestation verify swift-linux-demo-linux-x86_64.tar.gz \
  --repo gestrich/SwiftLinuxDemo
```

`verify-asset` is the consumer-friendly check. It's the one to put
in a `curl … | sh`-style installer or a `README` quickstart. It
proves:

- there is an immutable release in this repo with this tag,
- the bytes on disk are byte-for-byte one of that release's named
  assets,
- the release-integrity attestation backing those claims is signed by
  GitHub and recorded in a transparency log.

`gh attestation verify` is the supply-chain check. It's the one to
add when you care about *which workflow built the bytes*, not just
that they were officially released. It proves:

- there is a build-provenance attestation in this repo whose subject
  digest matches the bytes on disk,
- that attestation was signed by Sigstore in response to a real
  GitHub Actions run,
- the workflow file, commit SHA, and run ID are recorded in the
  signed statement (use `--format json` to inspect them).

For maximum strictness, also pass `--signer-workflow` to pin which
workflow file is allowed to produce attestations (otherwise *any*
workflow in the repo qualifies):

```bash
gh attestation verify swift-linux-demo-linux-x86_64.tar.gz \
  --repo gestrich/SwiftLinuxDemo \
  --signer-workflow gestrich/SwiftLinuxDemo/.github/workflows/release.yml
```

### A note on silent success

`gh attestation verify` prints nothing on success by default — only
failures get loud. Add `--format json` to see the signed statement
and confirm the commit SHA, workflow file, and run ID it asserts.

`gh release verify` and `gh release verify-asset` are noisier on
success — both print a `✓` line, the resolved tag, and (for
`verify`) the asset digests they cover. Either way, the exit code is
the authoritative signal in scripts.

The full reference for both is in the
[`gh attestation`][gh-attest] and [`gh release`][gh-release] CLI
manuals.

[gh-attest]: https://cli.github.com/manual/gh_attestation
[gh-release]: https://cli.github.com/manual/gh_release

## See Also

- <doc:04-DocC-On-Pages>
- The [Sigstore docs][sigstore-docs] — Fulcio, Rekor, Cosign, in
  deeper detail than what's covered here.
- The [SLSA v1.0 specification][slsa-v1] — the semantic content of a
  provenance statement.

[sigstore-docs]: https://docs.sigstore.dev/
[slsa-v1]: https://slsa.dev/spec/v1.0/
