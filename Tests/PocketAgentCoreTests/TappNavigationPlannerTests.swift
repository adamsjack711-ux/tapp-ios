import Testing
@testable import PocketAgentCore

struct TappNavigationPlannerTests {
    private func reply(_ steps:[JSONValue],extras:[String:JSONValue]=[:])->ModelReply {
        .init(toolCalls:[.init(id:"plan",name:TappNavigationPlanner.toolName,
            arguments:["steps":.array(steps)].merging(extras) { _,new in new })])
    }

    @Test("Natural language produces one bounded navigation plan")
    func validPlan() async throws {
        let model=NavigationPlanningModel(response:reply([.string("show"),.string("right"),.string("left")]))
        let result=try await TappNavigationPlanner(model:model).plan(request:"Browse one older card, then come back")
        #expect(result == [.show,.browseRight,.browseLeft])
        #expect(await model.calls==1)
    }

    @Test("Unknown operations, arbitrary coordinates, missing show and oversized plans fail before navigation",arguments:0..<6)
    func invalidPlans(_ kind:Int) async {
        let responses=[reply([.string("show"),.string("close")]),reply([.string("left")]),reply([]),
            reply(Array(repeating:.string("show"),count:9)),reply([.string("show")],extras:["x":.number(0.5)]),
            reply([.string("show"),.object(["action":.string("tap")])])]
        await #expect(throws:TappNavigationPlanningError.invalidPlan) {
            _ = try await TappNavigationPlanner(model:NavigationPlanningModel(response:responses[kind])).plan(request:"Show open apps")
        }
    }

    @Test("Empty requests do not call the model")
    func empty() async {
        let model=NavigationPlanningModel(response:reply([.string("show")]))
        await #expect(throws:TappNavigationPlanningError.invalidRequest) { _ = try await TappNavigationPlanner(model:model).plan(request:" ") }
        #expect(await model.calls==0)
    }

    @Test("Only an explicit navigation entry point selects the planner")
    func entryPoint() {
        #expect(TappNavigationPlanner.request(in:"Tapp navigate: show my apps")=="show my apps")
        #expect(TappNavigationPlanner.request(in:"Tell me about AI navigation")==nil)
    }
}

private actor NavigationPlanningModel:AgentModelClient {
    let response:ModelReply
    private(set) var calls=0
    init(response:ModelReply) { self.response=response }
    func reply(to messages:[ModelMessage],tools:[ToolDefinition]) async throws ->ModelReply { calls+=1;return response }
}
