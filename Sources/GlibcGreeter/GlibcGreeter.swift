// This file is intentionally Linux-only. The `import Glibc` line is the
// reason: `Glibc` is the Swift module that exposes Linux's GNU C library;
// it does not exist on macOS (where the equivalent is `Darwin`). Removing
// the manifest-level `#if os(Linux)` around this target's declaration in
// Package.swift would cause the macOS build to attempt compilation here
// and fail with `no such module 'Glibc'`.
//
// This target exists purely as a demonstration of the manifest-level
// guard pattern (`#if os(Linux) ... .target(name: "GlibcGreeter") ...
// #endif`). See <doc:05-Discoveries> for the literal compiler error each
// experiment captures.

import Glibc

public struct GlibcGreeter: Sendable {
    public init() {}

    /// Reports a Linux-only runtime fact via `gethostname` from Glibc.
    public func runtimeReport() -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let result = gethostname(&buffer, buffer.count)
        guard result == 0 else { return "glibc-hostname=(error)" }
        return "glibc-hostname=\(String(cString: buffer))"
    }
}
