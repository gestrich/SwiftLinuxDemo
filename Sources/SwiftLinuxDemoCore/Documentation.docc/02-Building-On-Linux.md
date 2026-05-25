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

- [`-c release`][build-config-docs] — selects the *release* build
  configuration. Without it, `swift build` produces a debug binary
  that's slower and bigger. Documented in
  *[Using build configurations][build-config-docs]* on swift.org.
- [`--product swift-linux-demo`][products-docs] — names a single
  executable product from `Package.swift` to build. Without it,
  `swift build` builds every target in the package; with it, only
  the CLI artifact we actually ship gets compiled.
- [`--static-swift-stdlib`][static-stdlib] — statically links the
  Swift runtime libraries into the binary. The next section is
  entirely about why this one matters on Linux.

[build-config-docs]: https://docs.swift.org/swiftpm/documentation/packagemanagerdocs/usingbuildconfigurations/
[products-docs]: https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html#Product
[static-stdlib]: https://www.swift.org/documentation/articles/static-linux-getting-started.html

## Why `--static-swift-stdlib`?

On macOS and iOS, the Swift runtime is part of the operating system.
The same dynamic libraries (`libswiftCore.dylib`, `libFoundation.dylib`,
and the rest) live in `/usr/lib/swift` on every Apple device, so any
Swift binary you compile can rely on them being present at runtime.
This is invisible — you never have to think about it.

Linux works differently. There is no system-shipped Swift runtime,
because Swift isn't part of any Linux distribution's base install.
The Swift runtime libraries only exist on a Linux machine where
someone explicitly installed a Swift toolchain. So a dynamically-
linked Swift binary built on Linux runs fine on the build machine
(which has the toolchain), and dies with `error while loading shared
libraries: libswiftCore.so` on any stock Ubuntu, Debian, or Alpine
box that doesn't.

`--static-swift-stdlib` solves this by baking the Swift runtime
libraries into the binary itself. The output is bigger (this repo's
`swift-linux-demo` ends up around ~30 MB tarballed) but it runs on
essentially any glibc-based Linux host with no prerequisite install
— which is exactly what a downloadable CLI needs.

The macOS build of any Swift CLI doesn't need this flag, because
macOS does ship the runtime. This repo doesn't produce a macOS
release, so the consideration only matters here for context.

For the deeper background, see *[Getting Started with the Static
Linux SDK][static-stdlib]* on swift.org, which also covers a stricter
mode (the Static Linux SDK) that statically links the C library
itself so the resulting binary doesn't even need glibc.

## Why apt-install `libcurl4-openssl-dev` and `libxml2-dev`?

This is the first surprise for anyone coming from macOS or iOS
development: on Apple platforms, "system frameworks" like
`Foundation`, `URLSession`, and `XMLParser` are bundled with the OS
itself. You import them and they're just *there*. You never install
a system library to make `URLSession` work — Apple ships everything
through the SDK and the runtime.

Linux is closer to the metal. There's no concept of a vendor-bundled
SDK that ships every dependency at once. Each "system framework"
you'd take for granted on macOS is implemented in terms of standard
open-source C libraries that may or may not be installed, and that
your build needs to be able to find — both at compile time (for the
headers) and at runtime (for the `.so` files).

[swift-corelibs-foundation][corelibs] is the open-source
reimplementation of Apple's Foundation that ships with Swift on
Linux. It exposes the same `Foundation.URLSession` and
`Foundation.XMLParser` API surface you're used to, but instead of
calling Apple's `CFNetwork` and `libxml2.dylib` (which only exist on
macOS), it delegates to two specific C libraries that have been
shipping on every Linux distribution for decades:

- `URLSession` on Linux is backed by **libcurl** (the same library
  behind the `curl` CLI).
- `FoundationXML` on Linux is backed by **libxml2** (the GNOME
  project's XML parser).

This repo's `Fetcher.swift` calls `URLSession.shared.data(for:)`.
On Linux that pulls in Foundation's libcurl-backed URLSession, which
means the build needs the curl C *headers* (`curl.h`) — not just the
runtime `.so`. That's what the `-dev` suffix is for:
`libcurl4-openssl-dev` is the Debian/Ubuntu package that includes
the development headers Swift's C-interop shims
(`_CFURLSessionInterface`) build against.

The `ubuntu-latest` runner image ships the runtime libs but not the
`-dev` headers, so the apt install line is exactly that gap-filler:

```yaml
- name: Install system dependencies
  run: sudo apt-get install -y libcurl4-openssl-dev libxml2-dev
```

If you ever add a Foundation feature that pulls in a third C
dependency (e.g. `FoundationCalendar` brings in `tzdata`), the
symptom is a confusing C-interop error at build time — usually
along the lines of `module 'CIcu' is not available`. The fix is
almost always to install one more `-dev` package via the same
mechanism.

[corelibs]: https://github.com/swiftlang/swift-corelibs-foundation

## Do we even need `setup-swift`?

Both `ubuntu-22.04` and `ubuntu-24.04` runner images ship Swift
preinstalled. Removing the `setup-swift` step entirely — and just
calling `swift build` directly — does work today. The experiments
workflow has two jobs (`EXP-G` and `EXP-H`) that test exactly this,
on each Ubuntu image, with no `setup-swift` step at all:

| Image | Preinstalled Swift | `swift build` | `swift test` |
|---|---|---|---|
| `ubuntu-22.04` | `6.3.1` at `/usr/local/bin/swift` | ✓ 84 s | ✓ |
| `ubuntu-24.04` | `6.3.1` at `/usr/local/bin/swift` | ✓ 73 s | ✓ |

So why keep the step? Three reasons, in increasing order of how much
you should care about each one:

1. **Version pin.** Without `setup-swift`, the build uses whichever
   Swift the runner image happens to ship. Runner image bumps roll
   out gradually over 1–2 months and can change the bundled compiler
   version. A release tagged today might compile against a different
   Swift than the same commit tagged next month. With the pin, the
   compiler version only changes when you (or a CI bot) bump it
   intentionally, with a commit that records the change.

2. **Cross-version testing.** A matrix build against multiple Swift
   versions (e.g., 6.2 + 6.3 + the nightly main) needs *some* way
   to install non-image-default toolchains. `setup-swift` is the
   straightforward answer; without it, you'd be using
   [`swiftly`][swiftly] (the official Swift toolchain installer) by
   hand.

3. **Parity with local dev.** If your `Package.swift`'s
   `swift-tools-version` is ahead of what the image ships,
   `setup-swift` is what unblocks the build. (This repo's manifest
   declares `swift-tools-version: 6.2`, which the image satisfies,
   so it isn't a concern *here* — but pinning insulates you against
   a future bump.)

If you don't care about any of those — for example, a hobby project
where "compiles with whatever Ubuntu has" is fine — pinning
`ubuntu-22.04` or `ubuntu-24.04` (rather than `ubuntu-latest`) and
dropping the `setup-swift` step is a valid lighter setup. The cost
is a slower discovery of Swift version bumps and one fewer knob
to control.

This repo keeps the step:

```yaml
- name: Install Swift
  uses: swift-actions/setup-swift@v2
  with:
    swift-version: '6.2'
```

The `setup-swift` action is community-maintained at
[swift-actions/setup-swift][setup-swift]. It uses the same
[`swiftly`][swiftly] installer under the hood, but with the
GitHub-Actions ergonomics (caching, tool version output, matrix
support) wrapped around it.

[setup-swift]: https://github.com/swift-actions/setup-swift
[swiftly]: https://www.swift.org/install/linux/

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
