// swift-tools-version: 6.2
import PackageDescription

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
        // swift-crypto provides Apple's CryptoKit API on Linux. We only link
        // it on Linux — on Apple platforms the system CryptoKit is used
        // directly. See Discoveries 14.1 in the source guide.
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
            ]
        ),
        .testTarget(
            name: "SwiftLinuxDemoCoreTests",
            dependencies: ["SwiftLinuxDemoCore"]
        ),
    ]
)
