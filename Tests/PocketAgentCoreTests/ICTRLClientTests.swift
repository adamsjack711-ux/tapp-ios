import CryptoKit
import Foundation
import Testing
@testable import PocketAgentCore

@Suite("iCTRL encrypted client")
struct ICTRLClientTests {
    @Test("Protocol matches independent Python HMAC/SHA256 test vectors")
    func knownAnswers() throws {
        let key = Data(0..<32), nonce = Data(0..<16)
        let request = Data(#"{"jsonrpc":"2.0","id":1,"method":"device_info","params":{}}"#.utf8)
        let sealed = try ICTRLWire.seal(request, key: key, nonce: nonce, timestamp: 1_700_000_000)
        #expect(sealed.tok == "630dcd29")
        #expect(sealed.ct == "LBWBVbibdCW0HNXl0ZoySDGyITO4zWVEeZftn9zQ5NohSRVhTnMrexYNVUnnbbsKOxt8H4cF/hL2EAA=")
        #expect(sealed.tag == "c37e14c0a4ae9fc3d99cd0fb175db53c52b7bd72df741ea15240c0410c92052f")
        let response = ICTRLWire.Envelope(v: 1, tok: nil, ts: nil, nonce: nonce.ictrlHex,
            ct: "LWcZwwj2XRJIwit1JHsuUgJxlfKQn7dMXU5BQkcw6Yo8vWPyXXb7aoDtq2SI7bIJJvpWaE3pr3Q=",
            tag: "cd6344a29cebc7a3b86a1ce9543347341f6e0a5c4b0da612e852c135a3764e00")
        let opened = try ICTRLWire.open(response, key: key, expectedNonce: nonce)
        #expect(String(data: opened, encoding: .utf8) == #"{"jsonrpc":"2.0","id":1,"result":{"protocol_version":1}}"#)
    }

    @Test("Tampered replies and mismatched nonces fail closed")
    func rejectsTampering() throws {
        let envelope = ICTRLWire.Envelope(v: 1, tok: nil, ts: nil, nonce: Data(0..<16).ictrlHex,
            ct: Data("forged".utf8).base64EncodedString(), tag: String(repeating: "0", count: 64))
        #expect(throws: ICTRLError.authenticationFailed) {
            try ICTRLWire.open(envelope, key: Data(0..<32), expectedNonce: Data(0..<16))
        }
        #expect(throws: ICTRLError.authenticationFailed) {
            try ICTRLWire.open(envelope, key: Data(0..<32), expectedNonce: Data(repeating: 1, count: 16))
        }
    }

    @Test("X25519 pairing then authenticated RPC works without exposing a plaintext key")
    func pairAndCall() async throws {
        let store = MemoryCredentials()
        let peer = ReferencePeer()
        let client = ICTRLClient(credentials: store, transport: peer)
        #expect(await client.isPaired() == false)
        try await client.pair()
        #expect(await client.isPaired())
        #expect(store.load() == Data(0..<32))
        let info = try await client.call("device_info")
        #expect(info["protocol_version"] == .number(1))
        #expect(await peer.methods == ["device_info"])
        try await client.forget()
        #expect(await client.isPaired() == false)
    }

    @Test("Denied pairing never saves credentials")
    func deniedPair() async throws {
        let store = MemoryCredentials()
        let client = ICTRLClient(credentials: store, transport: ReferencePeer(mode: .denied))
        await #expect(throws: ICTRLError.pairingDenied) { try await client.pair() }
        #expect(store.load() == nil)
    }

    @Test("Requests require pairing")
    func requiresPair() async throws {
        let peer = ReferencePeer()
        let client = ICTRLClient(credentials: MemoryCredentials(), transport: peer)
        await #expect(throws: ICTRLError.notPaired) { try await client.call("device_info") }
        #expect(await peer.requestCount == 0)
    }

    @Test("Timeouts are never automatically replayed")
    func noRetries() async throws {
        let peer = ReferencePeer(mode: .timeout)
        let client = ICTRLClient(credentials: MemoryCredentials(key: Data(0..<32)), transport: peer)
        await #expect(throws: URLError.self) { try await client.call("tap", parameters: ["ref": .string("el_1")]) }
        #expect(await peer.requestCount == 1)
    }

    @Test("Encrypted RPC IDs must match the request")
    func validatesID() async throws {
        let client = ICTRLClient(credentials: MemoryCredentials(key: Data(0..<32)), transport: ReferencePeer(mode: .wrongID))
        await #expect(throws: ICTRLError.invalidResponse) { try await client.call("device_info") }
    }

    @Test("RPC errors are decoded only after response authentication")
    func rpcError() async throws {
        let client = ICTRLClient(credentials: MemoryCredentials(key: Data(0..<32)), transport: ReferencePeer(mode: .rpcError))
        await #expect(throws: ICTRLError.rpc(-32602, "Not found")) { try await client.call("find_element") }
    }

    @Test("Hex decoding rejects malformed input")
    func hexInput() {
        #expect(Data(ictrlHex: "0g") == nil)
        #expect(Data(ictrlHex: "a") == nil)
        #expect(Data(ictrlHex: "+1") == nil)
        #expect(Data(ictrlHex: "ＦＦ") == nil)
        #expect(Data(ictrlHex: "aA") == Data([170]))
    }
}

final class MemoryCredentials: ICTRLCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: Data?
    init(key: Data? = nil) { self.key = key }
    func load() -> Data? { lock.lock(); defer { lock.unlock() }; return key }
    func save(_ key: Data) { lock.lock(); defer { lock.unlock() }; self.key = key }
    func remove() { lock.lock(); defer { lock.unlock() }; key = nil }
}

private actor ReferencePeer: ICTRLTransport {
    enum Mode { case normal, denied, timeout, wrongID, rpcError }
    let mode: Mode
    let key = Data(0..<32)
    private(set) var methods: [String] = []
    private(set) var requestCount = 0
    init(mode: Mode = .normal) { self.mode = mode }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requestCount += 1
        #expect(request.url?.host == "127.0.0.1")
        #expect(request.url?.port == 8200)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        if mode == .timeout { throw URLError(.timedOut) }
        let body = try #require(request.httpBody)
        if request.url?.path == "/pair" {
            if mode == .denied { return (Data("{}".utf8), 403) }
            let request = try JSONDecoder().decode([String: JSONValue].self, from: body)
            #expect(request["plain"] == nil)
            #expect(request["client_name"] == .string("Pocket Agent"))
            let publicString = try #require(request["pub"]?.stringValue)
            let rawPublic = try #require(Data(base64Encoded: publicString))
            let clientKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: rawPublic)
            let privateKey = Curve25519.KeyAgreement.PrivateKey()
            let publicKey = privateKey.publicKey.rawRepresentation
            let shared = try privateKey.sharedSecretFromKeyAgreement(with: clientKey).withUnsafeBytes { Data($0) }
            let wrap = ICTRLWire.mac(shared, Data("ictrl-pair".utf8) + rawPublic + publicKey)
            let pad = ICTRLWire.mac(wrap, Data("ictrl-wrap".utf8))
            let result: [String: String] = ["pub": publicKey.base64EncodedString(), "token_ct": Data(zip(key, pad).map(^)).ictrlHex,
                                            "tok": ICTRLWire.tokenID(key)]
            return (try JSONEncoder().encode(result), 200)
        }
        let envelope = try JSONDecoder().decode(ICTRLWire.Envelope.self, from: body)
        let nonce = try #require(Data(ictrlHex: envelope.nonce))
        let cipher = try #require(Data(base64Encoded: envelope.ct))
        let macKey = ICTRLWire.mac(key, Data("ictrl-v1|mac".utf8) + nonce)
        let tokenString = try #require(envelope.tok)
        let token = try #require(Data(ictrlHex: tokenString))
        let signed = Data("v1".utf8) + token + ICTRLWire.bigEndian(try #require(envelope.ts)) + nonce + cipher
        #expect(ICTRLWire.mac(macKey, signed).ictrlHex == envelope.tag)
        let plain = ICTRLWire.xorStream(key: ICTRLWire.mac(key, Data("ictrl-v1|enc-req".utf8) + nonce), nonce: nonce, input: cipher)
        let rpc = try JSONDecoder().decode([String: JSONValue].self, from: plain)
        methods.append(try #require(rpc["method"]?.stringValue))
        var reply: [String: JSONValue] = ["jsonrpc": .string("2.0"), "id": mode == .wrongID ? .number(999) : rpc["id"]!]
        if mode == .rpcError { reply["error"] = .object(["code": .number(-32602), "message": .string("Not found")]) }
        else { reply["result"] = .object(["protocol_version": .number(1)]) }
        let responseCipher = ICTRLWire.xorStream(key: ICTRLWire.mac(key, Data("ictrl-v1|enc-resp".utf8) + nonce),
                                                nonce: nonce, input: try JSONEncoder().encode(reply))
        let response = ICTRLWire.Envelope(v: 1, tok: nil, ts: nil, nonce: nonce.ictrlHex,
            ct: responseCipher.base64EncodedString(), tag: ICTRLWire.mac(macKey, Data("resp".utf8) + nonce + responseCipher).ictrlHex)
        return (try JSONEncoder().encode(response), 200)
    }
}
