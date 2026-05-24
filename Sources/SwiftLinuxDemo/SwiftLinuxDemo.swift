import ArgumentParser
import Foundation
import SwiftLinuxDemoCore

@main
struct SwiftLinuxDemo: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-linux-demo",
        abstract: "A tiny Swift CLI used to demonstrate Linux GitHub Actions releases with build provenance.",
        version: "0.1.0",
        subcommands: [Greet.self, Hash.self, Info.self, Fetch.self],
        defaultSubcommand: Info.self
    )
}

struct Greet: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print a greeting."
    )

    @Option(name: .shortAndLong, help: "Name to greet.")
    var name: String = "world"

    func run() throws {
        print(Greeter().greet(name: name))
    }
}

struct Hash: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print the SHA-256 hex of the input string (cross-platform via swift-crypto on Linux)."
    )

    @Argument(help: "Input string to hash.")
    var input: String

    func run() throws {
        print(Hasher().sha256Hex(input))
    }
}

struct Info: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print runtime platform info (os, arch, swift version)."
    )

    func run() throws {
        print(PlatformInfo.current().renderedReport())
    }
}

struct Fetch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "HEAD a URL and print the HTTP status code (uses libcurl-backed URLSession on Linux)."
    )

    @Argument(help: "URL to issue a HEAD request against.")
    var url: String

    func run() async throws {
        let code = try await Fetcher().head(url)
        print(code)
    }
}
