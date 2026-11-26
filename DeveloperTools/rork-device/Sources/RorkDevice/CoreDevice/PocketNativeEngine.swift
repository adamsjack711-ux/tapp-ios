import Foundation

/// An authenticated, device-bound CoreDevice session. No XCTest calls. The app
/// owns consent, foreground scope, observed coordinates and finite task lifetime.
public actor PocketNativeEngine {
    private let network: CoreDeviceUserspaceNetwork
    private let discovery: RemoteServiceDiscoverySession
    private let sink: PocketNativeMediaSink
    private var display: RemoteXPCConnection?
    private var touchChannel: RemoteXPCConnection?
    private var touchChannelOpened = ContinuousClock.now
    private var mediaSessionID: Data?
    private var mediaPacketBaseline = 0
    private var stopped = false
    private let allowedBundleID: String
    public private(set) var mediaDiagnostic = "No media session started"

    private init(network: CoreDeviceUserspaceNetwork, discovery: RemoteServiceDiscoverySession, sink: PocketNativeMediaSink, allowedBundleID: String) {
        self.network = network; self.discovery = discovery; self.sink = sink
        self.allowedBundleID = allowedBundleID
    }

    public static func connect(host: String, identity: RemotePairingIdentity, expectedDevice: String, allowedBundleID: String = "com.apple.Preferences") async throws -> PocketNativeEngine {
        let tunnel = try await PocketControlProbe.connect(to: host, using: identity)
        let sink = PocketNativeMediaSink()
        let network: CoreDeviceUserspaceNetwork
        do { network = try CoreDeviceUserspaceNetwork(tunnel: tunnel, connectionTimeout: .seconds(5), mediaSink: sink) }
        catch { tunnel.close(); throw error }
        let deadline = Task { try? await Task.sleep(for: .seconds(10)); if !Task.isCancelled { network.close() } }
        defer { deadline.cancel() }
        do {
            guard let peerIdentity = UUID(uuidString: identity.identifier) else {
                throw RorkDeviceError.invalidInput("Native pairing identity is not a stable UUID.")
            }
            let discovery = try await RemoteServiceDiscoverySession.open(over: network.connect(to: network.configuration.serviceDiscoveryPort), peerIdentity: peerIdentity)
            guard discovery.directory.deviceIdentifier == expectedDevice else {
                discovery.close()
                throw RorkDeviceError.invalidInput("Native engine reached a different device.")
            }
            return PocketNativeEngine(network: network, discovery: discovery, sink: sink, allowedBundleID: allowedBundleID)
        } catch { network.close(); throw error }
    }

    /// Hard cancellation can close transport from an expiration handler even
    /// while the actor is awaiting a service reply.
    public nonisolated func abort() { network.close() }

    public func close() async {
        guard !stopped else { return }
        stopped = true
        try? await stopMedia()
        discovery.close(); network.close()
    }

    public func screenshot() async throws -> Data {
        let channel: RemoteXPCConnection
        do { channel = try await open("com.apple.coredevice.screencaptureservice", pipelined: true) }
        catch { throw RorkDeviceError.transport("Screenshot setup failed: \(error.localizedDescription)") }
        defer { channel.close() }
        let output = try await invoke(channel, feature: "capturescreenshot", action: "capturescreenshot", input: [
            "displayUniqueID": .null, "requestedFormat": .string("png")
        ])
        guard case let .data(image) = output.dictionaryValue?["image"],
              image.count <= 20 * 1024 * 1024,
              image.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
            throw RorkDeviceError.protocolViolation("Native screenshot did not return a bounded PNG.")
        }
        return image
    }

    public func launch(bundleID: String) async throws {
        guard [allowedBundleID, "com.jackadamslovell.PocketAgent"].contains(bundleID) else {
            throw RorkDeviceError.invalidInput("Native launch is restricted to the explicitly allowed app and Pocket Agent.")
        }
        let connection = try await raw("com.apple.coredevice.appservice")
        let deadline = closeAfter(connection, seconds: 8)
        defer { deadline.cancel(); connection.close() }
        let service = try await CoreDeviceApplicationService.open(over: connection)
        _ = try await service.launchApplication(bundleIdentifier: bundleID, options: .init())
    }

    public func requireLegacyRunnerStopped() async throws {
        let connection = try await raw("com.apple.coredevice.appservice")
        let deadline = closeAfter(connection, seconds: 8)
        defer { deadline.cancel(); connection.close() }
        let service = try await CoreDeviceApplicationService.open(over: connection)
        let processes = try await service.runningProcesses()
        guard !processes.contains(where: { $0.executablePath.hasSuffix("/iCTRLUITests-Runner.app/iCTRLUITests-Runner") }) else {
            throw RorkDeviceError.invalidInput("The legacy XCTest helper is still running. Shut it down in Screen Control before using native control; it causes Automation Running.")
        }
    }

    /// Reset only our disposable counter fixture; never another allowed app.
    public func resetClickTestFixture() async throws {
        guard allowedBundleID == "com.jackadamslovell.TappClickTarget" else {
            throw RorkDeviceError.invalidInput("Only the Tapp counter fixture can be reset.")
        }
        let connection = try await raw("com.apple.coredevice.appservice")
        let deadline = closeAfter(connection, seconds: 8)
        defer { deadline.cancel(); connection.close() }
        let service = try await CoreDeviceApplicationService.open(over: connection)
        _ = try await service.launchApplication(bundleIdentifier:allowedBundleID,options:.init(terminateExistingProcess:true))
    }

    public struct SwitcherAppIdentity: Sendable {
        public let bundleIdentifier: String
        public let displayName: String
        fileprivate let bundlePath: String
    }

    public func installedSwitcherApps() async throws -> [SwitcherAppIdentity] {
        guard allowedBundleID == "com.jackadamslovell.PocketAgent" else {
            throw RorkDeviceError.invalidInput("App Switcher needs the navigation scope.")
        }
        let connection = try await raw("com.apple.coredevice.appservice")
        let deadline = closeAfter(connection,seconds:8)
        defer { deadline.cancel(); connection.close() }
        let service = try await CoreDeviceApplicationService.open(over:connection)
        return try await service.applications(matching:.all,streaming:true)
            .filter { !$0.isInternal && $0.bundleIdentifier != "com.apple.springboard" }
            .map { .init(bundleIdentifier:$0.bundleIdentifier,displayName:$0.displayName,bundlePath:$0.bundlePath) }
    }

    public func resolveSwitcherApp(named name:String) async throws -> SwitcherAppIdentity {
        let matches = try await installedSwitcherApps().filter {
            $0.bundleIdentifier != "com.jackadamslovell.PocketAgent" &&
            $0.displayName.caseInsensitiveCompare(name.trimmingCharacters(in:.whitespacesAndNewlines)) == .orderedSame
        }
        guard matches.count == 1,let app = matches.first else {
            throw RorkDeviceError.invalidInput("Name one uniquely installed app other than hitapp. No card was touched.")
        }
        return app
    }

    public func openSwitcherFromBottom(observedBottomY:Double) async throws {
        guard allowedBundleID == "com.jackadamslovell.PocketAgent", display != nil,
              mediaSessionID != nil, observedBottomY.isFinite,(0.95...0.995).contains(observedBottomY) else {
            throw RorkDeviceError.invalidInput("A bottom edge validated against the fresh screen is required.")
        }
        try await sendGesture(start:(0.5,observedBottomY),end:(0.5,0.60),holdMilliseconds:600)
    }

    public func switcherAppIsRunning(_ app:SwitcherAppIdentity) async throws -> Bool {
        let connection = try await raw("com.apple.coredevice.appservice")
        let deadline = closeAfter(connection, seconds:8)
        defer { deadline.cancel(); connection.close() }
        let service = try await CoreDeviceApplicationService.open(over:connection)
        return try await service.runningProcesses().contains { CoreDeviceApplicationService.executable($0.executablePath,belongsTo:app.bundlePath) }
    }

    /// Coordinates come only from a locally revalidated App Switcher header.
    /// Continuous contact starts in the lower card, never as a separate tap.
    public func dragSwitcherCard(x:Double = 0.5,direction:String) async throws {
        guard allowedBundleID == "com.jackadamslovell.PocketAgent",display != nil,
              mediaSessionID != nil,sink.packetsReceived > mediaPacketBaseline,
              x.isFinite,(0.20...0.80).contains(x) else {
            throw RorkDeviceError.invalidInput("A verified App Switcher card is required.")
        }
        let end:(Double,Double)
        switch direction {
        case "left": end = (0.20,0.81)
        case "right": end = (0.80,0.81)
        case "up": end = (x,0.38)
        default: throw RorkDeviceError.invalidInput("Unsupported App Switcher drag.")
        }
        // Horizontal browsing must settle before lifting. A constant-velocity
        // release flings several cards, taking the hosted cursor with them.
        try await sendGesture(start:(x,0.81),end:end,holdMilliseconds:direction == "up" ? 0 : 120,
                              initialHoldMilliseconds:180,settleMotion:direction != "up")
    }

    /// Collapse only the app's own visually identified progress banner.
    public func collapseNavigationBanner() async throws {
        guard allowedBundleID == "com.jackadamslovell.PocketAgent", display != nil,
              mediaSessionID != nil, sink.packetsReceived > mediaPacketBaseline else {
            throw RorkDeviceError.invalidInput("Authenticated navigation media is required.")
        }
        try await sendGesture(start:(0.5,0.085),end:(0.5,0.02),holdMilliseconds:0)
    }

    public func mediaStatus() async throws -> String {
        let channel = try await open("com.apple.coredevice.displayservice")
        defer { channel.close() }
        let output = try await invoke(channel, feature: "getmediastreamserverstatus", action: "mediastreamstatus", input: [:])
        return Self.summary(output)
    }

    /// Read-only inventory. Never exports serial numbers, pairing material or
    /// screen data. Used to distinguish a real pointer from a mirror-only one.
    public func pointerInventory() async throws -> String {
        let channel = try await open("com.apple.coredevice.hid.universalhidservice")
        defer { channel.close() }
        let reply = try await hidRequest(channel, payload: ["connectedServices": .dictionary([:])])
        return Self.pointerInventorySummary(reply)
    }

    private func hidRequest(_ channel: RemoteXPCConnection, payload: [String: RemoteXPCValue]) async throws -> RemoteXPCValue {
        let deadline = Task { try? await Task.sleep(for: .seconds(8)); if !Task.isCancelled { channel.close() } }
        defer { deadline.cancel() }
        try await channel.send(.dictionary([
            "featureIdentifier": .string("com.apple.coredevice.feature.remote.universalhidservice"),
            "messageType": .string("Request"), "payload": .dictionary(payload)
        ]), additionalFlags: 0x10000)
        for _ in 0..<16 {
            let reply = try await channel.receive(on: .reply, acceptingEitherStream: true)
            if let value = reply.value, value != .dictionary([:]) { return value }
        }
        throw RorkDeviceError.protocolViolation("HID service returned no reply.")
    }

    static func pointerInventorySummary(_ value: RemoteXPCValue, key: String = "", depth: Int = 0) -> String {
        guard depth < 8 else { return "…" }
        let permitted = ["_ServiceID", "PrimaryUsage", "PrimaryUsagePage", "Product", "DeviceTypeHint", "PointerAccelerationType", "_CoreDevice_suppressMousePointer", "ReportDescriptor"]
        if permitted.contains(key) { return summary(value) }
        switch value {
        case .dictionary(let fields):
            return "{" + fields.keys.sorted().map { $0 + ": " + pointerInventorySummary(fields[$0]!, key: $0, depth: depth + 1) }.joined(separator: ", ") + "}"
        case .array(let values): return "[" + values.prefix(32).map { pointerInventorySummary($0, depth: depth + 1) }.joined(separator: ", ") + "]"
        case .data(let data): return "<\(data.count) bytes>"
        default: return "<omitted>"
        }
    }

    /// Experimental, motion-only virtual mouse. Must be started by an explicit
    /// local approval. The caller checks Pocket Agent remains foreground before
    /// every sample. Never touches an existing HID device or starts XCTest.
    public func probePointerMovement(
        duration: PocketPointerDuration = .standard,
        continueWhile: @Sendable () async -> Bool,
        completed: @Sendable () async -> Bool = { false },
        nextMotion: @Sendable (Double) async throws -> PocketPointerMotion
    ) async throws -> String {
        guard display != nil, mediaSessionID != nil, sink.packetsReceived > mediaPacketBaseline else {
            throw RorkDeviceError.invalidInput("Native media authentication is not verified; no mouse created.")
        }
        try await requireLegacyRunnerStopped()
        let channel = try await open("com.apple.coredevice.hid.universalhidservice")
        defer { channel.close() }
        let before = try await PocketPointerProbe.services(hidRequest(channel, payload: ["connectedServices": .dictionary([:])]))
        // A new session-specific identity, not Apple's built-in pointer ID.
        let serviceID = UInt64.random(in: 0x100000000...0x1ffffffff)
        guard !before.contains(where: { $0["_ServiceID"] == .uint64(serviceID) }) else {
            throw RorkDeviceError.invalidInput("Pointer identity collision. No device created.")
        }
        try Task.checkCancellation()
        guard await continueWhile() else { throw CancellationError() }
        var attemptedCreation = false
        var motionError: Error?
        var reports = 0
        var reachedTarget = false
        do {
            attemptedCreation = true
            let response = try await hidRequest(channel, payload: ["createService": .dictionary(["_0": PocketPointerProbe.creation(serviceID: serviceID)])])
            guard response.dictionaryValue?["serviceID"] == .uint64(serviceID) else {
                throw RorkDeviceError.protocolViolation("Mouse registration did not return our requested identity. No motion sent.")
            }
            let registered = try await PocketPointerProbe.services(hidRequest(channel, payload: ["connectedServices": .dictionary([:])]))
            try PocketPointerProbe.verifyCreated(registered, serviceID: serviceID)
            try await Task.sleep(for: .milliseconds(500))
            let clock = ContinuousClock()
            let started = clock.now
            let deadline = started.advanced(by: .seconds(duration.rawValue))
            // Wall-clock bounded: captures pause movement rather than extending
            // the test. A second report-count ceiling prevents a tight loop.
            while clock.now < deadline, reports < duration.rawValue * 50 {
                    try Task.checkCancellation()
                    guard !stopped, await continueWhile() else { throw CancellationError() }
                    let elapsed = started.duration(to: clock.now).components
                    let motion = try await nextMotion(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
                    try Task.checkCancellation()
                    guard !stopped, await continueWhile() else { throw CancellationError() }
                    if await completed() { reachedTarget = true; break }
                    try Task.checkCancellation()
                    guard clock.now < deadline else { break }
                    try await channel.send(.dictionary([
                        "featureIdentifier": .string("com.apple.coredevice.feature.remote.universalhidservice"),
                        "messageType": .string("Request"), "payload": .dictionary(["send": .dictionary([
                            "_0": .data(try PocketPointerProbe.motion(dx: motion.dx, dy: motion.dy)), "_1": .uint64(serviceID)
                        ])])
                    ]))
                    reports += 1
                    try await Task.sleep(for: .milliseconds(20))
            }
        } catch { motionError = error }

        if attemptedCreation {
            // Only this experiment's non-existing-before ID can be removed.
            // Use a fresh channel: the request channel might have timed out.
            let cleanup = try await open("com.apple.coredevice.hid.universalhidservice")
            defer { cleanup.close() }
            try await cleanup.send(.dictionary([
                "featureIdentifier": .string("com.apple.coredevice.feature.remote.universalhidservice"),
                "messageType": .string("Request"),
                "payload": .dictionary(["removeService": .dictionary(["_0": .uint64(serviceID)])])
            ]))
            let remaining = try await PocketPointerProbe.services(hidRequest(cleanup, payload: ["connectedServices": .dictionary([:])]))
            guard !remaining.contains(where: { $0["_ServiceID"] == .uint64(serviceID) }) else {
                throw RorkDeviceError.protocolViolation("Temporary mouse cleanup could not be verified. Stop the native engine; do not repeat the test.")
            }
        }
        if let motionError {
            if motionError is CancellationError { throw motionError }
            throw RorkDeviceError.protocolViolation("\(motionError.localizedDescription) Sent \(reports) motion reports. Temporary mouse removal verified.")
        }
        let ending = reachedTarget ? "Stopped at the observed target" : "Completed \(duration.rawValue)-second window"
        return "\(ending): \(reports) native-format motion-only reports (\(PocketPointerProbe.reportByteCount) bytes each). Temporary mouse removal verified. Dispatch alone is not proof of physical pointer movement."
    }

    /// Bounded, separately authorized one-click path. The old probe is still
    /// motion-only. Position and destination must be freshly checked by caller.
    public func movePointerAndClick(
        continueWhile: @Sendable () async -> Bool,
        nextStep: @Sendable (Double) async throws -> PocketPointerClickStep,
        beforeClick: @Sendable () async throws -> Void
    ) async throws -> String {
        guard display != nil, mediaSessionID != nil, sink.packetsReceived > mediaPacketBaseline else {
            throw RorkDeviceError.invalidInput("Native media is not authenticated; no click mouse created.")
        }
        try await requireLegacyRunnerStopped()
        let channel = try await open("com.apple.coredevice.hid.universalhidservice")
        defer { channel.close() }
        let before = try await PocketPointerProbe.services(hidRequest(channel, payload: ["connectedServices": .dictionary([:])]))
        let id = UInt64.random(in: 0x200000000...0x2ffffffff)
        guard !before.contains(where: { $0["_ServiceID"] == .uint64(id) }) else {
            throw RorkDeviceError.invalidInput("Click mouse identity collision.")
        }
        var failure: Error?, attemptedCreation = false, buttonMayBeDown = false, clicked = false, reports = 0
        do {
            try Task.checkCancellation()
            guard await continueWhile() else { throw CancellationError() }
            attemptedCreation = true
            let response = try await hidRequest(channel, payload: ["createService": .dictionary(["_0": PocketPointerClick.creation(serviceID: id)])])
            guard response.dictionaryValue?["serviceID"] == .uint64(id) else {
                throw RorkDeviceError.protocolViolation("Click mouse registration identity mismatch.")
            }
            try PocketPointerClick.verify(try await PocketPointerProbe.services(hidRequest(channel, payload: ["connectedServices": .dictionary([:])])), id: id)
            let clock = ContinuousClock(), started = ContinuousClock.now
            while started.duration(to: clock.now) < .seconds(30), reports < 1500 {
                try Task.checkCancellation()
                guard !stopped, await continueWhile() else { throw CancellationError() }
                let elapsed = started.duration(to: clock.now).components
                let step = try await nextStep(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
                try Task.checkCancellation()
                guard !stopped, await continueWhile() else { throw CancellationError() }
                switch step {
                case .move(let motion):
                    try await sendPointerReport(PocketPointerProbe.motion(dx: motion.dx, dy: motion.dy), id: id, channel: channel)
                    reports += 1
                    try await Task.sleep(for: .milliseconds(20))
                case .click:
                    // This callback rechecks screen and position, and persists
                    // the single-send journal BEFORE a message's button-down.
                    try await beforeClick()
                    try Task.checkCancellation()
                    guard !stopped, await continueWhile(), started.duration(to: clock.now) < .seconds(30) else { throw CancellationError() }
                    buttonMayBeDown = true
                    try await sendPointerReport(PocketPointerClick.button(pressed: true), id: id, channel: channel)
                    try? await Task.sleep(for: .milliseconds(80))
                    try await sendPointerReport(PocketPointerClick.button(pressed: false), id: id, channel: channel)
                    buttonMayBeDown = false; clicked = true
                }
                if clicked { break }
            }
            if !clicked { throw RorkDeviceError.invalidInput("Pointer did not reach a verified target in 30 seconds. No click dispatched.") }
        } catch { failure = error }
        if attemptedCreation {
            // Unstructured task permits button release and own-device cleanup
            // even if the controlling task was cancelled. Never touch another ID.
            try await Task { try await self.cleanupClickMouse(id: id, release: buttonMayBeDown) }.value
        }
        if let failure { throw failure }
        return "One primary-button down/up dispatched after \(reports) movement reports. Own click mouse removed. Application result must verify activation."
    }

    private func sendPointerReport(_ data: Data, id: UInt64, channel: RemoteXPCConnection) async throws {
        try await channel.send(.dictionary([
            "featureIdentifier": .string("com.apple.coredevice.feature.remote.universalhidservice"),
            "messageType": .string("Request"), "payload": .dictionary(["send": .dictionary([
                "_0": .data(data), "_1": .uint64(id)
            ])])
        ]))
    }

    private func cleanupClickMouse(id: UInt64, release: Bool) async throws {
        let cleanup = try await open("com.apple.coredevice.hid.universalhidservice")
        defer { cleanup.close() }
        if release { try? await sendPointerReport(PocketPointerClick.button(pressed: false), id: id, channel: cleanup) }
        try await cleanup.send(.dictionary([
            "featureIdentifier": .string("com.apple.coredevice.feature.remote.universalhidservice"),
            "messageType": .string("Request"), "payload": .dictionary(["removeService": .dictionary(["_0": .uint64(id)])])
        ]))
        let remaining = try await PocketPointerProbe.services(hidRequest(cleanup, payload: ["connectedServices": .dictionary([:])]))
        guard !remaining.contains(where: { $0["_ServiceID"] == .uint64(id) }) else {
            throw RorkDeviceError.protocolViolation("Own click mouse removal was not verified. Do not retry.")
        }
    }

    public func startMedia() async throws -> String {
        guard display == nil else { return mediaDiagnostic }
        let channel = try await open("com.apple.coredevice.displayservice")
        do {
            var uuid = UUID().uuid
            let sessionID = withUnsafeBytes(of: &uuid) { Data($0) }
            mediaPacketBaseline = sink.packetsReceived
            let output = try await invoke(channel, feature: "startmediastream", action: "mediastreamstart", input: [
                "clientSupportedFeatures": .uint64(140), "direction": .string("output"),
                "negotiatorOffer": .data(try PocketNativeWire.offer(sessionID: UInt32.random(in: 1...UInt32.max))),
                "options": .dictionary([
                    "AVCMediaStreamNegotiatorAccessNetworkType": .dictionary(["int": .int64(1)]),
                    "AVCMediaStreamNegotiatorTransportProtocolType": .dictionary(["int": .int64(2)]),
                    "CoreDeviceVideoDisplayMode": .dictionary(["string": .string("DisplayByID")]),
                    "VideoStreamForDisplayID": .dictionary(["int": .int64(1)]),
                    "avcMediaStreamOptionClientSessionID": .dictionary(["uuid": .uuid(sessionID)])
                ]),
                "receiverIP": .string(network.configuration.hostAddress), "receiverPort": .uint64(UInt64(sink.port)),
                "senderIP": .string(network.configuration.deviceAddress), "timeout": .uint64(10), "type": .string("video")
            ])
            mediaDiagnostic = Self.summary(output)
            let returnedID = output.dictionaryValue?["connection"]?.dictionaryValue?["options"]?.dictionaryValue?["avcMediaStreamOptionClientSessionID"]?.dictionaryValue?["uuid"]
            guard returnedID == .uuid(sessionID) else {
                throw RorkDeviceError.protocolViolation("Media reply did not echo our session identity. No input allowed.")
            }
            mediaSessionID = sessionID
            display = channel
            try await Task.sleep(for: .milliseconds(600))
            return mediaDiagnostic + "\nReceived video datagrams: \(sink.packetsReceived)"
        } catch { channel.close(); throw error }
    }

    public func tap(x: Double, y: Double) async throws -> Int {
        try await tapWithHold(x:x,y:y,holdMilliseconds:70)
    }

    public func hold(x:Double,y:Double) async throws -> Int {
        try await tapWithHold(x:x,y:y,holdMilliseconds:650)
    }

    public func drag(fromX:Double,fromY:Double,toX:Double,toY:Double) async throws {
        guard display != nil,mediaSessionID != nil,sink.packetsReceived > mediaPacketBaseline,
              [fromX,fromY,toX,toY].allSatisfy({ $0.isFinite && (0.02...0.98).contains($0) }) else {
            throw RorkDeviceError.invalidInput("A fresh pair of visible drag targets and authenticated native media are required.")
        }
        try await sendGesture(start:(fromX,fromY),end:(toX,toY),holdMilliseconds:120,initialHoldMilliseconds:500,settleMotion:true)
    }

    public func selectSwitcherCard(x:Double) async throws -> Int {
        guard allowedBundleID == "com.jackadamslovell.PocketAgent", (0.20...0.80).contains(x) else {
            throw RorkDeviceError.invalidInput("A verified navigation card is required.")
        }
        return try await tapWithHold(x:x,y:0.72,holdMilliseconds:180)
    }

    private func tapWithHold(x:Double,y:Double,holdMilliseconds:Int) async throws -> Int {
        guard display != nil, mediaSessionID != nil, sink.packetsReceived > mediaPacketBaseline else {
            throw RorkDeviceError.invalidInput("Native media authentication is not verified; no touch sent.")
        }
        // Renew between completed gestures, before the service's long-session
        // disconnect can interrupt a press. Never renew/replay after sending.
        if touchChannel != nil, touchChannelOpened.duration(to:.now) >= .seconds(45) {
            touchChannel?.close(); touchChannel = nil
        }
        let channel: RemoteXPCConnection
        if let touchChannel { channel = touchChannel }
        else {
            channel = try await open("com.apple.coredevice.hid.universalhidservice")
            touchChannel = channel
            touchChannelOpened = .now
            _ = try await hidRequest(channel, payload: ["connectedServices": .dictionary([:])])
        }
        func report(_ contact: Bool) throws -> RemoteXPCValue {
            .dictionary([
                "featureIdentifier": .string("com.apple.coredevice.feature.remote.universalhidservice"),
                "messageType": .string("Request"),
                "payload": .dictionary(["send": .dictionary([
                    "_0": .data(try PocketNativeWire.touch(x: x, y: y, contact: contact, timestamp: DispatchTime.now().uptimeNanoseconds)),
                    "_1": .uint64(257)
                ])])
            ])
        }
        do {
            try await channel.send(report(true))
            // Always send the matching release, even if cancellation arrives here.
            try? await Task.sleep(for: .milliseconds(holdMilliseconds))
            // Stamp release after the hold, at its actual send time.
            try await channel.send(report(false))
            // A write alone does not prove peer consumption. Keep the same
            // channel throughout the owned media session and await a reply.
            _ = try await hidRequest(channel, payload: ["connectedServices": .dictionary([:])])
        } catch {
            channel.close(); touchChannel = nil
            throw error // Never retry an uncertain input.
        }
        return sink.packetsReceived
    }

    public func swipe(direction: String) async throws {
        guard display != nil, mediaSessionID != nil, sink.packetsReceived > mediaPacketBaseline else {
            throw RorkDeviceError.invalidInput("Native media authentication is not verified; no swipe sent.")
        }
        let start: (Double, Double), end: (Double, Double)
        switch direction {
        case "up": start = (0.5, 0.72); end = (0.5, 0.32)
        case "down": start = (0.5, 0.32); end = (0.5, 0.72)
        case "left": start = (0.75, 0.55); end = (0.25, 0.55)
        case "right": start = (0.25, 0.55); end = (0.75, 0.55)
        default: throw RorkDeviceError.invalidInput("Unsupported swipe direction.")
        }
        try await sendGesture(start: start, end: end, holdMilliseconds: 0)
    }

    public func navigate(_ gesture: PocketNavigationGesture, observedBottomY: Double? = nil) async throws {
        guard allowedBundleID == "com.jackadamslovell.PocketAgent",
              display != nil, mediaSessionID != nil, sink.packetsReceived > mediaPacketBaseline else {
            throw RorkDeviceError.invalidInput("Navigation requires an authenticated Pocket Agent-scoped session.")
        }
        try await requireLegacyRunnerStopped()
        try Task.checkCancellation()
        if gesture.homeButtonPressCount > 0 {
            // One fixed Home press returns Home; a deliberate double press
            // opens App Switcher. This is one requested action, never a retry.
            let channel = try await open("com.apple.coredevice.hid.indigo")
            defer { channel.close() }
            for index in 0..<gesture.homeButtonPressCount {
                try Task.checkCancellation()
                try await channel.send(PocketNativeWire.homeButton(pressed: true))
                do { try await Task.sleep(for: .milliseconds(70)) }
                catch {
                    try? await channel.send(PocketNativeWire.homeButton(pressed: false))
                    throw error
                }
                try await channel.send(PocketNativeWire.homeButton(pressed: false))
                if index + 1 < gesture.homeButtonPressCount {
                    try await Task.sleep(for: .milliseconds(120))
                }
            }
            return
        }
        var start = gesture.start
        if gesture == .appSwitcher {
            guard let observedBottomY, observedBottomY.isFinite, (0.95...0.995).contains(observedBottomY) else {
                throw RorkDeviceError.invalidInput("A fresh, measured bottom indicator is required. No gesture sent.")
            }
            start = (0.5, observedBottomY)
        }
        try await sendGesture(start: start, end: gesture.end, holdMilliseconds: gesture.holdMilliseconds)
    }

    private func sendGesture(start: (Double, Double), end: (Double, Double), holdMilliseconds: Int, initialHoldMilliseconds:Int = 0, settleMotion:Bool = false) async throws {
        // Use the same acknowledged, session-owned transport as native taps.
        // Opening and immediately closing a write-only channel can drop a swipe.
        if touchChannel != nil, touchChannelOpened.duration(to:.now) >= .seconds(45) {
            touchChannel?.close(); touchChannel = nil
        }
        let channel: RemoteXPCConnection
        if let touchChannel { channel = touchChannel }
        else {
            channel = try await open("com.apple.coredevice.hid.universalhidservice")
            do {
                _ = try await hidRequest(channel, payload: ["connectedServices": .dictionary([:])])
            } catch { channel.close(); throw error }
            touchChannel = channel
            touchChannelOpened = .now
        }
        func send(_ x: Double, _ y: Double, contact: Bool) async throws {
            try await channel.send(.dictionary([
                "featureIdentifier": .string("com.apple.coredevice.feature.remote.universalhidservice"),
                "messageType": .string("Request"),
                "payload": .dictionary(["send": .dictionary([
                    "_0": .data(try PocketNativeWire.touch(x: x, y: y, contact: contact, timestamp: DispatchTime.now().uptimeNanoseconds)),
                    "_1": .uint64(257)
                ])])
            ]))
        }
        var point = start
        var releaseAttempted = false
        do {
            try Task.checkCancellation()
            try await send(point.0, point.1, contact: true)
            if initialHoldMilliseconds > 0 { try await Task.sleep(for:.milliseconds(initialHoldMilliseconds)) }
            let steps=settleMotion ? 24 : 12
            for step in 1...steps {
                try await Task.sleep(for: .milliseconds(settleMotion ? 15 : 30))
                let progress = Double(step) / Double(steps)
                let t = settleMotion ? progress*progress*progress*(10+progress*(-15+6*progress)) : progress
                point = (start.0 + (end.0 - start.0) * t, start.1 + (end.1 - start.1) * t)
                try await send(point.0, point.1, contact: true)
            }
            if holdMilliseconds > 0 { try await Task.sleep(for: .milliseconds(holdMilliseconds)) }
            releaseAttempted = true
            try await send(point.0, point.1, contact: false)
            _ = try await hidRequest(channel, payload: ["connectedServices": .dictionary([:])])
        } catch {
            if !releaseAttempted { try? await send(point.0, point.1, contact: false) }
            channel.close(); touchChannel = nil
            throw error // Never replay an uncertain gesture.
        }
    }

    public func stopMedia() async throws {
        touchChannel?.close(); touchChannel = nil
        guard let channel = display else { return }
        display = nil
        let session = mediaSessionID
        mediaSessionID = nil
        channel.close()
        // The public response does not contain the daemon's internal stop ID.
        // Never guess it from SyncStreamToken (which can belong to an audio
        // session), and never stopAll. Close only our XPC channel and verify
        // teardown using the exact client UUID that the start reply echoed.
        guard let session, !stopped else { return }
        for _ in 0..<7 {
            try await Task.sleep(for: .seconds(2))
            let statusChannel = try await open("com.apple.coredevice.displayservice")
            let output: RemoteXPCValue
            do {
                output = try await invoke(statusChannel, feature: "getmediastreamserverstatus", action: "mediastreamstatus", input: [:])
                statusChannel.close()
            } catch { statusChannel.close(); throw error }
            if try Self.mediaSessionIsAbsent(output, id: session) { return }
        }
        throw RorkDeviceError.protocolViolation("Own media channel closed, but stream cleanup is not yet verified. No other sessions were stopped.")
    }

    static func mediaSessionIsAbsent(_ output: RemoteXPCValue, id: Data) throws -> Bool {
        guard let fields = output.dictionaryValue, case .bool(let running) = fields["running"] else {
            throw RorkDeviceError.protocolViolation("Malformed media status; cleanup is not verified.")
        }
        if !running { return true }
        guard case .array(let sessions) = fields["sessions"] else {
            throw RorkDeviceError.protocolViolation("Missing active-session list; cleanup is not verified.")
        }
        for entry in sessions {
            guard case .uuid(let candidate) = entry.dictionaryValue?["connection"]?.dictionaryValue?["options"]?.dictionaryValue?["avcMediaStreamOptionClientSessionID"]?.dictionaryValue?["uuid"] else {
                throw RorkDeviceError.protocolViolation("Unidentified media session; cleanup is not verified.")
            }
            if candidate == id { return false }
        }
        return true
    }

    private func raw(_ name: String) async throws -> PocketNativeOwnedConnection {
        guard !stopped, let port = discovery.directory.services[name] else {
            throw RorkDeviceError.invalidInput("Native service unavailable: \(name)")
        }
        return PocketNativeOwnedConnection(try await network.connect(to: port))
    }

    private func open(_ name: String, pipelined: Bool = false) async throws -> RemoteXPCConnection {
        let connection = try await raw(name)
        let deadline = closeAfter(connection, seconds: 8)
        defer { deadline.cancel() }
        do { return try await RemoteXPCConnection.open(over: connection, pipelinedHandshake: pipelined) }
        catch { connection.close(); throw error }
    }

    private func closeAfter(_ connection: DeviceConnection, seconds: Int) -> Task<Void, Never> {
        let lease = PocketControlProbeLease()
        try? lease.register(connection)
        return Task { try? await Task.sleep(for: .seconds(seconds)); if !Task.isCancelled { lease.close() } }
    }

    private func invoke(_ channel: RemoteXPCConnection, feature: String, action: String, input: [String: RemoteXPCValue]) async throws -> RemoteXPCValue {
        let deadline = Task { try? await Task.sleep(for: .seconds(12)); if !Task.isCancelled { channel.close() } }
        defer { deadline.cancel() }
        try await channel.send(.dictionary([
            "CoreDevice.CoreDeviceDDIProtocolVersion": .int64(2), "CoreDevice.action": .dictionary([:]),
            "CoreDevice.coreDeviceVersion": .dictionary(["components": .array([.uint64(629), .uint64(3)]), "originalComponentsCount": .int64(2), "stringValue": .string("629.3")]),
            "CoreDevice.deviceIdentifier": .string(UUID().uuidString),
            "CoreDevice.featureIdentifier": .string("com.apple.coredevice.feature." + feature),
            "CoreDevice.actionIdentifier": .string("com.apple.coredevice.action." + action),
            "CoreDevice.input": .dictionary(input), "CoreDevice.invocationIdentifier": .string(UUID().uuidString)
        ]), additionalFlags: 0x10000)
        var root: [String: RemoteXPCValue]?
        for _ in 0..<16 {
            let reply = try await channel.receive(on: .reply, acceptingEitherStream: true)
            if reply.value == nil || reply.value == .dictionary([:]) { continue }
            root = reply.value?.dictionaryValue
            break
        }
        guard let root else { throw RorkDeviceError.protocolViolation("Native service returned no dictionary.") }
        if let error = root["CoreDevice.error"] { throw RorkDeviceError.protocolViolation("Native \(feature) failed: \(Self.summary(error))") }
        guard let output = root["CoreDevice.output"] else { throw RorkDeviceError.protocolViolation("Native service returned no output.") }
        return output
    }

    /// Diagnostic metadata only. Omit binary payloads and UUIDs entirely.
    private static func summary(_ value: RemoteXPCValue, depth: Int = 0) -> String {
        guard depth < 7 else { return "…" }
        switch value {
        case .dictionary(let fields): return "{" + fields.keys.sorted().map { $0 + ": " + summary(fields[$0]!, depth: depth + 1) }.joined(separator: ", ") + "}"
        case .array(let values): return "[" + values.prefix(12).map { summary($0, depth: depth + 1) }.joined(separator: ", ") + "]"
        case .data(let data): return "<\(data.count) bytes omitted>"
        case .uuid: return "<session UUID>"
        case .string(let string): return String(string.prefix(180))
        default: return String(describing: value)
        }
    }
}

/// Only wraps this package's userspace sockets, whose documented close/send/
/// receive contract permits concurrent shutdown of an awaiting operation.
private final class PocketNativeOwnedConnection: DeviceConnection, @unchecked Sendable {
    let base: DeviceConnection
    init(_ base: DeviceConnection) { self.base = base }
    func send(_ data: Data) async throws { try await base.send(data) }
    func receive(exactly count: Int) async throws -> Data { try await base.receive(exactly: count) }
    func close() { base.close() }
}
