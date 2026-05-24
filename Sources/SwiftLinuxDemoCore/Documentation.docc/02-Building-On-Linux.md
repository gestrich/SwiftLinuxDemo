# Building on Linux

What `--static-swift-stdlib` actually does, why apt-installing
`libcurl4-openssl-dev` and `libxml2-dev` is necessary, and why we still pin
Swift via `swift-actions/setup-swift` when Ubuntu already ships a Swift
toolchain.

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

## Cross-platform crypto

`Hasher.swift` uses SHA-256. On macOS that lives in CryptoKit; on Linux
CryptoKit doesn't exist, so the swift-crypto package provides a drop-in
`Crypto` module with the same API.

The package manifest links swift-crypto only on Linux:

```swift
.product(name: "Crypto", package: "swift-crypto",
         condition: .when(platforms: [.linux]))
```

And the source picks the right module at compile time:

```swift
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
```

Why two layers? Because they solve different problems — the manifest
condition controls which dependency edges are *linked*, and the source
guard controls which import statement is *compiled*. <doc:05-Discoveries>
shows what each error looks like when you strip the guards.

## See Also

- <doc:03-Attestation>
- <doc:05-Discoveries>
