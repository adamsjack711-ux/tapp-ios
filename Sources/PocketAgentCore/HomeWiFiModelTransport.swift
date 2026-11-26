import Foundation
import Security

/// Explicit routing for this owner's already approved model gateway only.
/// DNS routing changes; certificate identity, system trust and expiry do not.
public struct HomeWiFiModelTransport: ModelHTTPTransport {
    public static let serverName = "jacks-mac-studio.tail6472bd.ts.net"
    public static let address = "192.168.1.75"
    public static let port = 11436
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 180
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config, delegate: HomeWiFiTrust(), delegateQueue: nil)
    }

    public static func routed(_ request: URLRequest) throws -> URLRequest {
        guard let url = request.url,
              url.scheme == "https", url.host == serverName,
              url.port == nil || url.port == 443,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path == "/v1/chat/completions", request.httpMethod == "POST",
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ModelClientError.invalidURL
        }
        parts.host = address; parts.port = port
        var routed = request
        routed.url = parts.url
        routed.setValue(serverName, forHTTPHeaderField: "Host")
        return routed
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: Self.routed(request))
        guard let response = response as? HTTPURLResponse else { throw ModelClientError.invalidResponse }
        return (data, response)
    }

    /// Testable certificate validation: default system anchors, expiry and the
    /// fixed approved DNS name. Never accept arbitrary/self-signed certificates.
    static func validates(_ trust: SecTrust) -> Bool {
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, serverName as CFString)) == errSecSuccess else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }
}

private final class HomeWiFiTrust: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == HomeWiFiModelTransport.address,
              challenge.protectionSpace.port == HomeWiFiModelTransport.port,
              let trust = challenge.protectionSpace.serverTrust,
              HomeWiFiModelTransport.validates(trust) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
