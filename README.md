# SwiftLinuxDemo

A tiny Swift CLI that demonstrates building, attesting, and shipping a
verifiable Linux binary from GitHub Actions.

It is the runnable companion to the
[Linux Builds & GitHub Build Provenance][source-guide] guide — every pattern
the guide describes (`--static-swift-stdlib`,
`actions/attest-build-provenance@v2`, `gh attestation verify`, OIDC trust
roots) lives here in one small repo you can read end to end.

Read the full walkthrough on the **[DocC site][docs]** — five chapters
covering the pipeline, building on Linux, attestation, DocC-on-Pages, and
a Discoveries chapter that quotes the literal Linux compiler errors each
guard in `Package.swift` prevents.

[source-guide]: https://github.com/gestrich/AIDevTools/blob/main/docs/guides/linux-builds-and-attestations.html
[docs]: https://gestrich.github.io/SwiftLinuxDemo/documentation/swiftlinuxdemocore/

## Install (Linux x86_64)

```bash
curl -fsSL https://raw.githubusercontent.com/gestrich/SwiftLinuxDemo/main/scripts/install.sh | sh
```

Or download a release tarball manually from the [Releases page][releases]
and extract the binary.

[releases]: https://github.com/gestrich/SwiftLinuxDemo/releases

## Cryptographically verify the binary

Two verification paths cover two different trust questions. Run both for
the strongest guarantee:

```bash
# (1) Was this file in the official immutable release for this tag?
gh release verify-asset v0.2.0 swift-linux-demo-linux-x86_64.tar.gz \
  --repo gestrich/SwiftLinuxDemo

# (2) Was this file built by this repo's release workflow?
gh attestation verify swift-linux-demo-linux-x86_64.tar.gz \
  --repo gestrich/SwiftLinuxDemo
```

The first command asks GitHub *"is this byte sequence one of the named
assets in the immutable release for v0.2.0?"* — signed by GitHub itself.
The second asks Sigstore *"was this byte sequence built by the workflow
file in this repo, on this commit?"* — signed during the build.

The DocC chapter [Releases anyone can verify][docs-verify] explains the
two-attestation model in depth, including what each one *doesn't* prove
and when to reach for which.

[docs-verify]: https://gestrich.github.io/SwiftLinuxDemo/documentation/swiftlinuxdemocore/03-attestation/

## Use it

```bash
swift-linux-demo greet --name "World"
swift-linux-demo hash "abc"
swift-linux-demo info
swift-linux-demo fetch https://example.com
```

## Build it yourself

```bash
swift build
swift test
swift run swift-linux-demo info
```

On macOS the binary works the same way, but no macOS release is shipped —
this project intentionally demonstrates the Linux release path only.

## Project layout

```
Package.swift
Sources/
  SwiftLinuxDemo/         # thin ArgumentParser CLI shell
  SwiftLinuxDemoCore/     # library with the actual logic + DocC catalog
Tests/
  SwiftLinuxDemoCoreTests/
.github/workflows/
  ci.yml                  # build + test on every push
  release.yml             # tag-triggered Linux release with attestation
  docs.yml                # build DocC + deploy to GitHub Pages
  experiments.yml         # manually-triggered: capture compiler errors
scripts/
  release.sh              # tag-push wrapper (refuses non-v* / dirty / dupes)
  install.sh              # end-user installer
TODO.md                   # build plan driven by /loop
```

## Cut a release

```bash
./scripts/release.sh v0.1.0
```

That pushes the tag, which triggers `release.yml`. The workflow runs the
tests, builds the static-stdlib Linux binary, attests it via Sigstore, and
creates the GitHub Release with the tarball + checksums.
