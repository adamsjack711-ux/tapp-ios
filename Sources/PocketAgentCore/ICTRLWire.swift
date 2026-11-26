import CryptoKit
import Foundation
import Security

/// Client implementation of iCTRL's v1 wire protocol (not a new crypto format).
/// Protocol source: OpenMinis/iCTRL, pinned in DeveloperTools/ICTRL.lock.
enum ICTRLWire {
    struct Envelope: Codable, Sendable {
        let v: Int
        let tok: String?
        let ts: UInt64?
        let nonce: String
        let ct: String
        let tag: String
    }

    static func randomNonce() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw ICTRLError.invalidResponse
        }
        return Data(bytes)
    }

    static func tokenID(_ key: Data) -> String {
        Data(SHA256.hash(data: key).prefix(4)).ictrlHex
    }

    static func mac(_ key: Data, _ message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    static func bigEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        var value = value.bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    static func xorStream(key: Data, nonce: Data, input: Data) -> Data {
        var output = Data(capacity: input.count)
        let bytes = Array(input)
        for offset in stride(from: 0, to: bytes.count, by: 32) {
            let block = mac(key, nonce + bigEndian(UInt32(offset / 32)))
            output.append(contentsOf: zip(bytes[offset..<min(offset + 32, bytes.count)], block).map(^))
        }
        return output
    }

    static func seal(_ plaintext: Data, key: Data, nonce: Data, timestamp: UInt64) throws -> Envelope {
        guard key.count == 32, nonce.count == 16 else { throw ICTRLError.invalidResponse }
        let token = tokenID(key)
        guard let tokenBytes = Data(ictrlHex: token) else { throw ICTRLError.invalidResponse }
        let cipher = xorStream(key: mac(key, Data("ictrl-v1|enc-req".utf8) + nonce), nonce: nonce, input: plaintext)
        let signature = mac(mac(key, Data("ictrl-v1|mac".utf8) + nonce),
                            Data("v1".utf8) + tokenBytes + bigEndian(timestamp) + nonce + cipher)
        return Envelope(v: 1, tok: token, ts: timestamp, nonce: nonce.ictrlHex,
                        ct: cipher.base64EncodedString(), tag: signature.ictrlHex)
    }

    static func open(_ envelope: Envelope, key: Data, expectedNonce: Data) throws -> Data {
        guard envelope.v == 1, key.count == 32,
              Data(ictrlHex: envelope.nonce) == expectedNonce,
              let cipher = Data(base64Encoded: envelope.ct),
              let tag = Data(ictrlHex: envelope.tag), tag.count == 32,
              HMAC<SHA256>.isValidAuthenticationCode(
                tag, authenticating: Data("resp".utf8) + expectedNonce + cipher,
                using: SymmetricKey(data: mac(key, Data("ictrl-v1|mac".utf8) + expectedNonce))
              ) else { throw ICTRLError.authenticationFailed }
        return xorStream(key: mac(key, Data("ictrl-v1|enc-resp".utf8) + expectedNonce),
                         nonce: expectedNonce, input: cipher)
    }

    static func unwrapPairingKey(privateKey: Curve25519.KeyAgreement.PrivateKey,
                                 devicePublicKey: Data, wrappedKey: Data) throws -> Data {
        guard devicePublicKey.count == 32, wrappedKey.count == 32 else { throw ICTRLError.invalidResponse }
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: devicePublicKey)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: peer).withUnsafeBytes { Data($0) }
        let wrapping = mac(secret, Data("ictrl-pair".utf8) + privateKey.publicKey.rawRepresentation + devicePublicKey)
        return Data(zip(wrappedKey, mac(wrapping, Data("ictrl-wrap".utf8))).map(^))
    }
}

extension Data {
    var ictrlHex: String { map { String(format: "%02x", $0) }.joined() }

    init?(ictrlHex: String) {
        let chars = Array(ictrlHex.utf8)
        guard chars.count.isMultiple(of: 2), chars.allSatisfy({
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }) else { return nil }
        var bytes: [UInt8] = []
        for index in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(decoding: chars[index...index + 1], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(byte)
        }
        self.init(bytes)
    }
}
