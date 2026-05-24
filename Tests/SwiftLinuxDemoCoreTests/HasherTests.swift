import Testing
@testable import SwiftLinuxDemoCore

@Suite("Hasher")
struct HasherTests {
    @Test("matches known SHA-256 vector for empty string")
    func emptyStringDigest() {
        // Test vector: sha256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        #expect(
            Hasher().sha256Hex("") ==
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    @Test("matches known SHA-256 vector for 'abc'")
    func abcDigest() {
        #expect(
            Hasher().sha256Hex("abc") ==
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("output is 64 lowercase hex characters")
    func outputShape() {
        let hex = Hasher().sha256Hex("anything")
        #expect(hex.count == 64)
        #expect(hex.allSatisfy { "0123456789abcdef".contains($0) })
    }
}
