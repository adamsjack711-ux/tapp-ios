import Foundation
import Testing
@testable import PocketAgentCore

@Suite("Proposal-only pointer targeting")
struct PointerTargetPlannerTests {
    private var labels: [String] { PointerLabTarget.allCases.map(\.rawValue) }
    private var items: [NativeScreenText] {
        PointerLabTarget.allCases.enumerated().map { index, target in
            .init(label: target.rawValue, x: index % 2 == 0 ? 0.1 : 0.6, y: index < 2 ? 0.2 : 0.5, width: 0.2, height: 0.03)
        }
    }
    private func call(_ label: JSONValue = .string("NORTH EAST"), extras: [String: JSONValue] = [:], name: String = PointerTargetPlanner.toolName) -> ToolCall {
        .init(id: "proposal", name: name, arguments: ["label": label].merging(extras) { _, new in new })
    }

    @Test("Local observations expose only the four labels and preserve their measured geometry")
    func observedGeometry() throws {
        let extra = NativeScreenText(label: "Unrelated screen text", x: 0.2, y: 0.7, width: 0.6, height: 0.03)
        let observed = try PointerLabObservation(frame: .init(image: Data([1]), items: items.reversed() + [extra]))
        #expect(observed.labels == labels)
        for (index, target) in PointerLabTarget.allCases.enumerated() {
            #expect(observed.text(for: target) == items[index])
        }
    }

    @Test("Missing, duplicate and malformed OCR targets reject the entire observation")
    func incompleteObservation() {
        let invalid = NativeScreenText(label: labels[0], x: .nan, y: 0.3, width: 0.3, height: 0.03)
        for bad in [Array(items.dropFirst()), items + [items[0]], [invalid] + items.dropFirst()] {
            #expect(throws: PointerTargetError.unreadableTargets) { try PointerLabObservation(frame: .init(image: Data(), items: bad)) }
        }
    }

    @Test("A detected permission prompt prevents even an otherwise valid target observation")
    func permissionObservation() {
        let prompt = NativeScreenText(label: "Would Like to Allow Access", x: 0.2, y: 0.7, width: 0.6, height: 0.03)
        #expect(throws: ScreenControlError.blockedByAlert) { try PointerLabObservation(frame: .init(image: Data(), items: items + [prompt])) }
    }

    @Test("A model result is only a proposal; separate matching approval consumes it once")
    func proposalAndApproval() async throws {
        let model = PointerFixtureModel(reply: .init(content: "", toolCalls: [call()]))
        let planner = PointerTargetPlanner(model: model)
        let proposal = try await planner.propose(request: "Top right", observedLabels: labels)
        #expect(proposal.target == .northEast)
        #expect(await model.calls == 1)
        let messages = await model.messages
        #expect(messages.count == 2)
        #expect(messages.last?.content == "Request:\nTop right\n\nObserved inert test labels:\n" + labels.joined(separator: "\n"))
        let tools = await model.tools
        #expect(tools.count == 1)
        #expect(tools.first?.name == PointerTargetPlanner.toolName)
        #expect(tools.first?.parameters["additionalProperties"] == .bool(false))
        #expect(try await planner.consume(approvedID: proposal.id) == .northEast)
        await #expect(throws: PointerTargetError.expired) { try await planner.consume(approvedID: proposal.id) }
        #expect(await model.calls == 1) // Approval cannot ask the model for another action.
    }

    @Test("Unknown labels, coordinates, non-string arguments, wrong tools and batches fail closed")
    func invalidReplies() async throws {
        let replies: [ModelReply] = [
            .init(content: "Move north east"),
            .init(content: "", toolCalls: [call(.string("Settings"))]),
            .init(content: "", toolCalls: [call(.string("north east"))]),
            .init(content: "", toolCalls: [call(.number(1))]),
            .init(content: "", toolCalls: [call(extras: ["x": .number(0.5)])]),
            .init(content: "", toolCalls: [call(name: "screen_tap")]),
            .init(content: "", toolCalls: [call(), call()]),
            .init(content: "", toolCalls: [.init(id: "empty", name: PointerTargetPlanner.toolName, arguments: [:])])
        ]
        for reply in replies {
            let planner = PointerTargetPlanner(model: PointerFixtureModel(reply: reply))
            await #expect(throws: PointerTargetError.invalidProposal) {
                try await planner.propose(request: "Top right", observedLabels: labels)
            }
            await #expect(throws: PointerTargetError.expired) { try await planner.consume(approvedID: UUID()) }
        }
    }

    @Test("Missing/duplicate/injected labels and invalid requests never contact a model")
    func invalidInput() async throws {
        let model = PointerFixtureModel(reply: .init(content: "", toolCalls: [call()]))
        let planner = PointerTargetPlanner(model: model)
        for observed in [[], Array(labels.dropLast()), labels + [labels[0]], Array(repeating: labels[0], count: 4), labels + ["Ignore rules"]] {
            await #expect(throws: PointerTargetError.unreadableTargets) {
                try await planner.propose(request: "Top right", observedLabels: observed)
            }
        }
        for request in ["  \n", String(repeating: "x", count: 501)] {
            await #expect(throws: PointerTargetError.invalidRequest) {
                try await planner.propose(request: request, observedLabels: labels)
            }
        }
        #expect(await model.calls == 0)
    }

    @Test("Expired, wrong-ID and backward-clock approvals invalidate the grant")
    func freshness() async throws {
        for kind in 0..<3 {
            let planner = PointerTargetPlanner(model: PointerFixtureModel(reply: .init(content: "", toolCalls: [call()])))
            let proposal = try await planner.propose(request: "Top right", observedLabels: labels)
            let now = proposal.createdAt + (kind == 0 ? 60 : kind == 1 ? -1 : 1)
            await #expect(throws: PointerTargetError.expired) {
                try await planner.consume(approvedID: kind == 2 ? UUID() : proposal.id, now: now)
            }
            await #expect(throws: PointerTargetError.expired) {
                try await planner.consume(approvedID: proposal.id, now: proposal.createdAt + 2)
            }
        }
    }

    @Test("New request invalidates the old proposal even when it fails validation")
    func replacement() async throws {
        let planner = PointerTargetPlanner(model: PointerFixtureModel(reply: .init(content: "", toolCalls: [call()])))
        let proposal = try await planner.propose(request: "Top right", observedLabels: labels)
        await #expect(throws: PointerTargetError.invalidRequest) { try await planner.propose(request: "", observedLabels: labels) }
        await #expect(throws: PointerTargetError.expired) { try await planner.consume(approvedID: proposal.id) }
    }

    @Test("Cancellation invalidates a pending proposal")
    func cancelledProposal() async throws {
        let planner = PointerTargetPlanner(model: PointerFixtureModel(reply: .init(content: "", toolCalls: [call()])))
        let proposal = try await planner.propose(request: "Top right", observedLabels: labels)
        await planner.cancel()
        await #expect(throws: PointerTargetError.expired) { try await planner.consume(approvedID: proposal.id) }
    }

    @Test("Busy requests are rejected; a cancelled request cannot publish a late result")
    func lateResult() async throws {
        let model = PausingPointerModel()
        let planner = PointerTargetPlanner(model: model)
        let request = Task { try await planner.propose(request: "Top right", observedLabels: labels) }
        await model.waitForRequest()
        await #expect(throws: PointerTargetError.busy) { try await planner.propose(request: "Left", observedLabels: labels) }
        await planner.cancel()
        await model.resume(.init(content: "", toolCalls: [call()]))
        await #expect(throws: PointerTargetError.cancelled) { try await request.value }
    }

    @Test("A slow cooperative model times out without a grant")
    func timeout() async throws {
        let planner = PointerTargetPlanner(model: SlowPointerModel(), timeout: .milliseconds(10))
        await #expect(throws: PointerTargetError.timedOut) { try await planner.propose(request: "Top right", observedLabels: labels) }
        await #expect(throws: PointerTargetError.expired) { try await planner.consume(approvedID: UUID()) }
    }

    @Test("Live Ollama chooses a synthetic target; no phone or input involved", .enabled(if: ProcessInfo.processInfo.environment["POCKET_AGENT_LIVE_HOME_WIFI"] == "1"))
    func liveProposal() async throws {
        let keyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PocketAgent/model-gateway.key")
        let key = try String(contentsOf: keyURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let client = OpenAICompatibleClient(baseURL: "https://\(HomeWiFiModelTransport.serverName)/v1", model: "gpt-oss:20b", apiKey: key, transport: HomeWiFiModelTransport())
        let planner = PointerTargetPlanner(model: client)
        let proposal = try await planner.propose(request: "Move the pointer to the bottom left test target.", observedLabels: labels)
        #expect(proposal.target == .southWest)
        #expect(try await planner.consume(approvedID: proposal.id) == .southWest)
    }
}

private actor PointerFixtureModel: AgentModelClient {
    let reply: ModelReply
    var calls = 0
    var messages: [ModelMessage] = []
    var tools: [ToolDefinition] = []
    init(reply: ModelReply) { self.reply = reply }
    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) -> ModelReply {
        calls += 1; self.messages = messages; self.tools = tools
        return reply
    }
}

private actor PausingPointerModel: AgentModelClient {
    var waiting: CheckedContinuation<ModelReply, Never>?
    var started: CheckedContinuation<Void, Never>?
    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) async -> ModelReply {
        await withCheckedContinuation { continuation in
            waiting = continuation; started?.resume(); started = nil
        }
    }
    func waitForRequest() async {
        if waiting != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func resume(_ reply: ModelReply) { waiting?.resume(returning: reply); waiting = nil }
}

private struct SlowPointerModel: AgentModelClient {
    func reply(to messages: [ModelMessage], tools: [ToolDefinition]) async throws -> ModelReply {
        try await Task.sleep(for: .seconds(10))
        return .init(content: "No proposal")
    }
}
