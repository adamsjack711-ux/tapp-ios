import Testing
@testable import PocketAgentCore

struct TappAIPlannerTests {
    private var screen:String { TappTestTarget.allCases.map(\.rawValue).joined(separator:"\n") }
    private func call(_ label:String) -> ToolCall {
        ToolCall(id:"test",name:TappAIPlanner.toolName,arguments:["label":.string(label)])
    }

    @Test("AI can select each uniquely observed test target",arguments:TappTestTarget.allCases)
    func targetSelection(_ target:TappTestTarget) async throws {
        let model=TappPlannerModel(reply:ModelReply(toolCalls:[call(target.rawValue)]))
        let selected=try await TappAIPlanner(model:model).select(request:"Click that test button",screenText:screen+"\nPrivate unrelated screen text")
        #expect(selected==target)
        let messages=await model.messages
        #expect(!messages.contains { $0.content.contains("Private unrelated screen text") })
        #expect(messages.last?.content.contains(target.rawValue)==true)
    }

    @Test("Unknown, multiple and coordinate-bearing model commands never authorize a click",arguments:0..<5)
    func invalidReplies(_ kind:Int) async {
        let replies=[
            ModelReply(toolCalls:[call("Delete")]),
            ModelReply(toolCalls:[call("Top left"),call("Top right")]),
            ModelReply(toolCalls:[ToolCall(id:"x",name:TappAIPlanner.toolName,arguments:["label":.string("Top left"),"x":.number(0.1)])]),
            ModelReply(toolCalls:[ToolCall(id:"x",name:"screen_tap",arguments:["label":.string("Top left")])]),
            ModelReply(content:"Clicked it")]
        await #expect(throws:TappAIError.invalidSelection) {
            _ = try await TappAIPlanner(model:TappPlannerModel(reply:replies[kind])).select(request:"Click top left",screenText:screen)
        }
    }

    @Test("A missing or duplicate target stops before the model call",arguments:[false,true])
    func invalidObservation(_ duplicate:Bool) async {
        let model=TappPlannerModel(reply:ModelReply(toolCalls:[call("Top left")]))
        let invalid=duplicate ? screen+"\nTop left" : screen.replacingOccurrences(of:"Top left",with:"Top left done")
        await #expect(throws:TappAIError.fixtureNotReady) {
            _ = try await TappAIPlanner(model:model).select(request:"Click top left",screenText:invalid)
        }
        #expect(await model.messages.isEmpty)
    }

    @Test("Success requires exactly the selected counter to change")
    func verifiesObservedOutcome() throws {
        let correct=screen.replacingOccurrences(of:"Top right",with:"Top right done")
        try TappAIPlanner.verifyResult(correct,selected:.topRight)
        #expect(throws:TappAIError.resultNotVerified) { try TappAIPlanner.verifyResult(screen,selected:.topRight) }
        #expect(throws:TappAIError.resultNotVerified) {
            try TappAIPlanner.verifyResult(correct.replacingOccurrences(of:"Top left",with:"Top left done"),selected:.topRight)
        }
        #expect(throws:TappAIError.resultNotVerified) { try TappAIPlanner.verifyResult(correct+"\nTop right done",selected:.topRight) }
    }
}

private actor TappPlannerModel:AgentModelClient {
    let response:ModelReply
    private(set) var messages:[ModelMessage]=[]
    init(reply:ModelReply) { response=reply }
    func reply(to messages:[ModelMessage],tools:[ToolDefinition]) async throws -> ModelReply {
        self.messages=messages
        return response
    }
}
