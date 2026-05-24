# Discoveries

Each conditional in `Package.swift` and the source code, removed in
isolation on the Linux runner — with the literal compiler error each one
prevents.

## Method

Theory is fine. Compiler errors are better. The errors quoted in this
chapter were captured by `.github/workflows/experiments.yml`, which runs
one job per guard, mutates the source with `python3` + `sed`, then runs
`swift build > log 2>&1` and uploads the log as an artifact.

The repo has two guards working together. They look redundant on first
read; the experiments below show they protect against different failures.

```swift
// Package.swift — controls which dependency edge is LINKED per platform.
.product(name: "Crypto", package: "swift-crypto",
         condition: .when(platforms: [.linux]))
```

```swift
// Sources/SwiftLinuxDemoCore/Hasher.swift — controls which import COMPILES.
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
```

To re-run the experiments yourself: `gh workflow run experiments.yml --repo
gestrich/SwiftLinuxDemo`.

## Experiment 1 — strip `.when(platforms: [.linux])` from the swift-crypto dep

The manifest condition keeps swift-crypto out of macOS builds, where
CryptoKit is preferred. What happens on Linux if you remove it?

Mutation:

```swift
- .product(name: "Crypto", package: "swift-crypto",
-          condition: .when(platforms: [.linux]))
+ .product(name: "Crypto", package: "swift-crypto")
```

Build output:

```
[541/542] Linking swift-linux-demo
Build complete! (81.81s)
```

**Result: Linux still builds.** Linking Crypto unconditionally is harmless
on Linux — it's the same dep that Linux needs anyway. The `.when` guard's
purpose is *not* to make Linux work; it's to keep the dep out of the macOS
dependency graph, where you'd be pulling in (and compiling, and linking) a
swift-crypto module that nothing imports.

So this guard is a *correctness-by-omission* knob, not a correctness-of-link
knob. Strip it and Linux is fine; macOS suffers a wasted dependency.

## Experiment 2 — strip `#if canImport(CryptoKit)`, force `import CryptoKit`

Mutation:

```swift
- #if canImport(CryptoKit)
- import CryptoKit
- #else
- import Crypto
- #endif
+ import CryptoKit
```

Build output (Linux):

```
[530/537] Emitting module SwiftLinuxDemoCore
/home/runner/work/SwiftLinuxDemo/SwiftLinuxDemo/Sources/SwiftLinuxDemoCore/Hasher.swift:2:8: error: no such module 'CryptoKit'
 1 | import Foundation
 2 | import CryptoKit
   |        `- error: no such module 'CryptoKit'
 3 |
 4 | public struct Hasher: Sendable {
error: emit-module command failed with exit code 1
```

**Result: Linux fails.** CryptoKit is an Apple system framework — it
literally does not exist on Linux. The `#if canImport(CryptoKit)` guard
exists to let the source file ask "is this module available here?" at
compile time and pick a different import on platforms where the answer is
no.

`#if canImport(...)` is a *compile-time question about module availability*,
which is different from `#if os(macOS)` (a *compile-time assertion about
the host*). The first survives toolchain drift — if Apple ports CryptoKit
to a new platform tomorrow, `canImport` automatically picks the right path
there too.

## Experiment 3 — strip the guard, force `import Crypto`, AND remove the Crypto dep

This combines source mutation with manifest mutation. The point is to show
the *two-layer* failure mode: an import without a corresponding dependency
edge.

Mutations:

```swift
- #if canImport(CryptoKit)
- import CryptoKit
- #else
- import Crypto
- #endif
+ import Crypto
```

```swift
// Package.swift — empty out the target's dependencies array
- .target(
-     name: "SwiftLinuxDemoCore",
-     dependencies: [
-         .product(name: "Crypto", package: "swift-crypto",
-                  condition: .when(platforms: [.linux])),
-     ]
- ),
+ .target(
+     name: "SwiftLinuxDemoCore",
+     dependencies: []
+ ),
```

Build output (Linux):

```
warning: 'swiftlinuxdemo': dependency 'swift-crypto' is not used by any target
[8/15] Write swift-version--6DDE17EDADE5ABEB.txt
error: emit-module command failed with exit code 1
[10/21] Emitting module SwiftLinuxDemoCore
/home/runner/work/SwiftLinuxDemo/SwiftLinuxDemo/Sources/SwiftLinuxDemoCore/Hasher.swift:2:8: error: no such module 'Crypto'
 1 | import Foundation
 2 | import Crypto
   |        `- error: no such module 'Crypto'
 3 |
 4 | public struct Hasher: Sendable {
```

**Result: Linux fails — and SwiftPM also emits a helpful warning.**

Two things to notice:

1. The `import Crypto` line resolves only if the `Crypto` *product* is
   listed in the target's `dependencies:` array. Even though swift-crypto
   is still in the *package*'s `dependencies:` list (we only stripped the
   target-level entry), no target consumes it, so its modules aren't
   visible to any source file. That's what the warning means.
2. The error is reported per-target — `SwiftLinuxDemoCore` couldn't emit
   its module, and the same diagnostic surfaces from every other file in
   the target as a follow-on cascade. Look at the first line in the
   `emit-module` step to find the actual cause.

## Takeaways

- **`.when(platforms: [.linux])` is a macOS-side guard.** Removing it on
  Linux is harmless. It exists so the macOS build doesn't drag in a
  dependency macOS would never use. (Experiment 1.)
- **`#if canImport(CryptoKit)` is a Linux-side guard.** Without it, the
  source line `import CryptoKit` is unconditional, and Linux has nothing
  to import. (Experiment 2.)
- **Imports need both a source mention AND a dependency edge.** Strip
  either and Linux fails with `no such module 'X'`. The SwiftPM warning
  `'<package>': dependency '<name>' is not used by any target` is the
  most reliable signal that the *package* declares a dep but no *target*
  consumes it. (Experiment 3.)

A useful mental model: think of the manifest as wiring the *graph*
(packages → products → target deps), and the source-level `#if` /
`#if canImport` as gating which *nodes* a given file actually visits. Both
layers must agree for the import to resolve.

## See Also

- <doc:02-Building-On-Linux>
- The source guide's "Discoveries 14.1" — the theory companion that this
  chapter empirically tests.
