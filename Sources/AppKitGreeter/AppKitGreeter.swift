// This file is intentionally macOS-only. The `import AppKit` line is the
// reason: AppKit is a system framework that ships with macOS and does not
// exist on Linux. Removing the manifest-level `#if os(macOS)` around this
// target's declaration in Package.swift would cause the Linux build to
// attempt compilation here and fail with `no such module 'AppKit'`.
//
// This target exists purely as a demonstration of the manifest-level
// guard pattern (`#if os(macOS) ... .target(name: "AppKitGreeter") ...
// #endif`). See <doc:05-Discoveries> for the literal compiler error each
// experiment captures.

import AppKit

public struct AppKitGreeter: Sendable {
    public init() {}

    /// Reports an AppKit-only runtime fact. NSScreen is part of AppKit and
    /// only resolves on platforms where AppKit is available.
    public func runtimeReport() -> String {
        let count = NSScreen.screens.count
        return "appkit-screen-count=\(count)"
    }
}
