import Foundation
import Testing
@testable import PocketAgentCore

@Suite("App Switcher plans")
struct AppSwitcherRequestTests {
    @Test func savedAccessSkipsReviewButStillRejectsInvalidClose() async throws {
        let device = SwitcherAccessFixture()
        let tool = AppSwitcherTool(device: device, requiresApproval: false)
        #expect(!tool.requiresApproval(arguments: ["action": .string("show")]))
        #expect(try await tool.execute(arguments: ["action": .string("show")]) == "Shown")
        await #expect(throws: ScreenControlError.invalidArguments) { try await tool.execute(arguments: ["action": .string("close")]) }
        #expect(await device.calls == [.show])
    }
    @Test func longPlan() {
        #expect(AppSwitcherRequest.plan("Show my open apps then swipe right then swipe left then reopen Tapp Click Test then close Tapp Click Test") == [.show,.browseRight,.browseLeft,.open("tapp click test"),.close("tapp click test")])
    }
    @Test(arguments: ["show my open apps then erase everything", "show my open apps then close all apps", "show my open apps then close this app", "show my open apps then close hitapp", "show my open apps then reopen Tapp Click Test twice", "show my open apps then swipe right twice then swipe left twice then swipe right twice then swipe left twice"])
    func rejectWholeInvalidPlan(_ text:String) { #expect(AppSwitcherRequest.plan(text) == nil) }
    @Test func boundedRepeats() {
        #expect(AppSwitcherRequest.plan("show my open apps and then swipe right twice then swipe left") == [.show,.browseRight,.browseRight,.browseLeft])
    }
    @Test func strictArguments() throws {
        #expect(try AppSwitcherRequest.decode(["action":.string("close"),"app_name":.string("Tapp Click Test")]) == .close("Tapp Click Test"))
        #expect(throws: ScreenControlError.self) { try AppSwitcherRequest.decode(["action":.string("close")]) }
        #expect(throws: ScreenControlError.self) { try AppSwitcherRequest.decode(["action":.string("right"),"x":.number(0.5)]) }
    }
    @Test func onlyUniqueCentralHeader() throws {
        let label = NativeScreenText(label:"Tapp Click Test",x:0.3,y:0.15,width:0.3,height:0.02)
        #expect(try AppSwitcherRequest.card(named:"tapp click test",in:.init(image:Data(),items:[label])) == label)
        #expect(throws: ScreenControlError.self) { try AppSwitcherRequest.card(named:"Tapp Click Test",in:.init(image:Data(),items:[label,label])) }
        let content = NativeScreenText(label:"Tapp Click Test",x:0.3,y:0.20,width:0.3,height:0.02)
        #expect(throws: ScreenControlError.self) { try AppSwitcherRequest.card(named:"Tapp Click Test",in:.init(image:Data(),items:[content])) }
        let partial = NativeScreenText(label:"Tapp Click Test",x:0.85,y:0.15,width:0.1,height:0.02)
        #expect(throws: ScreenControlError.self) { try AppSwitcherRequest.card(named:"Tapp Click Test",in:.init(image:Data(),items:[partial])) }
    }
}

private actor SwitcherAccessFixture: AppSwitcherDevice {
    var calls: [AppSwitcherRequest] = []
    func controlSwitcher(_ request: AppSwitcherRequest, operationID: UUID) async throws -> String { calls.append(request); return "Shown" }
    func cancel(operationID: UUID) async {}
}
