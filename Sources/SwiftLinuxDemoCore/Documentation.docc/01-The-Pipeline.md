# The release pipeline

## What we mean by "pipeline"

A *release pipeline* is the automated path your code takes between
"merged into main" and "running on a user's machine." Every project has
one, even if it's just *"I run `swift build`, tar up the binary, and
attach it to a GitHub Release by hand."* The interesting question is
how much of that path is observable, and how much of it the user has
to take on trust.

This project's pipeline is fully automated and fully public. Every
step is defined in a file inside this repo, so anyone can read what
the pipeline does before running it. Every step runs on a clean,
single-use VM that GitHub provisions just for that build — no
leftover files from previous runs, no pre-installed tooling a third
party could have planted, no persistent state between builds. And the
artifact every step produces is cryptographically tied to the commit
it was built from — so a user holding a downloaded tarball can prove
which commit produced it without trusting anyone along the way.

The chapters that follow zoom into the steps individually. This
chapter introduces the steps themselves, and the three open-source
projects that make the cryptographic half of the pipeline possible.

## What happens on every release

Three things happen on every release, in order:

1. **Build** — a Linux binary is compiled from a specific commit on a
   clean GitHub-hosted runner.
2. **Attest** — that binary is cryptographically tied to the workflow
   run that produced it, with the proof recorded in a public log.
3. **Publish** — the binary, a SHA-256 checksum file, and the
   attestation bundle are attached to a GitHub Release.

Here's the full chain — from the maintainer's first `git push` to the
end user running the verification command — laid out as a tree:

```
scripts/release.sh vX.Y.Z
  └─ git tag + git push origin vX.Y.Z
        └─ release.yml fires on  tags: ['v*']
              ├─ job: test         (swift test on Linux)
              ├─ job: build-linux  (swift build --static-swift-stdlib, tar)
              │   └─ step: attest-build-provenance@v2
              └─ job: release      (gh release create with tarball +
                                    checksums)
                    │
                    ▼
                end user: install.sh
                        │
                        ▼
                end user: gh attestation verify <tarball> --repo <owner/repo>
```

Each of the boxes above has its own chapter. The build step (the heaviest
of the three) is covered by <doc:02-Building-On-Linux>. The attestation
step (the most conceptually loaded) is covered by <doc:03-Attestation>.

## What gives the pipeline its trust properties

The build half of the pipeline above could have been written by anyone
ten years ago — `swift build`, a tarball, a release page. What makes
the rest of the pipeline new is the *trust* half: the ability for a
stranger to verify, after the fact, that a downloaded binary really
came from this exact source.

Three different open-source ecosystems have to cooperate to make that
possible. Each one solves a piece of the problem that the other two
can't.

- **[GitHub Actions OIDC][actions-oidc]** — short for *OpenID Connect.*
  The job of OIDC in this pipeline is to give every workflow run a
  short-lived *identity* that GitHub itself vouches for. Without this,
  the only way for a workflow to "sign" anything would be with a
  long-lived secret stored in the repository — a constant rotation
  burden, and a single secret to steal. OIDC instead lets the workflow
  ask GitHub, at runtime, for a token whose contents (which repo, which
  workflow file, which commit, which run) are filled in by GitHub
  itself and cannot be forged. We'll see in <doc:03-Attestation> who
  consumes that token and what they do with it.

- **[Sigstore][sigstore]** — public, free infrastructure for "keyless"
  software signing. Sigstore takes the GitHub-issued OIDC token in
  exchange for a single-use signing certificate, uses it to sign the
  artifact, throws the signing key away within minutes, and records
  the signature in a public log so anyone can audit it later. This is
  the piece of the pipeline that lets a user verify *bytes match
  workflow run* without anyone having a long-lived signing key.

- **[SLSA][slsa-spec]** — pronounced *"salsa"*, short for
  *Supply-chain Levels for Software Artifacts.* SLSA is a framework
  for *what should be in a provenance statement*: artifact hash,
  builder identity, source repo, commit, workflow inputs. The
  cryptographic plumbing above produces bytes; SLSA defines what those
  bytes should mean.

[actions-oidc]: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect
[sigstore]: https://www.sigstore.dev/
[slsa-spec]: https://github.com/slsa-framework/slsa

## Why a tag, and not a branch?

Tags are *conventionally* immutable: a branch is expected to advance,
while a tag is expected to be fixed once pushed. That convention is
what makes a tag a useful release trigger — readers and tooling treat
a name like `v1.2.0` as the name of a single artifact, not a moving
target. If `v1.2.0` ever changes, something has gone wrong.

The attestation closes the loop by pinning the underlying *commit SHA*
into the signed statement. Even if someone later force-moved
`v1.2.0` to a different commit, the original attestation still
references the original commit. <doc:03-Attestation> covers how that
commit pin is used during verification.

The workflow trigger is the conventional idiom for "release on tag push":

```yaml
on:
  push:
    tags:
      - 'v*'
```

`scripts/release.sh` is the safety wrapper on top: it refuses any tag
that doesn't start with `v` (matching the workflow's `v*` glob),
refuses a dirty working tree, refuses a duplicate tag, then runs
`git tag` + `git push origin <tag>`. If those two glob patterns ever
drift, the script and the workflow silently diverge — keep them
aligned.

## Why Linux only?

This project deliberately ships a Linux-only release. A real
production tool would usually ship at least macOS and Windows too, but
the narrower scope keeps every step of the workflow short enough to
read in a single sitting. Adding a `build-macos` job is a copy-and-edit
exercise — the attestation, release, and verification pieces work the
same way on each platform.

## Where the pipeline lives in this repo

- `.github/workflows/release.yml` — the workflow that runs the pipeline.
- `scripts/release.sh` — the tag wrapper.
- `scripts/install.sh` — the downstream installer.
- `Package.swift` — the product and target definitions the workflow
  builds.

## See Also

- <doc:02-Building-On-Linux>
- <doc:03-Attestation>
