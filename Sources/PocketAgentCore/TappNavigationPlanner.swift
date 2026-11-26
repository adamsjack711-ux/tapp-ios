import Foundation

public enum TappNavigationPlanningError:LocalizedError,Equatable {
    case invalidRequest,invalidPlan,timedOut
    public var errorDescription:String? {
        switch self {
        case .invalidRequest: "Describe the App Switcher movement you want in 1–500 characters."
        case .invalidPlan: "Tapp couldn't turn that request into supported navigation. Ask to show open apps or browse cards left and right. No navigation started."
        case .timedOut: "Navigation planning took too long. No navigation started."
        }
    }
}

/// The model interprets intent; screenshots, cursor coordinates, gestures,
/// and outcome checks stay in the local navigation controller.
public struct TappNavigationPlanner:Sendable {
    public static let toolName="plan_tapp_navigation"
    private let model:any AgentModelClient
    public init(model:any AgentModelClient) { self.model=model }

    public static func request(in text:String)->String? {
        let text=text.trimmingCharacters(in:.whitespacesAndNewlines)
        for prefix in ["tapp navigate:","ai navigation:"] where text.lowercased().hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count)).trimmingCharacters(in:.whitespacesAndNewlines)
        }
        return nil
    }

    public func plan(request:String) async throws ->[AppSwitcherRequest] {
        let request=request.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !request.isEmpty,request.count<=500 else { throw TappNavigationPlanningError.invalidRequest }
        let definition=ToolDefinition(name:Self.toolName,description:"Plan up to eight App Switcher movements, without opening, closing, or interacting with app contents.",parameters:[
            "type":.string("object"),"properties":.object(["steps":.object([
                "type":.string("array"),"minItems":.number(1),"maxItems":.number(8),
                "items":.object(["type":.string("string"),"enum":.array(["show","left","right"].map(JSONValue.string))])])]),
            "required":.array([.string("steps")]),"additionalProperties":.bool(false)])
        let messages=[ModelMessage(role:.system,content:"""
        Interpret the user's iPhone App Switcher navigation request. Call plan_tapp_navigation
        exactly once with a finite ordered steps array. Supported steps: show open apps,
        swipe the cards left, swipe the cards right. Start with show. 'One older app' means
        right; 'one newer app' means left. 'Come back' reverses the preceding direction once.
        Do not invent a destination, app opening/closing, scrolling inside apps, taps, coordinates,
        settings changes or unbounded repetition. If any part of the request is unsupported or
        ambiguous, explain without calling a tool. A plan is not execution: do not claim success.
        The executor reads fresh screenshots and verifies cursor position locally between steps.
        """),ModelMessage(role:.user,content:request)]
        let reply=try await withThrowingTaskGroup(of:ModelReply.self) { group in
            group.addTask { try await model.reply(to:messages,tools:[definition]) }
            group.addTask { try await Task.sleep(for:.seconds(30));throw TappNavigationPlanningError.timedOut }
            defer { group.cancelAll() }
            guard let reply=try await group.next() else { throw TappNavigationPlanningError.invalidPlan }
            return reply
        }
        try Task.checkCancellation()
        guard reply.toolCalls.count==1,let call=reply.toolCalls.first,call.name==Self.toolName,
              Set(call.arguments.keys)==["steps"],case .array(let steps)=call.arguments["steps"],
              (1...8).contains(steps.count),steps.first == .string("show") else { throw TappNavigationPlanningError.invalidPlan }
        return try steps.map { value in
            switch value {
            case .string("show"): return .show
            case .string("left"): return .browseLeft
            case .string("right"): return .browseRight
            default: throw TappNavigationPlanningError.invalidPlan
            }
        }
    }
}
