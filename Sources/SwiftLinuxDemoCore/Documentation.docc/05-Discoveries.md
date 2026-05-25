# Cross-platform Swift packages: which guard does what

## The empirical question

Cross-platform Swift packages quickly accumulate conditional code:
[`#if os(macOS)`][lang-conditional] blocks inside `Package.swift`,
[`.when(platforms:)`][when-platforms] conditions on dependency edges,
[`#if canImport(...)`][lang-canimport] guards inside source files.
Apple's documentation describes each one in isolation, but the
question that actually matters when you're staring at an unfamiliar
error message is: *which guard would have prevented this?*

The answer below is empirical. For each of the three patterns this
repo uses, the experiments workflow strips the guard on a Linux
runner and captures the literal compiler diagnostic. The *"what does
this guard actually prevent"* answer is then exactly the error you
see when it isn't there.

[lang-conditional]: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/statements/#Conditional-Compilation-Block
[lang-canimport]: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/statements/#Conditional-Compilation-Block
[when-platforms]: https://docs.swift.org/swiftpm/documentation/packagedescription/targetdependencycondition/

## Method

`.github/workflows/experiments.yml` is a manually-triggered workflow with
one job per experiment. Each job:

1. Mutates `Package.swift` or a source file via `python3` (or `cat
   <<'SWIFT'`).
2. Runs `swift build > log 2>&1` with `set +e` so a build failure
   doesn't abort the job.
3. Captures the build's combined output to
   `experiments/<name>.log`.
4. Uploads the log as an artifact.

To re-run them yourself: `gh workflow run experiments.yml --repo
gestrich/SwiftLinuxDemo`. Each `Discoveries` quote below is verbatim from
those artifact logs.

## The three patterns at a glance

| Pattern | Lives in | Filters | When you reach for it |
|---|---|---|---|
| `.when(platforms: [.linux])` on a target dependency edge | `Package.swift` | Whether the dependency is **linked** on a given build destination | Dep compiles everywhere, but you only need it on some platforms (the swift-crypto case) |
| `#if os(...)` around a `.target(name:)` declaration | `Package.swift` | Whether the target **exists in the manifest** for a given host | Target's source files literally cannot compile on the other platform |
| `#if os(...)` / `#if canImport(...)` inside source | `*.swift` | Which lines of code the compiler **sees** | One source file picks between alternative implementations |

The patterns *compose*. If you use the manifest-level guard (pattern 2),
every reference to the gated target in another target's `dependencies:`
array must *also* be gated, or the manifest itself fails to evaluate
(experiments below).

## Pattern 1 — `.when(platforms:)` on a dep edge

This is the lightest guard. The dependency itself compiles everywhere;
the guard just controls *linking*. swift-crypto is the canonical example
in this repo:

```swift
.product(name: "Crypto", package: "swift-crypto",
         condition: .when(platforms: [.linux]))
```

### Experiment — strip the `.when` clause

The mutation makes the Linux-only condition unconditional. On Linux
nothing changes (Linux was going to link Crypto either way). The result:

```
[541/542] Linking swift-linux-demo
Build complete! (81.81s)
```

**Linux still builds.** The guard's purpose is *not* to make Linux work
— it's to keep the dep out of the macOS dependency graph, where you'd
be resolving, compiling and linking a swift-crypto module that nothing
imports. Pattern 1 is a *correctness-by-omission* knob, not a
correctness-of-link knob.

## Pattern 2 — `#if os(...)` around a target declaration

The heavier guard. Used when the target's source files themselves can't
compile on the other platform — e.g. `Sources/AppKitGreeter/` imports
AppKit (macOS-only), and `Sources/GlibcGreeter/` imports Glibc
(Linux-only).

In this repo's `Package.swift`:

```swift
#if os(macOS)
let platformExclusiveTargets: [Target] = [
    .target(name: "AppKitGreeter"),
]
let platformExclusiveCoreDeps: [Target.Dependency] = ["AppKitGreeter"]
#elseif os(Linux)
let platformExclusiveTargets: [Target] = [
    .target(name: "GlibcGreeter"),
]
let platformExclusiveCoreDeps: [Target.Dependency] = ["GlibcGreeter"]
#else
let platformExclusiveTargets: [Target] = []
let platformExclusiveCoreDeps: [Target.Dependency] = []
#endif
```

### Experiment EXP-D — declare both targets unconditionally

Mutation: drop the `#if os` wrapping entirely so both `AppKitGreeter`
and `GlibcGreeter` are declared on every platform.

Result on Linux:

```
[385/397] Emitting module AppKitGreeter
/home/runner/work/SwiftLinuxDemo/SwiftLinuxDemo/Sources/AppKitGreeter/AppKitGreeter.swift:12:8: error: no such module 'AppKit'
10 | // experiment captures.
11 |
12 | import AppKit
   |        `- error: no such module 'AppKit'
13 |
14 | public struct AppKitGreeter: Sendable {
[386/397] Compiling AppKitGreeter AppKitGreeter.swift
```

**The Linux build tries to compile `AppKitGreeter.swift` and fails at
the `import AppKit` line** — exactly because there is no AppKit on
Linux. `.when(platforms:)` would *not* save you here, because `.when`
only controls linking; the target's source still gets compiled if the
target is declared. The only way to prevent the compile attempt is to
hide the target from the manifest entirely.

### Experiment EXP-E — keep the target gated, but forget to gate the dep edge

A subtle, frequently-encountered failure mode. The target declaration
is correctly gated by `#if os(macOS)`, but somewhere downstream a
target's `dependencies:` array references it without the matching
guard:

```swift
#if os(macOS)
let platformExclusiveTargets: [Target] = [
    .target(name: "AppKitGreeter"),
]
#elseif os(Linux)
let platformExclusiveTargets: [Target] = [
    .target(name: "GlibcGreeter"),
]
#endif

// ⚠ This reference was not gated:
let platformExclusiveCoreDeps: [Target.Dependency] = ["AppKitGreeter"]
```

Result on Linux:

```
error: 'swiftlinuxdemo': product 'AppKitGreeter' required by package 'swiftlinuxdemo' target 'SwiftLinuxDemoCore' not found.
```

**Three things to notice:**

1. The build never reaches the *compile* phase. This is a
   **manifest-evaluation** failure — SwiftPM rejects the package before
   any Swift file is touched. It happens after package resolution but
   before any target is built.
2. SwiftPM says "product 'AppKitGreeter'" even though `AppKitGreeter`
   is declared as `.target(name:)`, not as a `.product(...)`. The
   error message is a little misleading. The fix is *not* to add a
   product declaration; it's to gate the dependency reference with
   the same `#if os` that gates the target.
3. This is exactly the gotcha that motivates the `let
   platformExclusiveCoreDeps` helper in this repo's `Package.swift` —
   binding the deps inside the same `#if` block as the target
   declaration makes it impossible to forget one without the other.

## Pattern 3 — source-level `#if os(...)` / `#if canImport(...)`

The finest-grained guard. Lives inside a `.swift` file, not in
`Package.swift`. Controls which import statements (and which arbitrary
code blocks) the compiler sees.

This repo uses both flavors:

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

The choice between `#if os(macOS)` and `#if canImport(...)` is worth
thinking about:

- **`#if os(X)`** is a hard assertion about the host's *operating
  system*. Easy to read, but it can drift — if the named module ever
  ships on a new platform, you have to update every guard.
- **`#if canImport(X)`** is a softer question — "is this module
  available?" — that auto-adapts to future toolchain changes. Prefer
  it when the module is the thing you actually care about. Prefer
  `#if os(X)` when you're guarding code that doesn't import anything
  (e.g. platform-specific syscalls accessed through `Foundation`).

### Experiment — strip `#if canImport(CryptoKit)`, force `import CryptoKit`

Mutation: remove the canImport guard in `Hasher.swift`; replace its
contents with an unconditional `import CryptoKit`.

Result on Linux:

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

**Linux fails.** CryptoKit is an Apple system framework — it literally
does not exist on Linux. The `#if canImport(CryptoKit)` guard exists
exactly because of this.

### Experiment — strip the guard, force `import Crypto`, *and* remove the dep

Mutation: source unconditionally imports `Crypto`, AND the
`SwiftLinuxDemoCore` target's `dependencies:` array no longer lists the
`Crypto` product.

Result on Linux:

```
warning: 'swiftlinuxdemo': dependency 'swift-crypto' is not used by any target
error: emit-module command failed with exit code 1
[10/21] Emitting module SwiftLinuxDemoCore
/home/runner/work/SwiftLinuxDemo/SwiftLinuxDemo/Sources/SwiftLinuxDemoCore/Hasher.swift:2:8: error: no such module 'Crypto'
 1 | import Foundation
 2 | import Crypto
   |        `- error: no such module 'Crypto'
 3 |
 4 | public struct Hasher: Sendable {
```

**Linux fails — and SwiftPM gives you a nice hint up top.** The
warning `dependency 'swift-crypto' is not used by any target` is the
single most reliable signal that the *package* declares a dependency
but no *target* consumes it. If you see that warning on a build that
shouldn't have it, you've broken an edge somewhere.

### Experiment EXP-F — strip source-level `#if os(...)` for AppKitGreeter

Mutation: replace the conditional import in `PlatformReport.swift`
with an unconditional `import AppKitGreeter`, while leaving the
manifest-level gating intact.

Result on Linux:

```
[535/543] Compiling SwiftLinuxDemoCore Hasher.swift
/home/runner/work/SwiftLinuxDemo/SwiftLinuxDemo/Sources/SwiftLinuxDemoCore/PlatformReport.swift:1:8: error: no such module 'AppKitGreeter'
1 | import AppKitGreeter
  |        `- error: no such module 'AppKitGreeter'
2 |
3 | public enum PlatformReport {
```

**Linux fails.** The manifest correctly omits `AppKitGreeter` from
the dependencies of `SwiftLinuxDemoCore` on Linux, so the module
isn't visible to the compiler when it tries to compile
`PlatformReport.swift`. **Manifest-level gating alone is not enough**
— if a source file unconditionally imports a manifest-gated target,
you still get a compile error.

The corollary is also true: a source-level guard alone isn't enough
either. EXP-D showed that an un-gated *target* fails to compile on the
wrong platform even if no one imports it — `swift build` builds all
declared targets regardless of whether anything depends on them.

## Putting it all together

The three patterns answer three different questions:

- **Is this dep needed *on this platform*?** Pattern 1 (`.when`).
- **Can this target's source even *compile* on this platform?** Pattern 2
  (`#if os(...)` around `.target(name:)`, paired with `#if os(...)`
  around every reference to its name).
- **Does this source file need *different code* per platform?** Pattern 3
  (`#if os(...)` / `#if canImport(...)` inside the .swift file).

A complete cross-platform Swift package usually wants all three,
because they protect against three different failure modes. This repo's
`Package.swift` keeps them adjacent and labeled, so future readers can
follow which guard solves which problem.

## See Also

- <doc:02-Building-On-Linux>
- [SE-0273][se-0273] — the proposal that introduced
  `.when(platforms:)` on target dependencies.
- [TargetDependencyCondition reference][when-platforms] — the
  official SwiftPM API docs for the manifest-level condition.

[se-0273]: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0273-swiftpm-conditional-target-dependencies.md
