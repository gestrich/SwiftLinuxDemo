import Foundation

#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

public struct Hasher: Sendable {
    public init() {}

    public func sha256Hex(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
