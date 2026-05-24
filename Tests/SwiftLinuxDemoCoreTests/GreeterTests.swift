import Testing
@testable import SwiftLinuxDemoCore

@Suite("Greeter")
struct GreeterTests {
    @Test("greets a named person")
    func greetsNamedPerson() {
        #expect(Greeter().greet(name: "Bill") == "Hello, Bill!")
    }

    @Test("falls back to 'world' for empty/whitespace input")
    func fallsBackToWorld() {
        #expect(Greeter().greet(name: "") == "Hello, world!")
        #expect(Greeter().greet(name: "   ") == "Hello, world!")
    }

    @Test("trims surrounding whitespace")
    func trimsWhitespace() {
        #expect(Greeter().greet(name: "  Bill  ") == "Hello, Bill!")
    }
}
