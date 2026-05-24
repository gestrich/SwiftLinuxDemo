import Foundation

public struct PlatformInfo: Sendable, Equatable {
    public let os: String
    public let arch: String
    public let swiftCompilerVersion: String

    public init(os: String, arch: String, swiftCompilerVersion: String) {
        self.os = os
        self.arch = arch
        self.swiftCompilerVersion = swiftCompilerVersion
    }

    public static func current() -> PlatformInfo {
        PlatformInfo(
            os: detectedOS,
            arch: detectedArch,
            swiftCompilerVersion: compilerVersion
        )
    }

    public func renderedReport() -> String {
        """
        os:     \(os)
        arch:   \(arch)
        swift:  \(swiftCompilerVersion)
        native: \(PlatformReport.line())
        """
    }

    private static var detectedOS: String {
        #if os(Linux)
        return "linux"
        #elseif os(macOS)
        return "macos"
        #elseif os(Windows)
        return "windows"
        #else
        return "unknown"
        #endif
    }

    private static var detectedArch: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #elseif arch(arm)
        return "arm"
        #elseif arch(i386)
        return "i386"
        #else
        return "unknown"
        #endif
    }

    private static var compilerVersion: String {
        #if swift(>=6.2)
        return "6.2+"
        #elseif swift(>=6.0)
        return "6.0+"
        #elseif swift(>=5.10)
        return "5.10+"
        #else
        return "unknown"
        #endif
    }
}
