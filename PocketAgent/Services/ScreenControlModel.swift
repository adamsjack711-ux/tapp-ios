import Combine
import Foundation
import Security
import UIKit

struct RunnerKeychainStore: ICTRLCredentialStore {
    private let account = "ictrl.loopback.v1"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.pocketagent.screen-control",
         kSecAttrAccount as String: account]
    }

    func load() throws -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw StoreError(status) }
        return data
    }

    func save(_ key: Data) throws {
        let attributes: [String: Any] = [kSecValueData as String: key,
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard status == errSecSuccess else { throw StoreError(status) }
        } else if status != errSecSuccess { throw StoreError(status) }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError(status) }
    }

    private struct StoreError: LocalizedError {
        let status: OSStatus
        init(_ status: OSStatus) { self.status = status }
        var errorDescription: String? { "Could not access the controller key in Keychain (\(status))." }
    }
}

/// A finite completion allowance, not an entitlement for persistent background work.
@MainActor
final class BackgroundAllowance {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    func begin(onExpiration: @escaping @MainActor () -> Void) {
        end()
        identifier = UIApplication.shared.beginBackgroundTask(withName: "hitapp approved step") { [weak self] in
            Task { @MainActor in
                onExpiration()
                self?.end()
            }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

@MainActor
final class ScreenControlModel: ObservableObject {
    @Published private(set) var isPaired = false
    @Published private(set) var isEnabled = false
    @Published private(set) var isWorking = false
    @Published private(set) var status = "Restoring your saved native screen-control access…"
    @Published private(set) var preview: ScreenResult?
    @Published var targetBundleID = "com.apple.Preferences"
    @Published var label = "General"
    @Published var elementType = ""
    @Published var typedText = ""
    @Published var swipeDirection = "up"
    @Published var interactionMode: ScreenInteractionMode = .act

    let client: ICTRLClient
    let controller: any ScreenActionController
    private let allowance = BackgroundAllowance()
    private var task: Task<Void, Never>?
    private let access = ScreenControlAccessStore()

    init() {
        client = ICTRLClient(credentials: RunnerKeychainStore())
        controller = NativeScreenController(device: NativeControlModel.shared, cursor: TappCursorModel.shared)
        targetBundleID = access.bundleID
        interactionMode = access.mode
        Task { isPaired = await client.isPaired() }
        if access.appEnabled { enable() }
        else { status = "Screen control is off by your choice. Re-enable it below when wanted." }
    }

    func startRunner() {
        guard !isWorking, !isEnabled else { return }
        guard !NativeControlModel.shared.connected, !NativeControlModel.shared.busy else {
            status = "Stop the native test before starting the legacy XCTest helper. The legacy helper brings back Automation Running."
            return
        }
        guard let url = URL(string: "ictrl://start?callback=pocketagent://screen-control"),
              UIApplication.shared.canOpenURL(url) else {
            status = "The screen helper is not installed or its launch link is missing. Install the signed helper with Xcode first. The iCTRL companion app is not required."
            return
        }
        run(status: "Opening the helper. Approve any iPhone passcode prompt; return here and check the connection.") {
            let opened = await UIApplication.shared.open(url)
            self.status = opened
                ? "Helper opened. This does not prove it is running: pair once, or use Check. After a reboot, Xcode must prepare the developer image again."
                : "The helper could not be opened. Check its installation and Developer Mode. Nothing was retried."
        }
    }

    func stopRunner() {
        guard !isWorking else { return }
        access.appEnabled = false
        isEnabled = false
        preview = nil
        run(status: "Stopping the optional screen helper…") {
            await self.controller.disable()
            let result = try await self.client.call("config", parameters: ["stop_server": .bool(true)])
            guard result["stopping"] == .bool(true) else { throw ICTRLError.invalidResponse }
            self.status = "The helper acknowledged shutdown. Screen Control is off. Start the helper and check it before the next session."
        }
    }

    func pair() {
        run(status: "Approve the Pocket Agent pairing request in the runner notification. No automatic retries.") {
            try await self.client.pair()
            self.isPaired = true
            self.status = "Paired. Enable control for one app to continue."
        }
    }

    func checkConnection() {
        run(status: "Checking the runner…") {
            let info = try await self.client.call("device_info")
            guard info["protocol_version"] == .number(1) else { throw ICTRLError.invalidResponse }
            self.isPaired = true
            self.status = "Connected to iCTRL \(info["server_version"]?.stringValue ?? "v1"). Device control is not yet verified."
        }
    }

    func enable() {
        let target = targetBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        run(status: "Restoring authorized screen control…") {
            guard FileManager.default.fileExists(atPath: URL.applicationSupportDirectory.appendingPathComponent("PocketControl/remote-pairing.plist").path) else {
                throw NativeScreenError.notPaired
            }
            try await self.controller.configure(enabled: true, allowedBundleID: target, mode: self.interactionMode)
            try Task.checkCancellation()
            self.targetBundleID = target
            self.isEnabled = true
            self.access.bundleID = target
            self.access.mode = self.interactionMode
            self.access.appEnabled = true
            self.preview = nil
            self.status = "Native \(self.interactionMode.rawValue) ready for \(target). Access stays enabled across launches. Reads, highlights, scrolling and supported navigation need no repeat access prompt. Unrecognized or consequential controls still need review. No XCTest."
        }
    }

    func stop() {
        task?.cancel()
        access.appEnabled = false
        isEnabled = false
        preview = nil
        status = "Stopped. A request already sent may have completed. Inspect the target app before retrying."
        Task { await controller.disable() }
    }

    func forget() {
        access.appEnabled = false
        run(status: "Forgetting the local pairing…") {
            await self.controller.disable()
            try await self.client.forget()
            self.isPaired = false
            self.isEnabled = false
            self.preview = nil
            self.status = "Local key removed. Revoke Pocket Agent in iCTRL's client list too if needed."
        }
    }

    func perform(_ action: ScreenAction) {
        var args: [String: JSONValue] = ["bundle_id": .string(targetBundleID)]
        if action != .read { args["observation_id"] = .string(preview?.observationID ?? "") }
        if action == .point || action == .tap || action == .type { args["label"] = .string(label) }
        if (action == .point || action == .tap), !elementType.isEmpty { args["element_type"] = .string(elementType) }
        if action == .type { args["text"] = .string(typedText) }
        if action == .swipe { args["direction"] = .string(swipeDirection) }
        run(status: "Performing your screen command…") {
            self.preview = nil
            let result = try await self.controller.perform(action, arguments: args, includeScreenshot: true)
            try Task.checkCancellation()
            self.preview = result
            self.status = result.outcome + (result.returnWarning.map { "\n\($0)" } ?? "")
        }
    }

    func receiveAgentResult(_ result: ScreenResult?) {
        preview = isEnabled ? result : nil
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Visual QA of a real UI-test capture. Does not pair or enable control.
    func loadRecordedSimulatorCapture() throws {
        let url = URL.documentsDirectory.appendingPathComponent("GuidanceCapture.json")
        preview = try JSONDecoder().decode(ScreenResult.self, from: Data(contentsOf: url))
        status = "Recorded simulator test capture. Screen control is still off."
    }
    #endif

    private func run(status: String, operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        self.status = status
        allowance.begin { [weak self] in
            self?.stop()
            self?.status = "iOS ended the background allowance. Reopen hitapp and inspect the phone before continuing."
        }
        task = Task {
            defer { isWorking = false; task = nil; allowance.end() }
            do {
                try await operation()
            } catch {
                if !Task.isCancelled {
                    self.status = error.localizedDescription + " No automatic retry. If a command was in flight, inspect the phone before trying again."
                }
            }
        }
    }
}
