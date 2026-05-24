import Testing
@testable import SwiftLinuxDemoCore

@Suite("PlatformInfo")
struct PlatformInfoTests {
    @Test("current() reports a non-empty os and arch")
    func currentNotEmpty() {
        let info = PlatformInfo.current()
        #expect(!info.os.isEmpty)
        #expect(!info.arch.isEmpty)
        #expect(!info.swiftCompilerVersion.isEmpty)
    }

    @Test("renderedReport includes each field's value")
    func reportFormat() {
        let info = PlatformInfo(os: "demo-os", arch: "demo-arch", swiftCompilerVersion: "demo-swift")
        let rendered = info.renderedReport()
        #expect(rendered.contains("demo-os"))
        #expect(rendered.contains("demo-arch"))
        #expect(rendered.contains("demo-swift"))
    }
}
