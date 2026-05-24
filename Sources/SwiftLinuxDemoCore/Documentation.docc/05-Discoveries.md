# Discoveries

Each conditional in `Package.swift` and the source code, removed in
isolation on the Linux runner — with the literal compiler error each one
prevents.

## Method

Theory is fine. Compiler errors are better. The errors in this chapter are
captured by `.github/workflows/experiments.yml`, which runs one job per
guard, mutates files with `sed`, builds, and uploads the build's stderr as
an artifact.

If you want to re-run the experiments yourself, you can trigger them with
`gh workflow run experiments.yml`.

## Two guards, two layers

The source guide ("Discoveries 14.1") distinguishes:

- **`.when(platforms:)`** in the manifest — filters which dependency edges
  are *linked* per build destination.
- **`#if os(...)` or `#if canImport(...)`** in source — filters which lines
  the compiler sees.

In this repo, the relevant guards are:

```swift
// Package.swift
.product(name: "Crypto", package: "swift-crypto",
         condition: .when(platforms: [.linux]))
```

```swift
// Sources/SwiftLinuxDemoCore/Hasher.swift
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
```

The three experiments below remove each guard in turn.

## Experiment 1 — strip `.when(platforms: [.linux])`

> Status: pending experiment run. After `experiments.yml` executes, this
> section will quote the literal compiler output. The expected outcome on
> Linux is that the build still passes (linking `Crypto` everywhere is
> harmless on Linux), and on macOS, depending on the swift-crypto version,
> we either get nothing (just an extra unused dependency in the graph) or a
> name-ambiguity error if a file in the package imports both `Crypto` and
> `CryptoKit`. The empirical result will replace this paragraph.

## Experiment 2 — strip `#if canImport(CryptoKit)`, force `import CryptoKit`

> Status: pending experiment run. The expected outcome on Linux is a
> "no such module 'CryptoKit'" diagnostic, since CryptoKit is an Apple
> system framework and does not exist on Linux. The literal text will be
> inserted here.

## Experiment 3 — strip `#if canImport(CryptoKit)` AND remove the `Crypto` dep

> Status: pending experiment run. The expected outcome is "no such module
> 'Crypto'" on both platforms, because no source of that module name is
> resolvable. The literal text will be inserted here.

## Takeaways

(Filled in once the experiments run.)
