// swift-tools-version: 6.2
import PackageDescription

// =============================================================================
// Platform-exclusive plumbing
// =============================================================================
// Three patterns coexist in this manifest, each solving a different problem.
// (See <doc:05-Discoveries> for the literal compiler error each guard prevents.)
//
//   1. `#if os(...)` in this file, around a TARGET DECLARATION.
//      Used when the target's source files import a framework that only
//      exists on one platform (AppKit on macOS, Glibc on Linux). Without
//      the manifest-level guard, the *other* platform tries to compile
//      those source files and the build fails with "no such module".
//
//   2. `#if os(...)` in this file, around a DEPENDENCY EDGE entry.
//      Used when a downstream target wants to depend on a target that
//      only exists on certain platforms. The dependency name in the
//      `dependencies:` array must not be evaluated on platforms where
//      the referenced target doesn't exist, or the manifest itself
//      becomes invalid ("no such target").
//
//   3. `.product(name:..., condition: .when(platforms: [...]))` on a
//      dependency edge. Used when the depended-on package compiles fine
//      on every platform (swift-crypto is the classic example), but you
//      only want it *linked* on some of them. This is the lightest
//      guard — Linux-only linking, no manifest gymnastics.
//
// Patterns 1 and 2 work together: if pattern 1 hides a target, every
// reference to it in another target's `dependencies:` must also be inside
// a matching `#if`. Otherwise the manifest fails to evaluate.

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

let package = Package(
    name: "SwiftLinuxDemo",
    platforms: [
        // Bumped so CryptoKit conformances and URLSession async APIs are
        // unconditionally available on macOS. Linux has no equivalent
        // gating — the host OS is the only build target on the CI runner.
        .macOS(.v13)
    ],
    products: [
        .executable(name: "swift-linux-demo", targets: ["SwiftLinuxDemo"]),
        .library(name: "SwiftLinuxDemoCore", targets: ["SwiftLinuxDemoCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        // swift-crypto compiles on every platform; we only need to LINK it
        // on Linux, where CryptoKit doesn't exist. The `.when` guard is
        // pattern 3 above.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-docc-plugin.git", from: "1.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftLinuxDemo",
            dependencies: [
                "SwiftLinuxDemoCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "SwiftLinuxDemoCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux])),
            ] + platformExclusiveCoreDeps
        ),
        .testTarget(
            name: "SwiftLinuxDemoCoreTests",
            dependencies: ["SwiftLinuxDemoCore"]
        ),
    ] + platformExclusiveTargets
)
