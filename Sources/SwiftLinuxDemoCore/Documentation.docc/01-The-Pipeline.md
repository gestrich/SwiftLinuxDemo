# Pipeline anatomy

A single `git tag v0.1.0` triggers seven steps that end with a downstream user
verifying the binary cryptographically.

## The flow

```
scripts/release.sh v0.1.0
  └─ git tag + git push origin v0.1.0
        └─ release.yml fires on  tags: ['v*']
              ├─ job: test         (swift test on Linux)
              ├─ job: build-linux  (swift build --static-swift-stdlib, tar)
              │   └─ step: attest-build-provenance@v2 (OIDC → Sigstore → Rekor)
              └─ job: release      (gh release create with tarball + checksums)
                    │
                    ▼
                end user: install.sh
                        │
                        ▼
                end user: gh attestation verify <tarball> --repo gestrich/SwiftLinuxDemo
```

Three pieces of foundational tech make this safe:

- **GitHub Actions OIDC** — each workflow run gets a short-lived OpenID
  Connect identity token signed by GitHub. The token's claims (`repository`,
  `ref`, `workflow`, `sha`, `run_id`) are baked in by GitHub itself, so no
  long-lived signing key needs to exist.
- **Sigstore** — public infrastructure that exchanges the OIDC token for a
  short-lived X.509 certificate, signs the artifact with an ephemeral key,
  destroys the key, and publishes the signature to the Rekor transparency
  log. The whole signing keypair lives for under ten minutes.
- **SLSA build provenance** — the schema defining what a "provenance
  statement" must contain (artifact digest, builder, source repo, commit,
  workflow inputs). `actions/attest-build-provenance` emits an in-toto
  attestation in this format.

## Why a tag?

Tags are immutable names for a single commit. A branch can advance; a tag is
fixed once pushed. That's exactly the property a release artifact's
provenance needs — the attestation can confidently claim "this binary was
built from commit X" because the tag will always resolve to commit X.

The workflow trigger is the literal idiom for "release on tag push":

```yaml
on:
  push:
    tags:
      - 'v*'
```

`scripts/release.sh` is the safety wrapper on top: it refuses any tag that
doesn't start with `v` (matching the workflow's `v*` glob), refuses a dirty
working tree, refuses a duplicate tag, then runs `git tag` + `git push origin
<tag>`. If those two glob patterns ever drift, the script and the workflow
silently diverge.

## What this repo strips out

The source guide describes a macOS + Linux matrix. This repo is intentionally
**Linux-only**. The narrower scope makes every step in the workflow easier
to read; if you want the macOS half, the source guide has it.

## Where it lives in this repo

- `.github/workflows/release.yml` — the workflow.
- `scripts/release.sh` — the tag wrapper.
- `scripts/install.sh` — the downstream installer.
- `Package.swift` — the product/target definitions the workflow builds.

## See Also

- <doc:02-Building-On-Linux>
- <doc:03-Attestation>
