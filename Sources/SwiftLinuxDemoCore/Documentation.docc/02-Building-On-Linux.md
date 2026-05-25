# Build

## What's different about a Linux Swift build

Swift on Linux behaves differently from Swift on macOS in a few small
but important ways, and a CI workflow that doesn't account for them
either won't build at all or will produce a binary that fails to run
on anyone else's machine.

The Linux-specific concerns boil down to three: a build flag that
bakes the Swift runtime into the binary, a couple of system packages
that have to be installed before the Swift compiler can finish, and a
pin on the Swift toolchain so a runner image upgrade doesn't silently
change which compiler built the release. Each one shows up in a
matching line of YAML inside `.github/workflows/release.yml`.

## The build command

```yaml
- name: Build
  run: swift build -c release --product swift-linux-demo --static-swift-stdlib
```

Three flags, each with a specific job:

- `-c release` — optimized build, not debug.
- `--product swift-linux-demo` — the executable product declared in
  `Package.swift`. Without this, `swift build` builds everything; with it,
  we only build the CLI artifact we ship.
- `--static-swift-stdlib` — statically link the Swift runtime libraries
  into the binary.

## Why `--static-swift-stdlib`?

Without the flag, the binary dynamically links against `libswiftCore.so`,
`libFoundation.so`, and friends — files that exist on a machine where the
Swift toolchain is installed, but not on a stock Ubuntu box. Run the binary
there and it dies with "library not found."

With the flag, the Swift runtime is baked into the binary. The file is
bigger, but it runs on essentially any glibc-based Linux host — which is
exactly what we want for a downloadable CLI.

The macOS build of any Swift CLI doesn't need this flag, because macOS ships
a Swift runtime with the OS. This repo doesn't ship a macOS build at all, so
the consideration only matters here for context.

## Why apt-install `libcurl4-openssl-dev` and `libxml2-dev`?

Foundation on Linux is [swift-corelibs-foundation][corelibs] — a from-scratch
reimplementation of Apple's Foundation that delegates to C libraries instead
of Apple frameworks:

- `URLSession` on Linux is backed by **libcurl**.
- `FoundationXML` on Linux is backed by **libxml2**.

This repo's `Fetcher.swift` calls `URLSession.shared.data(for:)`. On Linux
that pulls in Foundation's libcurl-backed URLSession, which means the build
needs the curl headers (`curl.h`) — not just the runtime `.so`. That's the
`-dev` suffix: `libcurl4-openssl-dev` includes the development headers that
Swift's C-interop shims (`_CFURLSessionInterface`) build against.

The `ubuntu-latest` image ships the runtime libs but not the `-dev` headers.
The apt install line is exactly that gap-filler.

```yaml
- name: Install system dependencies
  run: sudo apt-get install -y libcurl4-openssl-dev libxml2-dev
```

[corelibs]: https://github.com/swiftlang/swift-corelibs-foundation

## Why pin Swift if Ubuntu ships it?

Both `ubuntu-22.04` and `ubuntu-24.04` runner images ship Swift preinstalled
(at the time of writing, Swift 6.3.x is in `ubuntu-latest`). If we removed
the `setup-swift` step entirely, the Linux build would still find a Swift
toolchain — just whichever one the runner image happens to ship.

Two reasons to pin:

1. Runner image bumps roll out gradually over 1–2 months and can change the
   bundled compiler version. Without a pin, your build is at the mercy of
   that rollout — a release tagged today might compile against a different
   Swift than the same commit tagged next month.
2. The pin gives you one knob to bump intentionally, with a commit that
   records the change.

```yaml
- name: Install Swift
  uses: swift-actions/setup-swift@v2
  with:
    swift-version: '6.2'
```

## Three conditional patterns, three different jobs

Cross-platform Swift packages usually need three different
"this-only-applies-on-platform-X" knobs, each guarding against a
different failure mode. This repo demonstrates all three:

**1. `.when(platforms: [.linux])` on a dep edge** — used when the
dependency itself compiles everywhere, but you only want it *linked* on
some platforms. swift-crypto is the canonical case:

```swift
.product(name: "Crypto", package: "swift-crypto",
         condition: .when(platforms: [.linux]))
```

**2. `#if os(...)` around a `.target(name:)` declaration** — used when
the target's source files themselves can't compile on the other
platform (because they `import` a framework that doesn't exist there).
This repo has two such targets: `AppKitGreeter` (imports AppKit,
macOS-only) and `GlibcGreeter` (imports Glibc, Linux-only):

```swift
#if os(macOS)
let platformExclusiveTargets: [Target] = [.target(name: "AppKitGreeter")]
let platformExclusiveCoreDeps: [Target.Dependency] = ["AppKitGreeter"]
#elseif os(Linux)
let platformExclusiveTargets: [Target] = [.target(name: "GlibcGreeter")]
let platformExclusiveCoreDeps: [Target.Dependency] = ["GlibcGreeter"]
#endif
```

The dependency *references* (`platformExclusiveCoreDeps`) live inside
the same `#if` block — that's load-bearing. Referencing a manifest-
gated target's name from an un-gated context fails manifest
evaluation. See <doc:05-Discoveries> for the literal error.

**3. `#if os(...)` or `#if canImport(...)` inside source** — used when
one source file picks between platform-specific implementations:

```swift
// Sources/SwiftLinuxDemoCore/PlatformReport.swift
#if os(macOS)
import AppKitGreeter
#elseif os(Linux)
import GlibcGreeter
#endif
```

```swift
// Sources/SwiftLinuxDemoCore/Hasher.swift
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
```

`#if os(X)` is a hard assertion about the host OS. `#if canImport(X)`
asks the softer question "is this module available right now?" which
auto-adapts if the named module ever ships on a new platform. Prefer
`canImport` when the module is the thing you care about.

The three patterns *compose* — they don't substitute for each other.
<doc:05-Discoveries> empirically demonstrates the distinct failure mode
each one prevents on the Linux runner.

## See Also

- <doc:03-Attestation>
- <doc:05-Discoveries>
