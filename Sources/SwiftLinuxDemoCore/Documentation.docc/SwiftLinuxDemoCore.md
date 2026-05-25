# ``SwiftLinuxDemoCore``

A working example of every step needed to build, test, release, and
publish a Swift command-line tool for Linux using GitHub Actions.

## What this project covers

Shipping a Swift CLI on Linux through GitHub Actions involves more
moving parts than the equivalent flow on macOS. This repository pulls
a complete working version of that flow into one small project. Every
step a real Linux Swift release needs is here:

- **Cross-platform Swift package setup** — how to condition your code
  to compile on Linux, since you're usually sharing the same codebase
  with macOS.
- **A Linux build that runs anywhere** — producing a binary that
  works on any Linux machine, not just the one it was built on,
  along with the system-library surprises Linux brings that you
  never have to think about on macOS.
- **A tag-triggered GitHub Actions release pipeline** — pushing a
  version tag is the one gesture that triggers a release, with the
  same build and tests also running automatically on every push to
  catch problems before tag time.
- **Cryptographic provenance** for every release — so anyone who
  downloads a binary can independently prove it really came from
  this repository's build, not from a tampered or impersonated
  release page.
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
