# ``SwiftLinuxDemoCore``

A working example of every step needed to build, test, release, and
publish a Swift command-line tool for Linux using GitHub Actions —
written small enough to read end to end.

## What this project covers

Shipping a Swift CLI on Linux through GitHub Actions involves more
moving parts than the equivalent flow on macOS, and the documentation
for each part lives in a different place (Swift Package Manager,
GitHub Actions, GitHub Pages, Sigstore, SLSA, …). This repository pulls
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

## Topics

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
