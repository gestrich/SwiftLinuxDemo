# ``SwiftLinuxDemoCore``

A working example of every step needed to build, test, release, and
publish a Swift command-line tool for Linux using GitHub Actions.

## What this project covers

Shipping a Swift CLI on Linux through GitHub Actions involves more
moving parts than the equivalent flow on macOS. This repository pulls
a complete working version of that flow into one small project. Every
step a real Linux Swift release needs is here:

- **Cross-platform Swift package setup** — dependency conditions
  (`.when(platforms:)`), target-level platform guards in
  `Package.swift`, source-level `#if os(...)` / `#if canImport(...)`
  guards, and which one solves which problem.
- **A Linux build that runs anywhere** — `swift build` with
  `--static-swift-stdlib` so the resulting binary works on any
  glibc-based host, plus the system packages
  (`libcurl4-openssl-dev`, `libxml2-dev`) that have to be installed
  first.
- **A tag-triggered GitHub Actions release pipeline** — `release.yml`,
  the `release.sh` wrapper that protects against bad tags, and the
  separate `ci.yml` that runs the same build + test on every push.
- **Cryptographic provenance** for every release, in two complementary
  layers — a build-provenance attestation signed via Sigstore during
  the build, plus a GitHub-signed release-integrity attestation for
  immutable releases — together with the `gh` commands a downstream
  user runs to verify them.
- **A DocC documentation site** — the one you're reading — built by a
  workflow in the same repo and deployed to GitHub Pages.

The Swift CLI itself is deliberately small: a handful of `greet`,
`hash`, `info`, and `fetch` subcommands wrapping two library targets.
The interesting subject of this project is the *pipeline* around it,
not the CLI surface.

## The release pipeline at a glance

A release pipeline is the automated path the code takes between
"merged into main" and "running on a user's machine." This project's
pipeline is fully automated and fully public — every step is defined
in a file inside this repo, and each step runs on a clean, single-use
VM that GitHub provisions just for that build.

Four things happen on every release, in order:

1. **Test** — `swift test` runs on a Linux runner against the current
   commit.
2. **Build** — a Linux binary is compiled with the Swift runtime
   statically linked in.
3. **Attest** — that binary is cryptographically tied to the workflow
   run that produced it, with the proof recorded in a public log.
4. **Publish** — the binary, a SHA-256 checksum file, and the
   attestation bundle are attached to a GitHub Release.

Here's the full chain — from the maintainer's first `git push` to the
end user running the verification command — laid out as a tree:

```
scripts/release.sh v1.2.0
  └─ git tag + git push origin v1.2.0
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
                end user: gh attestation verify \
                          swift-linux-demo-linux-x86_64.tar.gz \
                          --repo gestrich/SwiftLinuxDemo
```

## Topics

- <doc:01-Test>
- <doc:02-Building-On-Linux>
- <doc:03-Attestation>
- <doc:04-DocC-On-Pages>
- <doc:05-Discoveries>

### Library types

- ``Greeter``
- ``Hasher``
- ``PlatformInfo``
- ``Fetcher``
