import CryptoKit
import Foundation

public enum ICTRLError: LocalizedError, Equatable {
    case notPaired, runnerUnavailable, pairingDenied, pairingBusy, authenticationFailed, invalidResponse, busy
    case http(Int)
    case rpc(Int, String)

    public var errorDescription: String? {
        switch self {
        case .notPaired: return "Pair with the iCTRL runner in Screen Control first."
        case .runnerUnavailable: return "The iCTRL runner is unreachable. Install and start it on this iPhone; check Developer Mode and the mounted developer image."
        case .pairingDenied: return "Pairing was declined or expired. Start pairing again only when ready to approve the runner notification."
        case .pairingBusy: return "Another pairing request is pending or cooling down. Wait before trying again."
        case .authenticationFailed: return "The runner rejected the key or its reply failed authentication. Check the device clock or pair again. Nothing was retried."
        case .invalidResponse: return "The runner returned an unsupported or malformed response."
        case .busy: return "A controller request is already in progress."
        case .http(let status): return "The controller returned HTTP \(status). Nothing was retried."
        case .rpc(let code, let message): return "Controller error \(code): \(message)"
        }
    }
}

public protocol ICTRLCredentialStore: Sendable {
    func load() throws -> Data?
    func save(_ key: Data) throws
    func remove() throws
}

public protocol ICTRLTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct ICTRLHTTPTransport: ICTRLTransport {
    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, data.count <= 12_000_000 else {
                throw ICTRLError.invalidResponse
            }
            return (data, response.statusCode)
        } catch let error as URLError where [.cannotConnectToHost, .cannotFindHost, .notConnectedToInternet].contains(error.code) {
            throw ICTRLError.runnerUnavailable
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public protocol ScreenRPC: Sendable {
    func call(_ method: String, parameters: [String: JSONValue]) async throws -> [String: JSONValue]
}

/// Deliberately loopback-only: the app controls its own phone, not a remote device.
public actor ICTRLClient: ScreenRPC {
    private let transport: any ICTRLTransport
    private let credentials: any ICTRLCredentialStore
    private var inFlight = false
    private var requestID = 0

    public init(credentials: any ICTRLCredentialStore, transport: any ICTRLTransport = ICTRLHTTPTransport()) {
        self.credentials = credentials
        self.transport = transport
    }

    public func isPaired() -> Bool { (try? credentials.load()?.count) == 32 }

    public func forget() throws {
        guard !inFlight else { throw ICTRLError.busy }
        try credentials.remove()
    }

    /// No automatic retries: each /pair displays a real device approval request.
    public func pair() async throws {
        guard !inFlight else { throw ICTRLError.busy }
        inFlight = true
        defer { inFlight = false }
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let body: [String: JSONValue] = [
            "client_name": .string("Pocket Agent"),
            "pub": .string(privateKey.publicKey.rawRepresentation.base64EncodedString())
        ]
        let (data, status) = try await post("pair", body: JSONEncoder().encode(body), timeout: 90)
        if status == 403 { throw ICTRLError.pairingDenied }
        if status == 429 { throw ICTRLError.pairingBusy }
        guard status == 200 else { throw ICTRLError.http(status) }
        let reply = try JSONDecoder().decode([String: JSONValue].self, from: data)
        guard let publicString = reply["pub"]?.stringValue, let publicKey = Data(base64Encoded: publicString),
              let wrappedString = reply["token_ct"]?.stringValue, let wrapped = Data(ictrlHex: wrappedString) else {
            throw ICTRLError.invalidResponse
        }
        let key = try ICTRLWire.unwrapPairingKey(privateKey: privateKey, devicePublicKey: publicKey, wrappedKey: wrapped)
        guard reply["tok"]?.stringValue == ICTRLWire.tokenID(key) else { throw ICTRLError.authenticationFailed }
        try Task.checkCancellation()
        try credentials.save(key)
    }

    /// Each invocation is sent once. A timeout may mean a gesture already ran.
    public func call(_ method: String, parameters: [String: JSONValue] = [:]) async throws -> [String: JSONValue] {
        guard !inFlight else { throw ICTRLError.busy }
        guard let key = try credentials.load(), key.count == 32 else { throw ICTRLError.notPaired }
        try Task.checkCancellation()
        inFlight = true
        defer { inFlight = false }
        requestID += 1
        let id = requestID
        let body: [String: JSONValue] = ["jsonrpc": .string("2.0"), "id": .number(Double(id)),
                                       "method": .string(method), "params": .object(parameters)]
        let nonce = try ICTRLWire.randomNonce()
        let envelope = try ICTRLWire.seal(JSONEncoder().encode(body), key: key, nonce: nonce,
                                         timestamp: UInt64(max(0, Date().timeIntervalSince1970)))
        let (data, status) = try await post("rpc", body: JSONEncoder().encode(envelope), timeout: 20)
        if status == 401 { throw ICTRLError.authenticationFailed }
        guard status == 200 else { throw ICTRLError.http(status) }
        let response = try JSONDecoder().decode(ICTRLWire.Envelope.self, from: data)
        let plain = try ICTRLWire.open(response, key: key, expectedNonce: nonce)
        let reply = try JSONDecoder().decode([String: JSONValue].self, from: plain)
        guard reply["jsonrpc"] == .string("2.0"), reply["id"] == .number(Double(id)) else {
            throw ICTRLError.invalidResponse
        }
        if case .object(let error) = reply["error"] {
            let rawCode = error["code"]?.numberValue ?? -1
            let code = rawCode.isFinite && (-1_000_000...1_000_000).contains(rawCode) ? Int(rawCode) : -1
            throw ICTRLError.rpc(code, error["message"]?.stringValue ?? "Unknown error")
        }
        guard case .object(let result) = reply["result"] else { throw ICTRLError.invalidResponse }
        return result
    }

    private func post(_ path: String, body: Data, timeout: TimeInterval) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8200/\(path)")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await transport.send(request)
    }
}
