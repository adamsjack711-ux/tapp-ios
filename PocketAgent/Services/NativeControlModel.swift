import ActivityKit
import BackgroundTasks
import Combine
import Foundation
import RorkDevice
import SwiftUI
import UIKit

@MainActor
final class NativeControlModel: ObservableObject, NativeScreenRevalidatingTapDevice, NativeScreenGestureDevice, HomeNavigationDevice, AppSwitcherDevice {
    static let shared = NativeControlModel()
    @Published private(set) var status = "Native input has not been tested."
    @Published private(set) var details = ""
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var proofCount = 0
    @Published private(set) var preview: Data?
    @Published private(set) var activityStatus = "Native icon not started."
    @Published private(set) var pointerStatus = "Not tested. No pointer device has been created."
    @Published private(set) var pointerExperimentRunning = false
    @Published private(set) var pointerPlanning = false
    @Published private(set) var pointerProposal: PointerTargetProposal?
    @Published private(set) var pointerPlanStatus = "Ask for one of the four targets. The agent proposes; you approve movement."
    @Published private(set) var homeNavigationEnabled = ScreenControlAccessStore().navigationEnabled
    @Published private(set) var navigationPreview: Data?
    @Published private(set) var navigationStatus = ScreenControlAccessStore().navigationEnabled
        ? "Navigation and Settings launch are ready. Your authorization stays on until you switch it off."
        : "Navigation and Settings launch are off by your choice."
    @Published private(set) var pointerFeedback = "No screen or pointer observation yet."
    @Published private(set) var pointerPreview: Data?
    @Published private(set) var pointerSnapshotPosition: CGPoint?
    @Published private(set) var pointerSnapshotTarget: CGPoint?
    private var pointerPosition: CGPoint?
    private var pointerObservedAt = -Double.infinity
    private var pointerEverObserved = false
    private var pointerCaptureAt = -Double.infinity
    private var pointerUIUpdatedAt = -Double.infinity
    private var pointerTargets: [CGPoint] = []
    private var pointerTargetIndex = 0
    private var pointerCaptureCount = 0
    private var pointerSteeringCount = 0
    private var pointerArrivalCount = 0
    private var pointerLastArrival = -Double.infinity
    private var pointerScreenSize = CGSize.zero
    private var pointerStage = "not started"
    private var pointerCancellationReason: String?
    private var pointerPlanner: PointerTargetPlanner?
    private var pointerPlanID: UUID?
    private var pointerApprovedTarget: PointerLabTarget?
    var proofRect = CGRect.zero
    private var engine: PocketNativeEngine?
    private var operation: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private var activity: Activity<NativeControlActivityAttributes>?
    private var sessionDeadline = Date.distantPast
    private let allowance = BackgroundAllowance()
    private var agentBundleID: String?
    private var agentOperationID: UUID?
    private var lastFrame: NativeScreenFrame?
    private var switcherCheckpoint:String?
    private var switcherCheckedAt = Date.distantPast
    private var navigationOperationID: UUID?
    private var cornerBatchID: UUID?
    private var cornerBatchOpened = false
    private var resetCornerFixture = false
    private var cornerBackgroundTask:BGTask?
    private var cornerTaskIdentifier:String?
    var hasContinuedCornerRun:Bool { cornerBackgroundTask != nil }

    var hasActiveNavigationSession: Bool {
        homeNavigationEnabled
    }

    func begin(bundleID: String, operationID: UUID) async throws {
        if cornerBatchID != nil {
            guard bundleID == "com.jackadamslovell.TappClickTarget",
                  connected, engine != nil, Date.now < sessionDeadline else { throw NativeTestError.notConnected }
            agentOperationID = operationID
            return
        }
        guard !busy, !connected else { throw ScreenControlError.busy }
        busy = true
        agentBundleID = bundleID
        agentOperationID = operationID
        status = "Starting one approved native operation…"
        allowance.begin { [weak self] in self?.stop(); LocalControlRoute.shared.stop() }
        do {
            try await LocalControlRoute.shared.startAndWait()
            try Task.checkCancellation()
            let url = URL.applicationSupportDirectory.appendingPathComponent("PocketControl/remote-pairing.plist")
            let connection = try await PocketNativeEngine.connect(host: LocalControlPacket.peerAddress,
                identity: RemotePairingIdentity(contentsOf: url), expectedDevice: "00008150-000A20360212401C", allowedBundleID: bundleID)
            guard agentOperationID == operationID, !Task.isCancelled else {
                connection.abort()
                await connection.close()
                throw CancellationError()
            }
            engine = connection
            try await connection.requireLegacyRunnerStopped()
            connected = true
            sessionDeadline = .now + 90
            startActivity()
            expiry = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(90)); self?.stop(); LocalControlRoute.shared.stop() } catch { }
            }
        } catch { stop(); LocalControlRoute.shared.stop(); throw error }
    }

    /// The click coordinator owns destination verification. Kept independent
    /// of the motion-only/always-visible cursor experiment.
    func runCursorClick(operationID: UUID,
                        ready: @escaping @Sendable () async -> Void,
                        continueWhile: @escaping @Sendable () async -> Bool,
                        nextStep: @escaping @Sendable (Double) async throws -> PocketPointerClickStep,
                        beforeClick: @escaping @Sendable () async throws -> Void) async throws -> String {
        guard !pointerExperimentRunning, !pointerPlanning else { throw ScreenControlError.busy }
        try await begin(bundleID: "com.jackadamslovell.PocketAgent", operationID: operationID)
        do {
            guard let engine else { throw NativeTestError.notConnected }
            try await Task.sleep(for: .seconds(8))
            try Task.checkCancellation()
            guard UIApplication.shared.applicationState == .active else { throw CancellationError() }
            _ = try await engine.startMedia()
            await ready()
            let result = try await engine.movePointerAndClick(continueWhile: continueWhile, nextStep: nextStep, beforeClick: beforeClick)
            try await engine.stopMedia()
            _ = await finishSession(returnToApp: false)
            return result
        } catch {
            if let engine { try? await engine.stopMedia() }
            _ = await finishSession(returnToApp: false)
            throw error
        }
    }

    func openAllowedApp() async throws {
        guard let engine, let agentBundleID else { throw NativeTestError.notConnected }
        if cornerBatchID != nil && cornerBatchOpened { return }
        if cornerBatchID != nil && resetCornerFixture { try await engine.resetClickTestFixture() }
        else { try await engine.launch(bundleID: agentBundleID) }
        // Establish the batch's display session before its first observation.
        // Negotiating it only on the first tap changed the captured rendering
        // between the approved frame and validation, destabilizing OCR.
        if cornerBatchID != nil { _ = try await engine.startMedia() }
        try await Task.sleep(for: .milliseconds(700))
        if cornerBatchID != nil { cornerBatchOpened = true }
    }

    /// A bounded diagnostic against our counter-only fixture. Production AI
    /// operations keep their existing single-operation lifetime.
    func beginCornerBatch(totalClicks:Int,title:String = "Tapp corner check",resetFixture:Bool = false) async throws {
        guard cornerBatchID == nil,cornerTaskIdentifier == nil,!busy,!connected else { throw ScreenControlError.busy }
        guard UIApplication.shared.applicationState == .active else { throw NativeTestError.backgroundUnavailable }
        if #available(iOS 26.0, *) {
            do { try await acquireCornerBackground(totalClicks:totalClicks,title:title) }
            catch { completeCornerBackground(success:false); throw error }
        } else { throw NativeTestError.backgroundUnavailable }
        let id=UUID()
        do { try await begin(bundleID:"com.jackadamslovell.TappClickTarget",operationID:id) }
        catch { completeCornerBackground(success:false); throw error }
        // The system-granted continued task replaces the short UIKit allowance.
        allowance.end()
        cornerBatchID=id; cornerBatchOpened=false; resetCornerFixture=resetFixture
        sessionDeadline = .now + 180
        expiry?.cancel()
        expiry=Task { [weak self] in
            do { try await Task.sleep(for:.seconds(180)); self?.stop(); LocalControlRoute.shared.stop() } catch { }
        }
        traceTappClick("corner-batch-started",extra:["continuedBackgroundGranted":hasContinuedCornerRun])
    }

    @available(iOS 26.0, *)
    private func acquireCornerBackground(totalClicks:Int,title:String,subtitle:String? = nil) async throws {
        let identifier="com.jackadamslovell.PocketAgent.tappcheck.\(UUID().uuidString)"
        cornerTaskIdentifier=identifier
        let registered=BGTaskScheduler.shared.register(forTaskWithIdentifier:identifier,using:.main) { [weak self] task in
            Task { @MainActor in
                guard let self,self.cornerTaskIdentifier==identifier,
                      let continued=task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success:false); return
                }
                self.cornerBackgroundTask=continued
                continued.progress.totalUnitCount=Int64(totalClicks)
                continued.progress.completedUnitCount=0
                continued.expirationHandler={ [weak self] in
                    Task { @MainActor in
                        guard let self,self.cornerTaskIdentifier==identifier else { return }
                        self.traceTappClick("corner-background-expired")
                        await TappCursorModel.shared.cancelCornerRun()
                        self.stop(); LocalControlRoute.shared.stop()
                    }
                }
            }
        }
        guard registered else { throw NativeTestError.backgroundUnavailable }
        let request=BGContinuedProcessingTaskRequest(identifier:identifier,title:title,
            subtitle:subtitle ?? "Verifying \(totalClicks) click\(totalClicks==1 ? "" : "s")")
        request.strategy = .fail
        if #available(iOS 27.0, *) { try await BGTaskScheduler.shared.submitTaskRequest(request) }
        else { try BGTaskScheduler.shared.submit(request) }
        let deadline=Date.now.addingTimeInterval(5)
        while cornerBackgroundTask == nil && Date.now<deadline {
            try Task.checkCancellation()
            try await Task.sleep(for:.milliseconds(20))
        }
        guard cornerBackgroundTask != nil else { throw NativeTestError.backgroundUnavailable }
    }

    func updateCornerProgress(completed:Int,total:Int) {
        if #available(iOS 26.0, *),let task=cornerBackgroundTask as? BGContinuedProcessingTask {
            task.progress.completedUnitCount=Int64(completed)
            task.updateTitle("Tapp corner check",subtitle:"\(completed) of \(total) clicks verified")
        }
    }

    func completeCornerBackground(success:Bool) {
        let identifier=cornerTaskIdentifier
        cornerTaskIdentifier=nil
        let task=cornerBackgroundTask
        cornerBackgroundTask=nil
        if let task { task.setTaskCompleted(success:success) }
        else if let identifier { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:identifier) }
    }

    func endCornerBatch(success:Bool = false) async throws {
        guard cornerBatchID != nil else { throw NativeTestError.notConnected }
        var cleanupError:Error?
        if let engine {
            do { try await engine.stopMedia(); traceTappClick("corner-batch-media-cleanup-verified") }
            catch { cleanupError=error }
        }
        cornerBatchID=nil; cornerBatchOpened=false
        _ = await finishSession(returnToApp:false,preservingCornerBackground:true)
        if let cleanupError { throw cleanupError }
    }

    func captureFrame() async throws -> NativeScreenFrame {
        guard let engine, agentBundleID != nil else { throw NativeTestError.notConnected }
        status = "Reading the approved screen locally…"
        let frame = try await cleanCursorFrame(engine)
        lastFrame = frame
        return frame
    }

    func prepareTapObservation(_ frame:NativeScreenFrame) async throws {
        guard engine != nil, agentBundleID != nil else { throw NativeTestError.notConnected }
        lastFrame=frame
    }

    private func cleanCursorFrame(_ engine:PocketNativeEngine) async throws -> NativeScreenFrame {
        // Tapp's tip now rests at the text's bottom-centre interior edge, leaving
        // the glyphs readable. Keep it visible throughout capture and OCR.
        // If any text is obscured, the unchanged strict validation stops input.
        let started=Date.now
        let data=try await engine.screenshot()
        let captured=Date.now
        try Task.checkCancellation()
        let languages = agentBundleID == "com.jackadamslovell.TappClickTarget" ? ["en-US"] : nil
        let frame=try await ImageOCRService.nativeFrame(in:data,recognitionLanguages:languages)
        traceTappClick("frame-timing",extra:["captureMS":captured.timeIntervalSince(started)*1000,
            "ocrMS":Date.now.timeIntervalSince(captured)*1000])
        return frame
    }

    private func traceTappClick(_ stage:String,extra:[String:Any] = [:]) {
        guard agentBundleID == "com.jackadamslovell.TappClickTarget" || navigationOperationID != nil else { return }
        var record:[String:Any] = ["stage":stage,"operation":agentOperationID?.uuidString ?? "", "time":Date.now.timeIntervalSince1970]
        record.merge(extra) { _,new in new }
        guard let data=try? JSONSerialization.data(withJSONObject:record),
              let line=String(data:data,encoding:.utf8) else { return }
        let url=URL.documentsDirectory.appendingPathComponent("tapp-input-trace.jsonl")
        let previous=(try? String(contentsOf:url,encoding:.utf8)) ?? ""
        try? (previous+line+"\n").write(to:url,atomically:true,encoding:.utf8)
    }

    func tap(_ target: NativeScreenText) async throws {
        guard let engine, agentBundleID != nil, target.valid else { throw NativeTestError.notConnected }
        status = "Sending one approved native tap…"
        traceTappClick("preparing-media")
        _ = try await engine.startMedia()
        do {
            try Task.checkCancellation()
            // Re-observe after media negotiation, immediately before input.
            var latest = try await cleanCursorFrame(engine)
            guard !latest.containsPermissionPrompt else { throw ScreenControlError.blockedByAlert }
            // OCR can vary for an unchanged frame. One extra observation may
            // recover a transient recognition error, but must still match the
            // original approved screen exactly. Never resend input here.
            if let lastFrame, !latest.sameContent(as:lastFrame) {
                traceTappClick("rechecking-screen-before-input")
                latest = try await cleanCursorFrame(engine)
                guard !latest.containsPermissionPrompt else { throw ScreenControlError.blockedByAlert }
            }
            if agentBundleID == "com.jackadamslovell.TappClickTarget",let lastFrame {
                let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
                try? encoder.encode(lastFrame.items).write(to:URL.documentsDirectory.appendingPathComponent("tapp-validation-before.json"),options:.atomic)
                try? encoder.encode(latest.items).write(to:URL.documentsDirectory.appendingPathComponent("tapp-validation-after.json"),options:.atomic)
                try? latest.image.write(to:URL.documentsDirectory.appendingPathComponent("tapp-validation-after.png"),options:.atomic)
            }
            guard let lastFrame else { throw ScreenControlError.staleScreen }
            let match=try latest.revalidatedTapTarget(target,matching:lastFrame)
            try Task.checkCancellation()
            try await TappCursorModel.shared.ensurePresented()
            let anchor = TappCursorModel.shared.enabled ? match.cursorAnchor : (x:match.x+match.width/2,y:match.y+match.height/2)
            traceTappClick("validated-before-touch",extra:["x":anchor.x,"y":anchor.y,"label":match.label])
            TappCursorModel.shared.pressFeedback()
            do {
                _ = try await engine.tap(x:anchor.x,y:anchor.y)
                TappCursorModel.shared.releaseFeedback()
            } catch { TappCursorModel.shared.cancelFeedback(); throw error }
            traceTappClick("touch-down-and-up-sent")
            if cornerBatchID == nil {
                try await engine.stopMedia()
                traceTappClick("media-cleanup-verified")
            }
            try await Task.sleep(for: .milliseconds(300))
        } catch { traceTappClick("failed: \(error.localizedDescription)"); try? await engine.stopMedia(); throw error }
    }

    func swipe(direction: String) async throws {
        guard let engine, agentBundleID != nil else { throw NativeTestError.notConnected }
        status = "Sending one approved native swipe…"
        _ = try await engine.startMedia()
        do {
            try Task.checkCancellation()
            let latest = try await cleanCursorFrame(engine)
            guard !latest.containsPermissionPrompt else { throw ScreenControlError.blockedByAlert }
            guard let lastFrame, latest.sameContent(as: lastFrame) else { throw ScreenControlError.staleScreen }
            try Task.checkCancellation()
            try await engine.swipe(direction: direction)
            try await engine.stopMedia()
            try await Task.sleep(for: .milliseconds(400))
        } catch { try? await engine.stopMedia(); throw error }
    }

    func hold(_ target:NativeScreenText) async throws {
        try await performHeldGesture(target,to:nil)
    }

    func drag(_ target:NativeScreenText,to destination:NativeScreenText) async throws {
        try await performHeldGesture(target,to:destination)
    }

    private func performHeldGesture(_ target:NativeScreenText,to destination:NativeScreenText?) async throws {
        guard let engine,agentBundleID != nil,target.valid,destination?.valid != false else { throw ScreenControlError.invalidArguments }
        _ = try await engine.startMedia()
        let cursor=TappCursorModel.shared
        do {
            let latest=try await cleanCursorFrame(engine)
            guard !latest.containsPermissionPrompt else { throw ScreenControlError.blockedByAlert }
            guard let lastFrame else { throw ScreenControlError.staleScreen }
            let start=try latest.revalidatedTapTarget(target,matching:lastFrame)
            let end=try destination.map { try latest.revalidatedTapTarget($0,matching:lastFrame) }
            try Task.checkCancellation()
            try await cursor.ensurePresented()
            let origin=start.cursorAnchor
            cursor.pressFeedback()
            defer { cursor.cancelFeedback() }
            if let end {
                // Input and visual motion share the same endpoints. The native
                // primitive owns its hold/release and never retries input.
                async let gesture:Void=engine.drag(fromX:origin.x,fromY:origin.y,toX:end.cursorAnchor.x,toY:end.cursorAnchor.y)
                try await Task.sleep(for:.milliseconds(500))
                if cursor.enabled { try await cursor.move(to:end) }
                try await gesture
            } else { _ = try await engine.hold(x:origin.x,y:origin.y) }
            cursor.releaseFeedback()
            try await engine.stopMedia()
            try await Task.sleep(for:.milliseconds(300))
        } catch { cursor.cancelFeedback();try? await engine.stopMedia();throw error }
    }

    func finish() async -> String? {
        if cornerBatchID != nil { return nil }
        return await finishSession(returnToApp: true)
    }

    private func finishSession(returnToApp: Bool,preservingCornerBackground:Bool = false) async -> String? {
        guard agentBundleID != nil else { return nil }
        var warning: String?
        let finishing = engine
        if returnToApp, let finishing, !Task.isCancelled {
            do { try await finishing.launch(bundleID: "com.jackadamslovell.PocketAgent") }
            catch { warning = "Reopen hitapp manually. No action was retried." }
        } else if returnToApp { warning = "Reopen hitapp manually; the operation was stopped." }
        if engine === finishing {
            endNativeSession(cancelPendingWork:false,preservingCornerBackground:preservingCornerBackground); LocalControlRoute.shared.stop()
            status = "Native operation finished. The connection is closed; your saved access is ready for the next command."
            saveDiagnostic()
        }
        return warning
    }

    func setHomeNavigationEnabled(_ enabled: Bool) {
        guard !enabled || (!busy && !connected && !pointerPlanning && !pointerExperimentRunning) else { return }
        ScreenControlAccessStore().navigationEnabled = enabled
        homeNavigationEnabled = enabled
        navigationStatus = enabled ? "Navigation and Settings launch are ready without repeat approval. This remains enabled after relaunch until you switch it off." : "Navigation and Settings launch are off by your choice."
        if !enabled, let navigationOperationID, navigationOperationID == agentOperationID {
            stop(); LocalControlRoute.shared.stop()
        }
    }

    func navigate(_ action: HomeNavigationAction, operationID: UUID) async throws -> String {
        // Every App Switcher entry point uses the navigation presentation and
        // measured phone-space compensation, including AI phone_navigate.
        if action == .appSwitcher { return try await controlSwitcher(.show,operationID:operationID) }
        guard hasActiveNavigationSession else { throw ScreenControlError.disabled }
        guard !busy, !connected, !pointerPlanning, !pointerExperimentRunning,
              UIApplication.shared.applicationState == .active else { throw ScreenControlError.busy }
        navigationOperationID = operationID
        defer {
            if navigationOperationID == operationID { navigationOperationID = nil }
        }
        navigationPreview = nil
        navigationStatus = "Starting approved navigation: \(action.title)."
        var inputMayHaveBeenSent = false
        do {
            try await begin(bundleID: action.launchBundleID ?? "com.jackadamslovell.PocketAgent", operationID: operationID)
            guard let engine else { throw NativeTestError.notConnected }
            // App launch needs no HID/media session. Navigation input does.
            if action.launchBundleID == nil { _ = try await engine.startMedia() }
            // The command or approval was entered in this app. Never begin on a different app,
            // lock screen or a detected system permission prompt.
            let before = try await ImageOCRService.nativeFrame(in: engine.screenshot())
            try Task.checkCancellation()
            guard UIApplication.shared.applicationState == .active, homeNavigationEnabled else { throw ScreenControlError.disabled }
            guard !before.containsPermissionPrompt else { throw ScreenControlError.blockedByAlert }
            if let target = action.launchBundleID {
                navigationStatus = "Fresh screen checked. Opening Settings through the native app service; no taps or setting changes."
                details = navigationStatus
                try Task.checkCancellation()
                inputMayHaveBeenSent = true
                try await engine.launch(bundleID: target)
            } else {
                let observed = ImageOCRService.homeIndicator(in: before.image)
                let activeWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                    .filter { $0.activationState == .foregroundActive }.flatMap(\.windows).first(where: \.isKeyWindow)
                let measured = activeWindow.flatMap {
                    ImageOCRService.measuredBottom(in: before.image, windowSize: $0.bounds.size, bottomInset: $0.safeAreaInsets.bottom)
                }
                let bottomY = observed?.centerY ?? measured
                if action.requiresBottomEdgeCoordinates {
                    guard let bottomY else { throw NativeTestError.bottomNotRecognized }
                    navigationStatus = observed != nil ? "Bottom indicator located in the fresh capture." : "Indicator hidden; using this app's measured display bounds and bottom safe area, matched to the fresh capture."
                    details = navigationStatus + " Normalized bottom: \(bottomY)."
                } else {
                    navigationStatus = action == .appSwitcher
                        ? "Fresh screen checked. Sending the fixed double Home event for App Switcher."
                        : "Fresh screen checked. Sending the fixed Home button event; no bottom-edge coordinates required."
                    details = navigationStatus
                }
                try Task.checkCancellation()
                inputMayHaveBeenSent = true
                try await engine.navigate(action == .appSwitcher ? .appSwitcher : .home, observedBottomY: bottomY)
            }
            try await Task.sleep(for: .milliseconds(900))
            // Preserve a local failure capture, and don't describe dispatch as a
            // successful transition when this app never left the foreground.
            navigationPreview = try await engine.screenshot()
            guard action == .appSwitcher ? UIApplication.shared.applicationState == .inactive : UIApplication.shared.applicationState == .background else { throw NativeTestError.homeNotReached }
            if action == .pageLeft || action == .pageRight {
                let intermediate = try await ImageOCRService.nativeFrame(in: engine.screenshot())
                try Task.checkCancellation()
                guard !intermediate.containsPermissionPrompt else { throw ScreenControlError.blockedByAlert }
                guard UIApplication.shared.applicationState == .background else { throw NativeTestError.homeNotReached }
                // Best-effort English Home-layout check, not proof of app identity.
                // Unfamiliar/localized layouts stop rather than swiping blindly.
                guard intermediate.items.contains(where: { $0.label == "Search" && $0.y > 0.65 && $0.y < 0.9 }) else {
                    throw NativeTestError.homeNotReached
                }
                try await engine.navigate(action == .pageLeft ? .pageLeft : .pageRight)
                try await Task.sleep(for: .milliseconds(700))
            }
            navigationPreview = try await engine.screenshot()
            try await engine.stopMedia()
            _ = await finishSession(returnToApp: false)
            navigationStatus = "\(action.title): native operation dispatched and hitapp left the foreground; local result captured. Visually verify the destination. No setting changes, app closing or automatic retry."
            saveDiagnostic()
            return navigationStatus + " Image and screen text were not sent to the model. Do not claim visual success. Reopen hitapp manually for the preview."
        } catch {
            if agentOperationID == operationID {
                if let engine { try? await engine.stopMedia() }
                _ = await finishSession(returnToApp: false)
            }
            let outcome = inputMayHaveBeenSent
                ? "Input was attempted and may already have completed. Inspect the phone; no retry."
                : "No navigation input was sent. No retry."
            navigationStatus = "Navigation stopped: \(error.localizedDescription) \(outcome)"
            saveDiagnostic()
            throw error
        }
    }

    var hasSwitcherContext:Bool { switcherCheckpoint != nil && Date.now.timeIntervalSince(switcherCheckedAt)<180 }

    func controlSwitcher(_ request:AppSwitcherRequest,operationID:UUID) async throws -> String {
        try await controlSwitcherPlan([request],operationID:operationID)
    }

    func controlSwitcherPlan(_ requests:[AppSwitcherRequest],operationID:UUID) async throws -> String {
        guard homeNavigationEnabled else { throw ScreenControlError.disabled }
        guard !requests.isEmpty,requests.count<=8,!busy,!connected,cornerTaskIdentifier == nil,
              UIApplication.shared.applicationState == .active else { throw ScreenControlError.busy }
        navigationOperationID=operationID
        defer { if navigationOperationID == operationID { navigationOperationID=nil } }
        // Save full-display geometry while our window is active. A different
        // app may hide its Home indicator; its content bounds are not the
        // phone's navigation edge. Revalidate against each fresh capture.
        let navigationWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }.flatMap(\.windows).first(where: \.isKeyWindow)
        let navigationWindowSize = navigationWindow?.bounds.size
        let navigationBottomInset = navigationWindow?.safeAreaInsets.bottom
        let run=UUID().uuidString, began=Date.now
        let folder=URL.documentsDirectory.appendingPathComponent("tapp-switcher-\(run)")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        var captures=0, completed=[String](), stage="connecting", inputAttempted=false
        var wasSwitcher=false
        var switcherCursorCalibrated=false
        var entryFromHitapp=false,entryCompensationRestored=false
        var entryPlacement="unmeasured"
        var switcherHostState = UIApplication.State.inactive
        var mostRecentlyOpened:String?
        func report(_ error:String = "",verified:Bool = false) {
            let value:[String:Any]=["runID":run,"started":began.timeIntervalSince1970,"time":Date.now.timeIntervalSince1970,
                "stage":stage,"requested":requests.map { $0.action+($0.appName.map { ":"+$0 } ?? "") },
                "completed":completed,"captures":captures,"verified":verified,"error":error,"evidenceDirectory":folder.lastPathComponent,
                "taskCancelled":Task.isCancelled,"operationMatches":agentOperationID==operationID,
                "navigationEnabled":homeNavigationEnabled,"routeConnected":LocalControlRoute.shared.connected,
                "continuedTaskGranted":cornerBackgroundTask != nil,"entryPlacement":entryPlacement]
            if let data=try? JSONSerialization.data(withJSONObject:value,options:.prettyPrinted) {
                try? data.write(to:URL.documentsDirectory.appendingPathComponent("tapp-switcher-report.json"),options:.atomic)
            }
        }
        report()
        do {
            guard #available(iOS 26.0, *) else { throw NativeTestError.backgroundUnavailable }
            try await acquireCornerBackground(totalClicks:requests.count,title:"Tapp navigation",subtitle:"Checking screens between steps")
            // A route left by a previous app process may be close to its
            // two-minute expiry. Start a fresh bounded lease for this plan.
            try await LocalControlRoute.shared.restartAndWait()
            try await begin(bundleID:"com.jackadamslovell.PocketAgent",operationID:operationID)
            allowance.end()
            guard let engine else { throw NativeTestError.notConnected }
            let cursor=TappCursorModel.shared
            cursor.start()
            for _ in 0..<300 {
                if cursor.connected { break }
                try await Task.sleep(for:.milliseconds(100))
            }
            guard cursor.connected else { throw NativeTestError.notConnected }
            let presentation = cursor.beginNavigationPresentation()
            defer { cursor.endNavigationPresentation(presentation) }
            try await cursor.move(x:0.5,y:0.90)
            _ = try await engine.startMedia()
            let installedApps = try await engine.installedSwitcherApps()
            func capture(_ label:String) async throws -> NativeScreenFrame {
                try Task.checkCancellation()
                guard homeNavigationEnabled,agentOperationID==operationID,Date.now.timeIntervalSince(began)<80 else { throw CancellationError() }
                let frame=try await ImageOCRService.nativeFrame(in:engine.screenshot())
                guard !frame.containsPermissionPrompt else { throw ScreenControlError.blockedByAlert }
                captures+=1
                try frame.image.write(to:folder.appendingPathComponent("\(captures)-\(label).png"),options:.atomic)
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--tapp-coordinate-probe") {
                    let geometry=try JSONSerialization.data(withJSONObject:cursor.navigationCoordinateProbe(),options:.prettyPrinted)
                    try geometry.write(to:folder.appendingPathComponent("\(captures)-\(label)-coordinates.json"),options:.atomic)
                }
                #endif
                try JSONEncoder().encode(frame.items).write(to:folder.appendingPathComponent("\(captures)-\(label).json"),options:.atomic)
                try frame.text.write(to:folder.appendingPathComponent("\(captures)-\(label).txt"),atomically:true,encoding:.utf8)
                navigationPreview=frame.image
                report()
                return frame
            }
            func header(_ frame:NativeScreenFrame) -> String? {
                frame.items.filter { item in item.y>=0.10 && item.y<0.17 && item.width<0.7 && (0.2...0.8).contains(item.x+item.width/2) && installedApps.contains { $0.displayName.caseInsensitiveCompare(item.label) == .orderedSame } }
                    .min(by:{ abs($0.x+$0.width/2-0.5)<abs($1.x+$1.width/2-0.5) })?.label
            }
            func calibrateSwitcherCursor() async throws -> NativeScreenFrame {
                cursor.resetNavigationCompensation()
                try await cursor.move(x:0.06,y:0.12)
                try await Task.sleep(for:.milliseconds(400))
                let firstFrame=try await capture("calibration-first")
                guard let first=await ImageOCRService.navigationCursorAnchor(in:firstFrame.image) else { throw ScreenControlError.staleScreen }
                try await cursor.move(x:0.18,y:0.84)
                try await Task.sleep(for:.milliseconds(400))
                let secondFrame=try await capture("calibration-second")
                guard let second=await ImageOCRService.navigationCursorAnchor(in:secondFrame.image) else { throw ScreenControlError.staleScreen }
                try cursor.calibrateNavigation(first:first,second:second)
                try await cursor.moveToNavigationRestingPoint()
                let corrected=try await capture("calibrated-bottom-center")
                guard let observed=await ImageOCRService.navigationCursorAnchor(in:corrected.image),
                      abs(observed.x-0.5)<0.02,abs(observed.y-TappCursorModel.navigationRestingY)<0.02 else { throw ScreenControlError.staleScreen }
                if entryFromHitapp { cursor.rememberNavigationEntryCompensation() }
                switcherCursorCalibrated=true
                return corrected
            }
            func drag(_ direction:String,x:Double=0.5,expectedCardName:String?=nil) async throws -> NativeScreenFrame {
                guard UIApplication.shared.applicationState == switcherHostState else { throw NativeTestError.homeNotReached }
                try Task.checkCancellation()
                try await cursor.move(x:0.5,y:0.90)
                try await Task.sleep(for:.milliseconds(250))
                let positioned = try await capture(direction == "up" ? "before-close-hold" : "before-swipe-hold")
                guard header(positioned) != nil else { throw ScreenControlError.staleScreen }
                if direction == "up" {
                    guard let expectedCardName else { throw ScreenControlError.invalidArguments }
                    let target = try AppSwitcherRequest.card(named:expectedCardName,in:positioned)
                    guard abs(target.x+target.width/2-x)<0.02 else { throw ScreenControlError.staleScreen }
                }
                guard UIApplication.shared.applicationState == switcherHostState else { throw NativeTestError.homeNotReached }
                // Stage opposite the card's travel before measuring its new
                // offset. Visibility during the transition is not guaranteed
                // by this requested-coordinate margin alone.
                let endX = direction == "left" ? 0.90 : direction == "right" ? 0.08 : 0.5
                let endY = direction == "up" ? 0.80 : 0.90
                try await cursor.move(x:endX,y:endY)
                cursor.pressFeedback()
                defer { cursor.cancelFeedback() }
                inputAttempted=true
                try await engine.dragSwitcherCard(x:x,direction:direction)
                cursor.releaseFeedback()
                try await Task.sleep(for:.milliseconds(700))
                guard UIApplication.shared.applicationState == switcherHostState else { throw NativeTestError.homeNotReached }
                let shifted=try await capture("after-\(direction)-before-correction")
                guard let observed=await ImageOCRService.navigationCursorAnchor(in:shifted.image) else {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--test-switcher-motion-chat"),direction != "up" {
                        // Distinguish a displaced path from a hidden host. Only
                        // the cursor path changes; no phone gesture is replayed.
                        for probe in 1...4 {
                            cursor.probeNavigationHorizontalOffset(direction == "right" ? -0.4 : 0.4)
                            try await cursor.move(x:0.5,y:0.9)
                            let sampled=try await capture("offset-probe-\(probe)-\(direction)")
                            if let located=await ImageOCRService.navigationCursorAnchor(in:sampled.image) {
                                try cursor.correctNavigationPosition(observed:located,requested:CGPoint(x:0.5,y:0.9))
                                try await cursor.move(x:0.5,y:0.9)
                                let centered=try await capture("offset-probe-recentered-\(direction)")
                                guard let actual=await ImageOCRService.navigationCursorAnchor(in:centered.image),
                                      abs(actual.x-0.5)<0.02,abs(actual.y-0.9)<0.02 else { throw ScreenControlError.staleScreen }
                                return centered
                            }
                        }
                    }
                    #endif
                    // An offscreen host card can stop supplying its card
                    // transform. Reacquire only the renderer in display space;
                    // never resend the phone gesture.
                    cursor.resetNavigationCompensation()
                    try await cursor.move(x:0.5,y:0.9)
                    let recovered=try await capture("after-\(direction)-display-reacquired")
                    guard let actual=await ImageOCRService.navigationCursorAnchor(in:recovered.image),
                          abs(actual.x-0.5)<0.02,abs(actual.y-0.9)<0.02 else { throw ScreenControlError.staleScreen }
                    return recovered
                }
                try cursor.correctNavigationPosition(observed:observed,requested:CGPoint(x:endX,y:endY))
                try await cursor.move(x:0.5,y:0.90)
                let corrected=try await capture("after-\(direction)")
                guard let final=await ImageOCRService.navigationCursorAnchor(in:corrected.image),
                      abs(final.x-0.5)<0.02,abs(final.y-0.9)<0.02 else { throw ScreenControlError.staleScreen }
                return corrected
            }
            func locate(_ name:String,in initial:NativeScreenFrame) async throws -> (NativeScreenText,NativeScreenFrame) {
                var frame=initial
                for attempt in 0..<7 {
                    if let target=try? AppSwitcherRequest.card(named:name,in:frame) { return (target,frame) }
                    guard attempt<6 else { break }
                    // Current app is at the newest end; older cards lie left.
                    // If the requested title is on the right, bring it inward.
                    let right=frame.items.contains { $0.label.caseInsensitiveCompare(name) == .orderedSame && $0.y<0.23 && $0.x+$0.width/2>0.80 }
                    let after=try await drag(right ? "left" : "right")
                    guard !after.sameContent(as:frame) else { throw ScreenControlError.ambiguousElement }
                    frame=after
                }
                throw ScreenControlError.ambiguousElement
            }
            _ = try await capture("initial")
            for (index,request) in requests.enumerated() {
                stage="step-\(index+1)-\(request.action)";report()
                let app: PocketNativeEngine.SwitcherAppIdentity?
                if let name=request.appName {
                    let matches = installedApps.filter { $0.displayName.caseInsensitiveCompare(name) == .orderedSame && $0.bundleIdentifier != "com.jackadamslovell.PocketAgent" }
                    guard matches.count == 1 else { throw ScreenControlError.ambiguousElement }
                    app=matches[0]
                } else { app=nil }
                if !wasSwitcher {
                    switcherCursorCalibrated=false
                    entryCompensationRestored=false
                    entryFromHitapp=UIApplication.shared.applicationState == .active
                    cursor.resetNavigationCompensation()
                    let edgeFrame = try await capture("before-bottom-navigation")
                    let observedBottom = ImageOCRService.homeIndicator(in:edgeFrame.image)?.centerY
                    let measuredBottom:Double?
                    if let size=navigationWindowSize,let inset=navigationBottomInset {
                        measuredBottom=ImageOCRService.measuredBottom(in:edgeFrame.image,windowSize:size,bottomInset:inset)
                    } else { measuredBottom=nil }
                    try await cursor.moveToHomeEdge()
                    try await Task.sleep(for:.milliseconds(250))
                    if UIApplication.shared.applicationState == .background {
                        guard let bottom=observedBottom ?? measuredBottom else { throw NativeTestError.bottomNotRecognized }
                        navigationStatus="Moving from the phone's bottom center into App Switcher."
                        cursor.pressFeedback()
                        defer { cursor.cancelFeedback() }
                        inputAttempted=true
                        try await engine.openSwitcherFromBottom(observedBottomY:bottom)
                        cursor.releaseFeedback()
                    } else {
                        inputAttempted=true
                        try await engine.navigate(.appSwitcher)
                    }
                    if entryFromHitapp { entryCompensationRestored=cursor.placeAtNavigationBottomImmediately() }
                    entryPlacement=entryCompensationRestored ? "cached-immediate-awaiting-visual-check" : "measuring-first-entry"
                    report()
                    try await Task.sleep(for:.milliseconds(900))
                    if !entryCompensationRestored { try await cursor.moveToNavigationRestingPoint() }
                    let state = UIApplication.shared.applicationState
                    guard state != .active else { throw NativeTestError.homeNotReached }
                    switcherHostState = state
                    let bannerFrame = try await engine.screenshot()
                    if try await ImageOCRService.hasNavigationBanner(in:bannerFrame) {
                        try await engine.collapseNavigationBanner()
                        try await Task.sleep(for:.milliseconds(600))
                    }
                    wasSwitcher=true
                }
                let latestBanner = try await engine.screenshot()
                if try await ImageOCRService.hasNavigationBanner(in:latestBanner) {
                    try await engine.collapseNavigationBanner()
                    try await Task.sleep(for:.milliseconds(400))
                }
                var before=try await capture("before-step-\(index+1)")
                guard header(before) != nil else { throw NativeTestError.homeNotReached }
                if entryCompensationRestored,!switcherCursorCalibrated,
                   let observed=await ImageOCRService.navigationCursorAnchor(in:before.image),
                   abs(observed.x-0.5)<0.02,abs(observed.y-TappCursorModel.navigationRestingY)<0.02 {
                    switcherCursorCalibrated=true
                    entryPlacement="cached-immediate-visually-verified"
                }
                if !switcherCursorCalibrated { before=try await calibrateSwitcherCursor() }
                if requests.count==1,request == .browseLeft || request == .browseRight,
                   hasSwitcherContext,let checkpoint=switcherCheckpoint {
                    (_,before)=try await locate(checkpoint,in:before)
                }
                switch request {
                case .show:
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--test-switcher-corners-chat") {
                        var positions=[[String:Any]]()
                        for (name,x,y) in [("top-left",0.06,0.08),("top-right",0.92,0.08),("bottom-right",0.92,0.94),("bottom-left",0.06,0.94)] {
                            try await cursor.moveToNavigationCorner(x:x,y:y)
                            try await Task.sleep(for:.milliseconds(900))
                            before=try await capture("corner-\(name)")
                            let observed=await ImageOCRService.navigationCursorAnchor(in:before.image)
                            let arrived=observed.map { abs($0.x-x)<0.02 && abs($0.y-y)<0.02 } ?? false
                            positions.append(["corner":name,"requestedX":x,"requestedY":y,"movementAcknowledged":true,
                                "observedX":observed?.x ?? -1,"observedY":observed?.y ?? -1,"visuallyArrived":arrived])
                            let result:[String:Any]=["runID":run,"corners":positions,"visualVerified":positions.count==4 && positions.allSatisfy { $0["visuallyArrived"] as? Bool == true },
                                "inputClicks":0,"evidenceDirectory":folder.lastPathComponent]
                            try JSONSerialization.data(withJSONObject:result,options:.prettyPrinted).write(
                                to:URL.documentsDirectory.appendingPathComponent("tapp-navigation-corners-report.json"),options:.atomic)
                            guard arrived else { throw ScreenControlError.staleScreen }
                        }
                        try await cursor.moveToHomeEdge()
                    }
                    #endif
                case .browseLeft,.browseRight:
                    let after=try await drag(request == .browseLeft ? "left" : "right")
                    guard !after.sameContent(as:before) else { throw ScreenControlError.staleScreen }
                    before=after
                case .close,.open:
                    guard let app else { throw ScreenControlError.invalidArguments }
                    if mostRecentlyOpened?.caseInsensitiveCompare(app.displayName) == .orderedSame,
                       (try? AppSwitcherRequest.card(named:app.displayName,in:before)) == nil {
                        // iOS initially centres the previous app. The app just
                        // reopened is the newest card, to its right.
                        before=try await drag("left")
                    }
                    let (target,located)=try await locate(app.displayName,in:before)
                    let fresh=try await capture("revalidate-card")
                    let current=try AppSwitcherRequest.card(named:app.displayName,in:fresh)
                    guard current.hasSameBounds(as:target),!located.containsPermissionPrompt,
                          UIApplication.shared.applicationState == switcherHostState else { throw ScreenControlError.staleScreen }
                    let x=current.x+current.width/2
                    if case .close = request {
                        let wasRunning=try await engine.switcherAppIsRunning(app)
                        let after=try await drag("up",x:x,expectedCardName:app.displayName)
                        guard !after.items.contains(where: { $0.label.caseInsensitiveCompare(app.displayName) == .orderedSame && $0.y<0.23 }) else { throw ScreenControlError.staleScreen }
                        if wasRunning {
                            guard try await !engine.switcherAppIsRunning(app) else { throw ScreenControlError.staleScreen }
                        }
                        before=after
                    } else {
                        try await cursor.move(x:x,y:0.72)
                        try await Task.sleep(for:.milliseconds(250))
                        let selectionFrame = try await capture("before-open-hold")
                        let selection = try AppSwitcherRequest.card(named:app.displayName,in:selectionFrame)
                        guard selection.hasSameBounds(as:current),UIApplication.shared.applicationState == switcherHostState else { throw ScreenControlError.staleScreen }
                        cursor.pressFeedback()
                        inputAttempted=true
                        _ = try await engine.selectSwitcherCard(x:x)
                        cursor.resetNavigationCompensation()
                        cursor.releaseFeedback()
                        try await Task.sleep(for:.milliseconds(800))
                        let after=try await capture("after-open")
                        let targetRunning = try await engine.switcherAppIsRunning(app)
                        guard UIApplication.shared.applicationState != .active,!after.sameContent(as:fresh),
                              targetRunning, (try? AppSwitcherRequest.card(named:app.displayName,in:after)) == nil else {
                            throw RorkDeviceError.invalidInput("Open not verified: host state \(UIApplication.shared.applicationState.rawValue), target running \(targetRunning). Inspect the last screenshot before continuing.")
                        }
                        before=after; wasSwitcher=false; mostRecentlyOpened=app.displayName
                    }
                }
                switcherCheckpoint=wasSwitcher ? header(before) : nil
                switcherCheckedAt = .now
                completed.append(request.action+(app.map { ":"+$0.displayName } ?? ""))
                if let task=cornerBackgroundTask as? BGContinuedProcessingTask {
                    task.progress.completedUnitCount=Int64(index+1)
                    // Updating the title expands an Island banner over card headers.
                    // Progress remains visible without obscuring local OCR.
                }
                report()
            }
            stage="cleanup";report()
            try await engine.stopMedia()
            _ = await finishSession(returnToApp:false,preservingCornerBackground:true)
            stage="complete";report(verified:true)
            completeCornerBackground(success:true)
            navigationStatus="Tapp completed \(completed.count) navigation step\(completed.count==1 ? "" : "s"), with \(captures) local screen checks. \(completed.joined(separator:", "))."
            saveDiagnostic()
            return navigationStatus
        } catch {
            report(error.localizedDescription)
            if let engine { try? await engine.stopMedia() }
            _ = await finishSession(returnToApp:false,preservingCornerBackground:true)
            completeCornerBackground(success:false)
            navigationStatus="Tapp stopped at \(stage): \(error.localizedDescription) \(inputAttempted ? "An action may already have completed." : "No input was sent.") No input was retried."
            saveDiagnostic()
            throw error
        }
    }

    func cancel(operationID: UUID) async {
        if agentOperationID == operationID { stop(); LocalControlRoute.shared.stop() }
    }

    func proofButtonPressed() { proofCount += 1 }

    /// Only called after the page's read/model approval. Captured pixels and
    /// unrelated screen text never leave the phone; the planner gets four labels.
    func requestPointerTarget(_ request: String) {
        guard !busy, !connected, !pointerExperimentRunning, !pointerPlanning else { return }
        invalidatePointerProposal()
        let planner = PointerTargetPlanner(model: ConfiguredModelClient())
        let id = UUID()
        pointerPlanner = planner; pointerPlanID = id; pointerPlanning = true
        pointerPlanStatus = "Reading the four test labels locally… No mouse will be created."
        operation = Task {
            defer {
                if pointerPlanID == id { pointerPlanID = nil }
                pointerPlanning = false; operation = nil
            }
            do {
                try await begin(bundleID: "com.jackadamslovell.PocketAgent", operationID: id)
                // Allow the keyboard/approval dialog and the planning layout to settle.
                try await Task.sleep(for: .milliseconds(900))
                try Task.checkCancellation()
                guard UIApplication.shared.applicationState == .active else { throw CancellationError() }
                let frame = try await captureFrame()
                let labels = try PointerLabObservation(frame: frame).labels
                // End the read-only native session before waiting for the model.
                if agentOperationID == id { _ = await finish() }
                try Task.checkCancellation()
                guard pointerPlanID == id else { throw CancellationError() }
                pointerPlanStatus = "Asking the configured model to choose one label… No movement authorized."
                let proposal = try await planner.propose(request: request, observedLabels: labels)
                try Task.checkCancellation()
                guard pointerPlanID == id, UIApplication.shared.applicationState == .active else { throw CancellationError() }
                pointerProposal = proposal
                pointerPlanStatus = "Proposed: \(proposal.target.rawValue.localizedCapitalized). Approve within 60 seconds. No movement yet."
            } catch {
                if agentOperationID == id { _ = await finish() }
                await planner.cancel()
                pointerProposal = nil
                pointerPlanStatus = error is CancellationError ? "Selection cancelled. No movement authorized." : error.localizedDescription
            }
        }
    }

    func invalidatePointerProposal() {
        guard !pointerPlanning, !pointerExperimentRunning else { return }
        let old = pointerPlanner
        pointerPlanner = nil; pointerProposal = nil
        Task { await old?.cancel() }
        pointerPlanStatus = "Ask for one of the four targets. The agent proposes; you approve movement."
    }

    func cancelPointerPlanning() {
        if pointerPlanning {
            pointerPlanID = nil; operation?.cancel()
            let planner = pointerPlanner
            Task { await planner?.cancel() }
            pointerPlanStatus = "Stopping target selection… No movement authorized."
        } else { invalidatePointerProposal() }
    }

    /// Explicit local approval only. Never enables AssistiveTouch or changes
    /// a system preference. A proposal ID selects one target; nil is the loop test.
    func startPointerExperiment(speed: PocketPointerSpeed, duration: PocketPointerDuration, approvedProposalID: UUID? = nil) {
        guard !busy, !connected, !pointerExperimentRunning, !pointerPlanning else { return }
        let planner = pointerPlanner
        pointerProposal = nil; pointerPlanner = nil
        pointerExperimentRunning = true
        pointerApprovedTarget = nil
        pointerStage = "connecting local route and native engine"
        pointerCancellationReason = nil
        pointerPosition = nil; pointerEverObserved = false
        pointerObservedAt = -.infinity; pointerCaptureAt = -.infinity; pointerUIUpdatedAt = -.infinity
        pointerTargets = []; pointerTargetIndex = 0; pointerCaptureCount = 0
        pointerSteeringCount = 0; pointerArrivalCount = 0; pointerLastArrival = -.infinity
        pointerPreview = nil; pointerSnapshotPosition = nil; pointerSnapshotTarget = nil
        pointerFeedback = "Preparing local screen feedback…"
        pointerStatus = "Connecting the native engine. No clicks or setting changes."
        let operationID = UUID()
        operation = Task {
            var result: String
            do {
                if let approvedProposalID {
                    guard let planner else { throw PointerTargetError.expired }
                    pointerApprovedTarget = try await planner.consume(approvedID: approvedProposalID)
                } else { await planner?.cancel() }
                try Task.checkCancellation()
                try await begin(bundleID: "com.jackadamslovell.PocketAgent", operationID: operationID)
                guard let engine else { throw NativeTestError.notConnected }
                pointerStage = "waiting for movement countdown"
                pointerStatus = "Movement begins in 8 seconds. Watch the physical phone; the Mac preview can be disconnected now."
                try await Task.sleep(for: .seconds(8))
                try Task.checkCancellation()
                guard UIApplication.shared.applicationState == .active else { throw CancellationError() }
                pointerStage = "starting native media"
                _ = try await engine.startMedia()
                // Discard any hover caused by approving the test in a Mac
                // preview. Only events during our own movement phase count.
                pointerPosition = nil; pointerEverObserved = false; pointerObservedAt = -.infinity
                pointerStage = "registering and testing the temporary mouse"
                result = try await engine.probePointerMovement(duration: duration, continueWhile: { [weak self] in
                    guard let self else { return false }
                    return await self.pointerExperimentMayContinue(operationID: operationID)
                }, completed: { [weak self] in
                    guard let self else { return false }
                    return await self.pointerTargetReached
                }, nextMotion: { [weak self] elapsed in
                    guard let self else { throw CancellationError() }
                    return try await self.pointerMotion(engine: engine, operationID: operationID,
                        speed: speed, duration: duration, elapsed: elapsed)
                })
                try await engine.stopMedia()
            } catch is CancellationError {
                result = "Pointer experiment cancelled while \(pointerStage). \(pointerCancellationReason ?? "The native operation was stopped.") Visibility is not verified."
            } catch {
                result = "Pointer experiment failed: \(error.localizedDescription)"
            }
            // Verify own-stream teardown on protocol failures too, before
            // finish() closes the route. Never stop another client's stream.
            if let engine, agentOperationID == operationID {
                do { try await engine.stopMedia() }
                catch { result += "\nMedia cleanup not verified: \(error.localizedDescription)" }
            }
            result += "\n\(speed.rawValue); local captures: \(pointerCaptureCount); hover observed: \(pointerEverObserved); feedback steering commands: \(pointerSteeringCount); target arrivals: \(pointerArrivalCount)."
            if let target = pointerApprovedTarget {
                result += "\nApproved target: \(target.rawValue.localizedCapitalized). \(pointerTargetReached ? "Arrival observed within 14 points. No click sent." : "Arrival not verified. No click sent.")"
            }
            if let pointerPreview {
                // One bounded local test frame, never sent to a model or server.
                try? pointerPreview.write(to: URL.applicationSupportDirectory.appendingPathComponent("PocketControl/pointer-test-frame.png"), options: .atomic)
            }
            let warning = agentOperationID == operationID ? await finish() : nil
            pointerStatus = result + (warning.map { "\n" + $0 } ?? "")
            pointerExperimentRunning = false
            pointerApprovedTarget = nil
            operation = nil
            details = pointerStatus
            saveDiagnostic()
        }
    }

    private var pointerTargetReached: Bool { pointerApprovedTarget != nil && pointerArrivalCount > 0 }

    func observePointer(_ position: CGPoint?) {
        guard pointerExperimentRunning else { return }
        pointerPosition = position
        if position != nil {
            pointerObservedAt = ProcessInfo.processInfo.systemUptime
            pointerEverObserved = true
        }
    }

    private func pointerMotion(engine: PocketNativeEngine, operationID: UUID, speed: PocketPointerSpeed,
                               duration: PocketPointerDuration, elapsed: Double) async throws -> PocketPointerMotion {
        guard pointerExperimentMayContinue(operationID: operationID) else { throw CancellationError() }
        var now = ProcessInfo.processInfo.systemUptime
        // The input loop waits here: do not move during capture/OCR. Never run
        // concurrent captures or display a recursive live preview on the pad.
        if now - pointerCaptureAt >= 3 {
            let captureStarted = now
            let observationBeforeCapture = pointerObservedAt
            let positionAtCapture = now - pointerObservedAt < 0.4 ? pointerPosition : nil
            let data = try await engine.screenshot()
            let frame = try await ImageOCRService.nativeFrame(in: data)
            try Task.checkCancellation()
            guard pointerExperimentMayContinue(operationID: operationID) else { throw CancellationError() }
            guard !frame.containsPermissionPrompt else { throw ScreenControlError.blockedByAlert }
            guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .flatMap(\.windows).first(where: \.isKeyWindow),
                  let image = UIImage(data: data), window.bounds.width > 0,
                  abs(image.size.width / image.size.height - window.bounds.width / window.bounds.height) < 0.01 else {
                throw NativeScreenError.unreadable
            }
            pointerScreenSize = window.bounds.size
            // Only our four inert test labels are steering targets. No arbitrary
            // OCR label can become a control, and this API cannot click.
            let labels = PointerLabTarget.allCases.map(\.rawValue)
            let targets = labels.compactMap { label -> CGPoint? in
                let matches = frame.items.filter { $0.label == label }
                guard matches.count == 1, let item = matches.first else { return nil }
                return CGPoint(x: item.x + item.width / 2, y: item.y + item.height / 2)
            }
            pointerTargets = targets.count == labels.count ? targets : []
            if let target = pointerApprovedTarget {
                let observation = try PointerLabObservation(frame: frame)
                pointerTargets = PointerLabTarget.allCases.map {
                    let text = observation.text(for: $0)
                    return CGPoint(x: text.x + text.width / 2, y: text.y + text.height / 2)
                }
                guard let index = labels.firstIndex(of: target.rawValue) else { throw PointerTargetError.unreadableTargets }
                pointerTargetIndex = index
            }
            pointerPreview = data
            pointerSnapshotPosition = positionAtCapture.map {
                CGPoint(x: $0.x / pointerScreenSize.width, y: $0.y / pointerScreenSize.height)
            }
            pointerSnapshotTarget = pointerTargets.isEmpty ? nil : pointerTargets[pointerTargetIndex % pointerTargets.count]
            pointerCaptureCount += 1
            now = ProcessInfo.processInfo.systemUptime
            // No reports were sent while awaiting capture. A still-present,
            // unchanged hover remains valid across that intentional pause.
            if positionAtCapture != nil, pointerPosition == positionAtCapture,
               pointerObservedAt == observationBeforeCapture {
                pointerObservedAt += now - captureStarted
            }
            pointerCaptureAt = now
        }
        let fresh = now - pointerObservedAt < 0.4
        var motion = PocketPointerMotion.zero
        var mode = "Pointer location unknown · acquisition sweep"
        if let point = pointerPosition, fresh, !pointerTargets.isEmpty {
            let target = pointerTargets[pointerTargetIndex % pointerTargets.count]
            let dx = target.x * pointerScreenSize.width - point.x
            let dy = target.y * pointerScreenSize.height - point.y
            if hypot(dx, dy) <= 14, now - pointerLastArrival > 0.4 {
                if pointerApprovedTarget != nil {
                    pointerArrivalCount = 1; pointerLastArrival = now
                    pointerFeedback = "Observed pointer reached the approved label. Removing the temporary mouse; no click."
                    return .zero
                }
                pointerArrivalCount += 1; pointerTargetIndex += 1; pointerLastArrival = now
                let next = pointerTargets[pointerTargetIndex % pointerTargets.count]
                motion = speed.toward(dxPoints: next.x * pointerScreenSize.width - point.x,
                                      dyPoints: next.y * pointerScreenSize.height - point.y)
                if motion != .zero { pointerSteeringCount += 1 }
            } else {
                motion = speed.toward(dxPoints: dx, dyPoints: dy)
                if motion != .zero { pointerSteeringCount += 1 }
            }
            mode = "Observed pointer \(Int(point.x)), \(Int(point.y)) pt · steering to OCR target"
        } else if pointerEverObserved {
            // Never dead-reckon after losing the pointer. A stale coordinate
            // cannot authorize further directed movement.
            mode = "Pointer/target feedback unavailable · movement paused"
        } else {
            motion = speed.sweep(at: elapsed)
        }
        if now - pointerUIUpdatedAt >= 0.25 {
            pointerStatus = "\(speed.rawValue) · \(max(0, duration.rawValue - Int(elapsed)))s left · movement only"
            pointerFeedback = "\(mode)\n\(pointerCaptureCount) local captures · \(pointerTargets.count)/4 targets · \(pointerArrivalCount) arrivals"
            pointerUIUpdatedAt = now
        }
        return motion
    }

    func cancelPointerExperiment(reason: String = "Stop was requested.") {
        guard pointerExperimentRunning else { return }
        pointerCancellationReason = reason
        pointerStatus = "Stopping movement and removing the temporary mouse…"
        operation?.cancel()
    }

    private func pointerExperimentMayContinue(operationID: UUID) -> Bool {
        pointerExperimentRunning && agentOperationID == operationID
            && UIApplication.shared.applicationState == .active
    }

    func connect() {
        run { [self] in
            let url = URL.applicationSupportDirectory.appendingPathComponent("PocketControl/remote-pairing.plist")
            let engine = try await PocketNativeEngine.connect(host: LocalControlPacket.peerAddress,
                identity: RemotePairingIdentity(contentsOf: url), expectedDevice: "00008150-000A20360212401C")
            self.engine = engine
            self.connected = true
            self.sessionDeadline = .now + 105
            self.status = "Native helper connected. No taps sent."
            self.startActivity()
            self.expiry?.cancel()
            self.expiry = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(105)); self?.stop() } catch { }
            }
            self.details = try await engine.mediaStatus()
        }
    }

    func capture() {
        run {
            guard let engine = self.engine else { throw NativeTestError.notConnected }
            self.preview = try await engine.screenshot()
            self.status = "Native screenshot received · stays on this phone."
        }
    }

    func proveTap() {
        run {
            guard let engine = self.engine else { throw NativeTestError.notConnected }
            self.status = "Native test starts in 8 seconds. Do not touch the phone; the Mac preview can be disconnected now."
            try await Task.sleep(for: .seconds(8))
            self.details = try await engine.startMedia()
            do {
                try await Task.sleep(for: .milliseconds(700))
                let rect = self.proofRect, bounds = UIScreen.main.bounds
                guard UIApplication.shared.applicationState == .active, rect.width > 40, rect.height > 30,
                      bounds.contains(rect), rect.midY > 100 else { throw NativeTestError.invalidTarget }
                let before = self.proofCount
                let packets = try await engine.tap(x: rect.midX / bounds.width, y: rect.midY / bounds.height)
                try await Task.sleep(for: .milliseconds(700))
                self.details += "\nProof counter before: \(before); after: \(self.proofCount); video datagrams: \(packets)."
                self.status = "Touch sent. Checking that only our media session ends."
                try await engine.stopMedia()
                guard self.proofCount == before + 1 else { throw NativeTestError.noTouch }
                self.status = "Native tap verified: the proof button received one touch. Video datagrams: \(packets). Own media stream ended."
            } catch {
                try? await engine.stopMedia()
                throw error
            }
        }
    }

    func openSettings() {
        run {
            guard let engine = self.engine else { throw NativeTestError.notConnected }
            self.status = "Opening Settings through the native engine."
            try await engine.launch(bundleID: "com.apple.Preferences")
            self.status = "Native Settings launch completed."
        }
    }

    func stop() {
        traceTappClick("native-stop",extra:["stack":Array(Thread.callStackSymbols.prefix(12))])
        cancelPointerPlanning()
        endNativeSession(cancelPendingWork: true)
    }

    private func endNativeSession(cancelPendingWork: Bool,preservingCornerBackground:Bool = false) {
        if !preservingCornerBackground { completeCornerBackground(success:false) }
        cornerBatchID=nil; cornerBatchOpened=false
        if cancelPendingWork { operation?.cancel() }
        expiry?.cancel()
        let old = engine; engine = nil; connected = false
        old?.abort()
        Task { await old?.close() }
        if let activity { Task { await activity.end(nil, dismissalPolicy: .immediate) } }
        activity = nil
        if agentBundleID != nil { agentBundleID = nil; busy = false }
        agentOperationID = nil; lastFrame = nil
        status = "Native helper stopped."
        activityStatus = "Native running icon ended."
        allowance.end()
    }

    private func run(_ body: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        allowance.begin { [weak self] in self?.stop() }
        operation = Task {
            defer { busy = false; operation = nil; allowance.end(); saveDiagnostic() }
            do { try await body() }
            catch { status = "Native test failed: \(error.localizedDescription)" }
            if let activity {
                await activity.update(ActivityContent(state: .init(phase: "Native helper connected · authorized control", checkedAt: .now), staleDate: min(.now + 90, sessionDeadline)))
            }
        }
    }

    private func startActivity() {
        guard activity == nil, UIApplication.shared.applicationState == .active else { return }
        do {
            activity = try Activity.request(attributes: NativeControlActivityAttributes(startedAt: .now),
                content: ActivityContent(state: .init(phase: "Native helper connected · authorized control", checkedAt: .now), staleDate: min(.now + 90, sessionDeadline)), pushType: nil)
            activityStatus = "hitapp Live Activity started."
        } catch { activityStatus = "Native running icon unavailable: \(error.localizedDescription)" }
    }

    private func saveDiagnostic() {
        let url = URL.applicationSupportDirectory.appendingPathComponent("PocketControl/native-engine-result.txt")
        try? (status + "\n" + activityStatus + "\n" + navigationStatus + "\n" + details).write(to: url, atomically: true, encoding: .utf8)
    }

    private enum NativeTestError: LocalizedError {
        case notConnected, invalidTarget, noTouch, homeNotReached, bottomNotRecognized, backgroundUnavailable
        var errorDescription: String? {
            switch self {
            case .notConnected: "Connect the native helper first."
            case .invalidTarget: "The measured proof button is not safely visible. No touch sent."
            case .noTouch: "A report was sent but the proof button did not receive exactly one touch. Control is not verified."
            case .homeNotReached: "The requested transition away from hitapp was not verified. No further input was sent."
            case .bottomNotRecognized: "The bottom Home indicator was missing or ambiguous in the fresh capture. No input was sent."
            case .backgroundUnavailable: "iOS did not grant time for the continuous corner check. No test clicks were sent."
            }
        }
    }
}

private struct NativeProofFrame: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct NativeEngineTestSection: View {
    @ObservedObject var native: NativeControlModel
    let routeConnected: Bool
    @State private var confirmingTap = false
    var body: some View {
        Section("Native engine · supervised proof") {
            Button("Proof button · \(native.proofCount) touches", action: native.proofButtonPressed)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(GeometryReader { view in Color.clear.preference(key: NativeProofFrame.self, value: view.frame(in: .global)) })
                .onPreferenceChange(NativeProofFrame.self) { native.proofRect = $0 }
            Button("Connect native engine", action: native.connect).disabled(native.connected || native.busy || !routeConnected)
            Button("Capture native screenshot", action: native.capture).disabled(!native.connected || native.busy)
            Button("Approve one native tap test…") { confirmingTap = true }.disabled(!native.connected || native.busy)
            Button("Open Settings · native engine", action: native.openSettings).disabled(!native.connected || native.busy)
            NavigationLink("Visible pointer experiment…") {
                NativePointerExperimentView(native: native)
            }
                .disabled(native.connected || native.busy)
            Button("Stop native engine", role: .destructive, action: native.stop).disabled(!native.connected)
            Text(native.status).font(.footnote).textSelection(.enabled)
            DisclosureGroup("Native diagnostics") { Text(native.activityStatus + "\n" + native.details).font(.caption.monospaced()).textSelection(.enabled) }
            if let data = native.preview, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220)
            }
        }
        .confirmationDialog("Send one native touch to the proof button?", isPresented: $confirmingTap, titleVisibility: .visible) {
            Button("Allow one proof tap", action: native.proveTap)
            Button("Cancel", role: .cancel) { }
        } message: { Text("After 8 seconds, only the measured button inside hitapp will be tapped. A brief local video stream authenticates input; frames are discarded. Nothing is sent to the model. Do not touch the phone during the test.") }
    }
}

/// Deliberately draws no cursor: a moving dot on this pad must come from iOS.
private struct NativePointerExperimentView: View {
    @ObservedObject var native: NativeControlModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirming = false
    @State private var confirmingRead = false
    @State private var approvedProposalID: UUID?
    @State private var agentTargeting = true
    @State private var targetRequest = "Move to the top right target"
    @StateObject private var voice = VoiceTranscriber()
    @FocusState private var requestFocused: Bool
    @State private var dwellDisabled = false
    @State private var speed: PocketPointerSpeed = .fast
    @State private var duration: PocketPointerDuration = .standard
    private var working: Bool { native.pointerPlanning || native.pointerExperimentRunning }

    var body: some View {
        // Push in the existing stack. A modal owned by a lazy Form Section
        // can lose its presenter and dismiss the entire settings stack.
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Real system pointer · experimental", systemImage: "cursorarrow.motionlines")
                    .font(.title2.bold()).id("pointerTop")
                if !working {
                Picker("Test mode", selection: $agentTargeting) {
                    Text("Agent target").tag(true)
                    Text("Loop test").tag(false)
                }.pickerStyle(.segmented)
                Text(agentTargeting
                    ? "Ask the agent for one target, approve its proposal, then watch the real mouse move there. Target selection uses your configured model (currently Mac Ollama)."
                    : "Movement-only diagnostic loop. Screenshots stay on this phone; no model request.")
                Text("AssistiveTouch must be on and Dwell Control off. Keep this page open. No simulated cursor is drawn.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if agentTargeting {
                    TextField("For example: move to the bottom left", text: $targetRequest, axis: .vertical)
                        .textFieldStyle(.roundedBorder).lineLimit(1...3).focused($requestFocused)
                        .disabled(voice.isRecording || voice.isStarting)
                    Button(voice.isRecording || voice.isStarting ? "Stop dictation" : "Dictate target request", systemImage: "mic") {
                        requestFocused = false
                        if voice.isRecording || voice.isStarting { voice.stop() }
                        else { voice.start() }
                    }
                    Text("Dictation replaces this test request. Review it before asking the agent.").font(.caption)
                    if let error = voice.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                    Text(native.pointerPlanStatus).font(.footnote)
                }
                Picker("Speed", selection: $speed) {
                    ForEach(PocketPointerSpeed.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).disabled(native.pointerExperimentRunning)
                if !agentTargeting { Picker("Duration", selection: $duration) {
                    ForEach(PocketPointerDuration.allCases, id: \.self) { Text("\($0.rawValue)s").tag($0) }
                }.pickerStyle(.segmented).disabled(native.pointerExperimentRunning) }
                }
                if native.pointerPlanning { Text(native.pointerPlanStatus).font(.footnote) }
                VStack {
                    HStack { Text("NORTH WEST"); Spacer(); Text("NORTH EAST") }
                    Spacer()
                    Text("SCREEN TARGETS\nReal pointer position comes from iOS hover events")
                        .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Spacer()
                    HStack { Text("SOUTH WEST"); Spacer(); Text("SOUTH EAST") }
                }
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .padding(20).frame(height: 220)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 24))
                Text(native.pointerStatus).font(.footnote).lineLimit(native.pointerExperimentRunning ? 2 : nil)
                Text(native.pointerFeedback).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                if !working, let data = native.pointerPreview, let image = UIImage(data: data) {
                    Text("Last local capture · orange = OCR target; blue = observed hover position (if available). These are annotations, not a captured cursor.")
                        .font(.caption).foregroundStyle(.secondary)
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                        .overlay {
                            GeometryReader { proxy in
                                if let point = native.pointerSnapshotTarget {
                                    Circle().stroke(.orange, lineWidth: 2).frame(width: 18, height: 18)
                                        .position(x: point.x * proxy.size.width, y: point.y * proxy.size.height)
                                }
                                if let point = native.pointerSnapshotPosition {
                                    Circle().fill(.blue).frame(width: 8, height: 8)
                                        .position(x: point.x * proxy.size.width, y: point.y * proxy.size.height)
                                }
                            }
                        }
                }
            }
            .padding(24)
            .onContinuousHover(coordinateSpace: .global) { phase in
                switch phase {
                case .active(let point): native.observePointer(point)
                case .ended: native.observePointer(nil)
                }
            }
        }
            .scrollDisabled(working)
            .onChange(of: working) { _, running in
                if running { scroll.scrollTo("pointerTop", anchor: .top) }
            }
        }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    if native.pointerPlanning {
                        Button("Stop target selection", role: .destructive) { native.cancelPointerPlanning() }
                            .buttonStyle(.borderedProminent)
                    } else if native.pointerExperimentRunning {
                        Button("Stop movement", role: .destructive) { native.cancelPointerExperiment() }
                            .buttonStyle(.borderedProminent)
                    } else {
                        if agentTargeting {
                            if let proposal = native.pointerProposal {
                                Text("Proposed: \(proposal.target.rawValue.localizedCapitalized)").font(.headline)
                                Toggle("Dwell Control is off", isOn: $dwellDisabled)
                                Button("Approve movement to this target…") {
                                    requestFocused = false; approvedProposalID = proposal.id; confirming = true
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!dwellDisabled || native.busy || native.connected)
                            }
                            Button(native.pointerProposal == nil ? "Read targets & ask agent…" : "Ask agent again…") {
                                voice.stop(); requestFocused = false; confirmingRead = true
                            }
                            .disabled(native.busy || native.connected || voice.isRecording || voice.isStarting || targetRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || targetRequest.count > 500)
                        } else {
                        Toggle("Dwell Control is off", isOn: $dwellDisabled)
                        Button("Approve movement-only test…") { approvedProposalID = nil; confirming = true }
                            .buttonStyle(.borderedProminent)
                            .disabled(!dwellDisabled || native.busy || native.connected)
                        }
                    }
                }.padding().frame(maxWidth: .infinity).background(.regularMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.disabled(working)
                }
            }
            .alert(agentTargeting ? "Move to the proposed target?" : "Run a \(duration.rawValue)-second \(speed.rawValue.lowercased()) mouse test?", isPresented: $confirming) {
                Button("Allow movement only") {
                    if agentTargeting, approvedProposalID == nil { return }
                    native.startPointerExperiment(speed: speed, duration: agentTargeting ? .standard : duration,
                                                  approvedProposalID: approvedProposalID)
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text(agentTargeting
                    ? "Target: \(native.pointerProposal?.target.rawValue.localizedCapitalized ?? "Expired"). Starts after 8 seconds, then runs for at most 30 seconds. Re-reads the targets locally and uses real iOS hover feedback; stops at the approved label. It may sweep briefly to acquire the pointer. No clicks or app switching. Keeps the hand icon, uses the local VPN, and removes its own mouse afterward. No further model request; last image stays on this phone."
                    : "Starts after 8 seconds. Captures locally about every 3 seconds and approaches four inert targets using hover feedback. If no pointer coordinates arrive, it runs a diagnostic sweep. No clicks. Keeps the hand icon and removes its own mouse afterward. Uses the local VPN; no model request. Last test image stays on this phone.")
            }
            .alert("Read the test labels and ask your model?", isPresented: $confirmingRead) {
                Button("Allow read & proposal") { native.requestPointerTarget(targetRequest) }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Uses the existing local VPN for one local screenshot. Only your typed request and the four inert labels go to the configured model; no pixels or other screen text. This phase creates no mouse and sends no input. Movement needs a second approval. Mac Ollama must be running and reachable.")
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    if phase == .background || voice.isRecording { voice.stop() }
                    native.cancelPointerExperiment(reason: "hitapp is no longer active.")
                    native.cancelPointerPlanning()
                }
            }
            .onChange(of: targetRequest) { _, _ in native.invalidatePointerProposal() }
            .onChange(of: voice.transcript) { _, text in
                if !text.isEmpty, !working { targetRequest = text }
            }
            .onChange(of: working) { _, active in if active { voice.stop() } }
            .onChange(of: agentTargeting) { _, _ in voice.stop(); native.invalidatePointerProposal() }
            .onDisappear {
                voice.stop()
                native.cancelPointerExperiment(reason: "The test page disappeared.")
                native.cancelPointerPlanning()
            }
            .navigationBarBackButtonHidden(working)
            .interactiveDismissDisabled(working)
    }
}
