# ``SwiftLinuxDemoCore``

A tiny Swift CLI that demonstrates building, attesting, and shipping a
verifiable Linux binary from GitHub Actions.

## Overview

`swift-linux-demo` is the runnable companion to the [Linux Builds & GitHub
Build Provenance][source-guide] guide. The same patterns the guide describes
— `--static-swift-stdlib`, `actions/attest-build-provenance@v2`,
`gh attestation verify`, OIDC trust roots — live in this repository's
`.github/workflows/release.yml`, where you can read them in one file instead
of inferring them across a larger codebase.

Read the chapters below in order. Each one is anchored in a file in *this*
repository, so you can open the file alongside the chapter and follow along.

[source-guide]: https://github.com/gestrich/AIDevTools/blob/main/docs/guides/linux-builds-and-attestations.html

## Topics

### Walkthrough

- <doc:01-The-Pipeline>
- <doc:02-Building-On-Linux>
- <doc:03-Attestation>
- <doc:04-DocC-On-Pages>
- <doc:05-Discoveries>

### Library types

- ``Greeter``
- ``Hasher``
- ``PlatformInfo``
- ``Fetcher``
