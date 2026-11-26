import Foundation
import CryptoKit

enum SettingsKeys {
    static let baseURL = "model.baseURL"
    static let model = "model.name"
    static let apiKey = "model.apiKey"
    static let homeWiFi = "model.homeWiFi"
    static let ollamaBaseURL = "http://localhost:11434/v1"
    static let ollamaModel = "gpt-oss:20b"

    #if targetEnvironment(simulator)
    static func useLocalOllama() {
        UserDefaults.standard.set(ollamaBaseURL, forKey: baseURL)
        UserDefaults.standard.set(ollamaModel, forKey: model)
    }
    #endif
}

struct ConfiguredModelClient: AgentModelClient {
    // Reuse connection pools across tool rounds and planner instances. Configuration
    // and credentials are still read for every request; only transports are shared.
    private static let standardTransport = ModelURLSessionTransport()
    private static let homeWiFiTransport = HomeWiFiModelTransport()

    static func client(baseURL: String, model: String, apiKey: String, homeWiFi: Bool) -> any AgentModelClient {
        if apiKey.hasPrefix("tapp_") || URL(string: baseURL)?.host?.lowercased() == "api.openai.com" || URL(string: baseURL)?.path.hasSuffix("/responses") == true {
            return ResponsesModelClient(baseURL: baseURL, model: model, accessCode: apiKey,
                                        isTappBackend: apiKey.hasPrefix("tapp_"), transport: standardTransport)
        }
        let useLAN = homeWiFi && URL(string: baseURL)?.host == HomeWiFiModelTransport.serverName
        return OpenAICompatibleClient(baseURL: baseURL, model: model, apiKey: apiKey,
            transport: useLAN ? homeWiFiTransport : standardTransport)
    }
    func contextIdentifier() async -> String? {
        let defaults = UserDefaults.standard
        let value = [defaults.string(forKey: SettingsKeys.baseURL) ?? "",
                     defaults.string(forKey: SettingsKeys.model) ?? "",
                     KeychainStore.read(SettingsKeys.apiKey) ?? ""].joined(separator: "\n")
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) async throws -> ModelReply {
        let defaults = UserDefaults.standard
        let baseURL = defaults.string(forKey: SettingsKeys.baseURL)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = defaults.string(forKey: SettingsKeys.model)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if baseURL.isEmpty && model.isEmpty {
            return await DemoModelClient().reply(to: messages, tools: tools)
        }
        guard !baseURL.isEmpty, !model.isEmpty else { throw ModelClientError.invalidConfiguration }
        return try await Self.client(
            baseURL: baseURL, model: model,
            apiKey: KeychainStore.read(SettingsKeys.apiKey) ?? "",
            homeWiFi: defaults.object(forKey: SettingsKeys.homeWiFi) as? Bool ?? true
        ).reply(to: messages, tools: tools)
    }
}

private struct DemoModelClient: AgentModelClient {
    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) async -> ModelReply {
        let latest = messages.last(where: { $0.role == .user })?.content ?? ""
        if latest.contains("Text detected in the user-provided screenshot") {
            return ModelReply(content: "I extracted the visible text from your screenshot. Configure a model in Settings to explain it and suggest next steps.")
        }
        return ModelReply(content: "This is demo mode. Choose Ollama in Settings on the simulator, or add an HTTPS model provider, to enable live answers and tool use. Local Ollama needs no API key.")
    }
}
