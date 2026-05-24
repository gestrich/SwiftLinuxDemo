import Foundation

public struct Greeter: Sendable {
    public init() {}

    public func greet(name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = trimmed.isEmpty ? "world" : trimmed
        return "Hello, \(target)!"
    }
}
