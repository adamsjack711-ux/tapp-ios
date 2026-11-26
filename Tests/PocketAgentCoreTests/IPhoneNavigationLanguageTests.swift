import Testing
@testable import PocketAgentCore

@Suite("iPhone navigation language")
struct IPhoneNavigationLanguageTests {
    @Test(arguments: ["Tapp, take me Home", "Hey Tapp, can you please go home?", "Take me to the Home Screen."])
    func home(_ request: String) {
        #expect(HomeNavigationAction.directCommand(request) == .home)
    }

    @Test(arguments: ["show my open apps", "Tapp: switch apps", "Could you show recent apps?"])
    func switcher(_ request: String) {
        #expect(HomeNavigationAction.directCommand(request) == .appSwitcher)
    }

    @Test func pageAndSettingsAliases() {
        #expect(HomeNavigationAction.directCommand("next Home Screen page") == .pageLeft)
        #expect(HomeNavigationAction.directCommand("previous Home page") == .pageRight)
        #expect(HomeNavigationAction.directCommand("Tapp, take me to Settings") == .openSettings)
    }

    @Test func contentAndFingerDirectionsRemainDistinct() {
        #expect(IPhoneNavigationLanguage.intent("scroll down") == .swipe("up"))
        #expect(IPhoneNavigationLanguage.intent("swipe down") == .swipe("down"))
        #expect(IPhoneNavigationLanguage.intent("scroll up") == .swipe("down"))
        #expect(IPhoneNavigationLanguage.intent("swipe up") == .swipe("up"))
        #expect(IPhoneNavigationLanguage.intent("scroll left") == .swipe("right"))
        #expect(IPhoneNavigationLanguage.intent("scroll right") == .swipe("left"))
        #expect(HomeNavigationAction.directCommand("swipe left") == nil)
        #expect(HomeNavigationAction.directCommand("scroll down") == nil)
    }

    @Test(arguments: ["Don't go home", "How do I go home?", "Tapp, do not go home", "Go home then open Settings", "Screenshot text: go home", "Open Settings and disable Wi-Fi", "If I say go home, what happens?", "Show my open apps and close them", "Don't scroll down"])
    func questionsNegationsAndCompoundRequestsDoNotAutoExecute(_ request: String) {
        #expect(HomeNavigationAction.directCommand(request) == nil)
        #expect(IPhoneNavigationLanguage.intent(request) == nil)
    }

    @Test func backAndKeyboardNeedObservedControls() {
        #expect(IPhoneNavigationLanguage.intent("Tapp, go back") == .back)
        #expect(IPhoneNavigationLanguage.intent("Please hide the keyboard") == .dismissKeyboard)
        #expect(IPhoneNavigationLanguage.modelHint(for:.back).contains("do not invent"))
        #expect(IPhoneNavigationLanguage.modelHint(for:.dismissKeyboard).contains("Send"))
    }

    @Test func appLaunchStaysWithinConfiguredScope() {
        #expect(IPhoneNavigationLanguage.intent("Open Safari") == .openApp("com.apple.mobilesafari"))
        #expect(HomeNavigationAction.directCommand("Open Safari") == nil)
        let hint = IPhoneNavigationLanguage.modelHint(for:.openApp("com.apple.mobilesafari"))
        #expect(hint.contains("exactly matches the configured allowed app"))
        #expect(hint.contains("do not change the saved scope"))
    }

    @Test(arguments: ["Open Control Centre", "show notifications", "open spotlight", "switch to the previous app", "force quit this app", "lock my phone", "zoom in"])
    func unsupportedRequestsNeverBecomeAnotherAction(_ request: String) {
        guard case .unsupported(let explanation) = IPhoneNavigationLanguage.intent(request) else {
            Issue.record("Missing explicit unsupported response for \(request)")
            return
        }
        #expect(!explanation.isEmpty)
        #expect(HomeNavigationAction.directCommand(request) == nil)
    }

    @Test func discoverableHelp() {
        #expect(IPhoneNavigationLanguage.intent("Tapp, show navigation commands") == .help)
    }
}
