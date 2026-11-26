import Foundation
import Security
import Testing
@testable import PocketAgentCore

@Suite("Owner-approved home Wi-Fi transport")
struct HomeWiFiTransportTests {
    @Test("A self-signed certificate with the correct name is still rejected")
    func untrustedCertificate() throws {
        // Public test certificate only; its private key was discarded.
        let der = Data(base64Encoded: "MIIDGjCCAgKgAwIBAgIUYHIi3Tv2MCI4L79MF2B0QDRfzyEwDQYJKoZIhvcNAQELBQAwLTErMCkGA1UEAwwiamFja3MtbWFjLXN0dWRpby50YWlsNjQ3MmJkLnRzLm5ldDAeFw0yNjEwMTgyMjU3MTNaFw0yNjEwMTkyMjU3MTNaMC0xKzApBgNVBAMMImphY2tzLW1hYy1zdHVkaW8udGFpbDY0NzJiZC50cy5uZXQwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCgDrhIyDwduaV+U/HlqqDJd5n7iiDOVgEllleWwshGK16zehN+kX5iMR8m8jjPQzwMk7rAuKWvkWeFooQh4GlYiBlGV9kE/gOUCjvBTncej858EaOu3sVCzfiqJp92ENYTNp8tWVQkHGJmP4lTy13k77/3uxtZUHw6RLrxtvVMgKS1iwZYooZt7PDMX3Twr/z2mqTUAPn3sUYwinisRJJvXXYxbYgBDom9julZtMtdckq5ONDi2dYYJxW3h+2H6vKUpupSQtnmOwXQ52jOGfsepRYkp93JT3nbKwNtHp8psePpeN9XuuLxrba/P69SxXpNIfRwEjEYrWkTbMwzxVI1AgMBAAGjMjAwMB0GA1UdDgQWBBQokz0xUg0vvQ7R5sH5Ixfmq0vgnDAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQAAHXN0WFqE7AxrKrNP9ub7KQjr5buT0CSsgq6hny/TBM9q3aeyHN6YSAZe3ubjd9hJZxkiCie6lHwFgG3lqr0McapdAaSlZO+LJo2sEvO5GwD+Bju3LyCSCotSMHFZAqvTpRLBWsIZXbeiiOLiQmLDLuE4RMn1Q60+QPA71CwtirCMK1asJzlbM8X/N7H0iYSY/GYIr+H1g0/I/hiKi9J3syGVIuznDdvtPRCaVidM6yVk3/9Qxj5O7yavMXTe1ZPT2Gcl9nFC6fO7rxRsUVagad77P2UcXgtu5rTH3B8ttpb21VvnCSqmTx4xj/kvn4rhDRs7kkBI7rw0/ENwgfrS")!
        let certificate = try #require(SecCertificateCreateWithData(nil, der as CFData))
        var optional: SecTrust?
        #expect(SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &optional) == errSecSuccess)
        let trust = try #require(optional)
        SecTrustSetVerifyDate(trust, ISO8601DateFormatter().date(from: "2026-10-18T23:00:00Z")! as CFDate)
        SecTrustSetNetworkFetchAllowed(trust, false)
        #expect(!HomeWiFiModelTransport.validates(trust))
    }

    @Test("Only the approved endpoint is rerouted; authorization and body survive")
    func route() throws {
        var request = URLRequest(url: URL(string: "https://\(HomeWiFiModelTransport.serverName)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer test-only", forHTTPHeaderField: "Authorization")
        let routed = try HomeWiFiModelTransport.routed(request)
        #expect(routed.url?.absoluteString == "https://192.168.1.75:11436/v1/chat/completions")
        #expect(routed.value(forHTTPHeaderField: "Host") == HomeWiFiModelTransport.serverName)
        #expect(routed.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
        #expect(routed.httpBody == request.httpBody)
    }

    @Test("Unapproved hosts, routes, methods and URL credentials never receive the key", arguments: [
        "http://jacks-mac-studio.tail6472bd.ts.net/v1/chat/completions",
        "https://example.invalid/v1/chat/completions",
        "https://jacks-mac-studio.tail6472bd.ts.net.evil.invalid/v1/chat/completions",
        "https://jacks-mac-studio.tail6472bd.ts.net:11434/v1/chat/completions",
        "https://user:password@jacks-mac-studio.tail6472bd.ts.net/v1/chat/completions",
        "https://jacks-mac-studio.tail6472bd.ts.net/v1/chat/completions?key=secret",
        "https://jacks-mac-studio.tail6472bd.ts.net/v1/chat/completions#fragment",
        "https://jacks-mac-studio.tail6472bd.ts.net/api/pull"
    ])
    func rejected(_ url: String) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        #expect(throws: ModelClientError.invalidURL) { try HomeWiFiModelTransport.routed(request) }
    }

    @Test("Read-only requests are not converted to model calls")
    func wrongMethod() {
        let request = URLRequest(url: URL(string: "https://\(HomeWiFiModelTransport.serverName)/v1/chat/completions")!)
        #expect(throws: ModelClientError.invalidURL) { try HomeWiFiModelTransport.routed(request) }
    }

    @Test("Live LAN HTTPS uses system trust and the existing access key", .enabled(if: ProcessInfo.processInfo.environment["POCKET_AGENT_LIVE_HOME_WIFI"] == "1"))
    func live() async throws {
        let keyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PocketAgent/model-gateway.key")
        let key = try String(contentsOf: keyURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let client = OpenAICompatibleClient(baseURL: "https://\(HomeWiFiModelTransport.serverName)/v1", model: "gpt-oss:20b", apiKey: key, transport: HomeWiFiModelTransport())
        let result = try await client.reply(to: [.init(role: .user, content: "Reply with Connected. This is a connection test.")], tools: [])
        #expect(!result.content.isEmpty)
    }
}
