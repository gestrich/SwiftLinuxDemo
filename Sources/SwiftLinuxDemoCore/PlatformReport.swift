// `PlatformReport` is the second half of the guard story Package.swift
// sets up. The manifest decides which platform-exclusive target *exists*;
// this file decides which one to *import*. Both guards have to agree, and
// removing either alone produces a different failure mode — see the
// experiments captured in <doc:05-Discoveries>.

#if os(macOS)
import AppKitGreeter
#elseif os(Linux)
import GlibcGreeter
#endif

/// One-line runtime fact, sourced from a platform-exclusive helper.
///
/// On macOS this calls into `AppKitGreeter` (which transitively imports
/// AppKit). On Linux it calls into `GlibcGreeter` (which transitively
/// imports Glibc). On any other host the report is a fixed string — the
/// only build host this repo's CI actually exercises are macOS and Linux,
/// but the catch-all keeps the source legal on visionOS, Windows, etc.
public enum PlatformReport {
    public static func line() -> String {
        #if os(macOS)
        return AppKitGreeter().runtimeReport()
        #elseif os(Linux)
        return GlibcGreeter().runtimeReport()
        #else
        return "platform=unknown"
        #endif
    }
}
