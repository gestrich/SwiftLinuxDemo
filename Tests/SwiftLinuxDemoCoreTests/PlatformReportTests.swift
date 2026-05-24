import Testing
@testable import SwiftLinuxDemoCore

@Suite("PlatformReport")
struct PlatformReportTests {
    @Test("returns a non-empty platform-keyed string on every supported host")
    func returnsNonEmpty() {
        let line = PlatformReport.line()
        #expect(!line.isEmpty)
    }

    #if os(macOS)
    @Test("on macOS, the report comes from AppKitGreeter")
    func macOSGoesThroughAppKit() {
        let line = PlatformReport.line()
        #expect(line.hasPrefix("appkit-screen-count="))
    }
    #elseif os(Linux)
    @Test("on Linux, the report comes from GlibcGreeter")
    func linuxGoesThroughGlibc() {
        let line = PlatformReport.line()
        #expect(line.hasPrefix("glibc-hostname="))
    }
    #endif
}
