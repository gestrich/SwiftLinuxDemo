import Foundation

#if canImport(FoundationNetworking)
// On Linux, URLSession lives in FoundationNetworking and is backed by
// libcurl. This import is the reason `release.yml` runs
// `apt-get install libcurl4-openssl-dev` before the build.
import FoundationNetworking
#endif

public struct Fetcher: Sendable {
    public enum FetchError: Error, CustomStringConvertible {
        case invalidURL(String)
        case nonHTTPResponse
        case httpStatus(Int)

        public var description: String {
            switch self {
            case .invalidURL(let s): "not a valid URL: \(s)"
            case .nonHTTPResponse:   "response was not HTTP"
            case .httpStatus(let c): "HTTP \(c)"
            }
        }
    }

    public init() {}

    public func head(_ urlString: String) async throws -> Int {
        guard let url = URL(string: urlString) else {
            throw FetchError.invalidURL(urlString)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FetchError.nonHTTPResponse
        }
        return http.statusCode
    }
}
