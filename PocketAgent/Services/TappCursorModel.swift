import Combine
import Foundation
import SwiftUI
import UIKit
import ObjectiveC

@MainActor
private final class TappCursorElement: UIAccessibilityElement {
    weak var owner: TappCursorModel?
    override var accessibilityFrame: CGRect {
        get { CGRect(x:(owner?.accessibilityPoint.x ?? 0)-2,y:(owner?.accessibilityPoint.y ?? 0)-26,width:36,height:58) }
        set { }
    }
    override var accessibilityPath: UIBezierPath? {
        get { owner?.renderedPath }
        set { }
    }
}

@MainActor
final class TappCursorModel: ObservableObject, NativeScreenCursor {
    static let shared = TappCursorModel()
    static let navigationRestingY=0.955
    @Published private(set) var enabled = false
    @Published private(set) var connected = false
    @Published private(set) var status = "Tapp is off."
    @Published private(set) var testing = false
    @Published private(set) var idle = false
    private var container: UIView?
    private var timer: Timer?
    private var session = UUID().uuidString
    private var sequence = 0
    private var acknowledgedSequence = -1
    private var rendererReady = false
    private var rendererHidden = false
    private var captureSuppressed = false
    private var pressBegan:CFTimeInterval?
    private var releaseBegan:CFTimeInterval?
    private var bubbleBegan = CACurrentMediaTime()
    private var expires = Date.distantPast
    private var from = CGPoint.zero
    private var destination = CGPoint.zero
    private var started = CACurrentMediaTime()
    private var duration = 0.25
    private var motionID = UUID()
    private var testTask: Task<Void,Never>?
    private var navigationPresentationID:UUID?
    private var navigationDisplayMode=false
    private var lastInteraction = Date.now
    private let allowance = BackgroundAllowance()
    private let documents = URL.documentsDirectory
    #if DEBUG
    private var diagnosticStarted = false
    func runHeldGestureDiagnostic() async throws {
        guard !testing else { throw ScreenControlError.busy }
        start();testing=true
        defer { testing=false }
        let device=NativeControlModel.shared,run=UUID().uuidString
        var completed=[String]()
        func report(_ error:String="") {
            let value:[String:Any]=["runID":run,"completed":completed,"error":error,"time":Date.now.timeIntervalSince1970]
            if let data=try? JSONSerialization.data(withJSONObject:value,options:.prettyPrinted) {
                try? data.write(to:documents.appendingPathComponent("tapp-held-gestures-report.json"),options:.atomic)
            }
        }
        report()
        do {
            for _ in 0..<300 {
                if connected { break }
                try await Task.sleep(for:.milliseconds(100))
            }
            guard connected else { throw TappError.notConnected }
            try await device.beginCornerBatch(totalClicks:2,title:"Tapp gesture test",resetFixture:true)
            let controller=NativeScreenController(device:device,cursor:self)
            let bundle="com.jackadamslovell.TappClickTarget"
            try await controller.configure(enabled:true,allowedBundleID:bundle,mode:.act)
            let before=try await controller.perform(.read,arguments:["bundle_id":.string(bundle)])
            let held=try await controller.perform(.hold,arguments:["bundle_id":.string(bundle),"observation_id":.string(before.observationID),"label":.string("Top left")])
            completed.append("hold");device.updateCornerProgress(completed:1,total:2);report()
            let dragged=try await controller.perform(.drag,arguments:["bundle_id":.string(bundle),"observation_id":.string(held.observationID),"label":.string("Bottom left"),"destination_label":.string("Bottom right")])
            if let image=dragged.screenshot { try image.write(to:documents.appendingPathComponent("tapp-held-gestures-after.png"),options:.atomic) }
            completed.append("drag");device.updateCornerProgress(completed:2,total:2)
            try await device.endCornerBatch(success:true);device.completeCornerBackground(success:true);report()
        } catch {
            report(error.localizedDescription);try? await device.endCornerBatch();device.completeCornerBackground(success:false);throw error
        }
    }

    func runRequestedDiagnostic() {
        guard !diagnosticStarted else { return }
        diagnosticStarted = true
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--tapp-test-movement") { testMovement() }
        else if args.contains("--tapp-test-ten-passes") { testCorners(passes:10) }
        else if let index=args.firstIndex(of:"--tapp-test-ai"),index+1<args.count { testAI(request:args[index+1]) }
    }
    #endif

    private init() { writeState() }

    func restoreIfNeeded() async {
        guard UserDefaults.standard.bool(forKey:"tapp.cursor.enabled"),!enabled else { return }
        try? await Task.sleep(for:.milliseconds(250))
        guard !Task.isCancelled else { return }
        start()
    }

    var point: CGPoint {
        let t = min(1,max(0,(CACurrentMediaTime()-started)/duration))
        let eased = t*t*t*(10+t*(-15+6*t))
        let raw=CGPoint(x: from.x+(destination.x-from.x)*eased,y: from.y+(destination.y-from.y)*eased)
        guard let size=container?.bounds.size,size.width>40,size.height>50 else { return raw }
        // Clamp in PHONE space before any scene compensation. Include the
        // arrow body and outline, not just its tip, within the display.
        return CGPoint(x:min(size.width-38,max(8,raw.x)),y:min(size.height-34,max(34,raw.y)))
    }

    fileprivate var accessibilityPoint:CGPoint {
        captureSuppressed ? CGPoint(x:-64,y:-64) : point.applying(navigationScreenTransform)
    }

    private var navigationCompensation:CGAffineTransform = .identity

    private var navigationScreenTransform:CGAffineTransform {
        navigationDisplayMode ? navigationCompensation : .identity
    }

    func calibrateNavigation(first:CGPoint,second:CGPoint) throws {
        guard let size=container?.bounds.size,navigationDisplayMode else { throw ScreenControlError.invalidArguments }
        let sx=(second.x-first.x)/0.12,sy=(second.y-first.y)/0.72
        guard (0.3...1.1).contains(sx),(0.3...1.1).contains(sy),abs(sx-sy)<0.08 else {
            throw ScreenControlError.staleScreen
        }
        let tx=(first.x-0.06*sx)*size.width,ty=(first.y-0.12*sy)*size.height
        navigationCompensation=CGAffineTransform(a:sx,b:0,c:0,d:sy,tx:tx,ty:ty).inverted()
        from=CGPoint(x:second.x*size.width,y:second.y*size.height);destination=from;started=CACurrentMediaTime()
        writeState()
    }

    func resetNavigationCompensation() {
        navigationCompensation = .identity
        writeState()
    }

    /// Cache only a visually verified entry from hitapp. Reuse is restricted
    /// to the same display geometry and OS; a fresh frame checks it afterward.
    func rememberNavigationEntryCompensation() {
        guard navigationDisplayMode,let size=container?.bounds.size else { return }
        let t=navigationCompensation
        UserDefaults.standard.set([size.width,size.height,t.a,t.b,t.c,t.d,t.tx,t.ty],forKey:"tapp.navigation.entryTransform")
        UserDefaults.standard.set(ProcessInfo.processInfo.operatingSystemVersionString,forKey:"tapp.navigation.entryOS")
    }

    @discardableResult
    func placeAtNavigationBottomImmediately() -> Bool {
        guard navigationPresentationID != nil,let size=container?.bounds.size,
              UserDefaults.standard.string(forKey:"tapp.navigation.entryOS")==ProcessInfo.processInfo.operatingSystemVersionString,
              let values=UserDefaults.standard.array(forKey:"tapp.navigation.entryTransform") as? [Double],
              values.count==8,values.allSatisfy(\.isFinite),values[0]==size.width,values[1]==size.height,
              (0.9...3.4).contains(values[2]),(0.9...3.4).contains(values[5]),values[3]==0,values[4]==0 else { return false }
        navigationCompensation=CGAffineTransform(a:values[2],b:values[3],c:values[4],d:values[5],tx:values[6],ty:values[7])
        // This placement does not wait for AI, OCR, a screenshot, or movement
        // acknowledgement. The companion fetches it on its next refresh.
        from=CGPoint(x:size.width*0.5,y:size.height*Self.navigationRestingY);destination=from
        started=CACurrentMediaTime();duration=0.001;motionID=UUID();sequence+=1
        wake();writeState()
        return true
    }

    #if DEBUG
    func navigationCoordinateProbe() -> [[String:Any]] {
        guard let container else { return [] }
        let objects:[(String,NSObject)] = [("view",container),("application",UIApplication.shared)]
            + (container.window.map { [("window",$0 as NSObject)] } ?? [])
            + ((container.accessibilityElements?.first as? NSObject).map { [("cursor",$0)] } ?? [])
        let names=["_accessibilityScreenPointForSceneReferencePoint:",
                   "_accessibilityDisplayPointForSceneReferencePoint:",
                   "_accessibilityConvertSystemBoundedScreenPointToContextSpace:"]
        typealias Convert = @convention(c) (AnyObject,Selector,CGPoint) -> CGPoint
        return objects.flatMap { label,object in
            names.compactMap { name -> [String:Any]? in
                let selector=NSSelectorFromString(name)
                guard object.responds(to:selector),let cls=object_getClass(object),
                      let method=class_getInstanceMethod(cls,selector),let encoding=method_getTypeEncoding(method),
                      String(cString:encoding)=="{CGPoint=dd}32@0:8{CGPoint=dd}16" else { return nil }
                let convert=unsafeBitCast(method_getImplementation(method),to:Convert.self)
                let points=[CGPoint.zero,CGPoint(x:container.bounds.width,y:container.bounds.height)]
                    .map { point -> [Double] in
                        let result=convert(object,selector,point)
                        return [result.x,result.y]
                    }
                return ["object":label,"method":name,"points":points]
            }
        }
    }

    func probeNavigationHorizontalOffset(_ displayWidths:CGFloat) {
        guard navigationDisplayMode,let size=container?.bounds.size else { return }
        navigationCompensation.tx += displayWidths*size.width*navigationCompensation.a
        writeState()
    }
    #endif

    func correctNavigationPosition(observed:CGPoint,requested:CGPoint) throws {
        guard navigationDisplayMode,let size=container?.bounds.size,
              [observed.x,observed.y,requested.x,requested.y].allSatisfy(\.isFinite) else { throw ScreenControlError.staleScreen }
        navigationCompensation.tx -= (observed.x-requested.x)*size.width*navigationCompensation.a
        navigationCompensation.ty -= (observed.y-requested.y)*size.height*navigationCompensation.d
        // Keep the displayed position continuous while changing coordinate
        // systems; the following move animates from the observed position.
        from=CGPoint(x:observed.x*size.width,y:observed.y*size.height);destination=from;started=CACurrentMediaTime()
        writeState()
    }

    fileprivate var renderedPath:UIBezierPath {
        let now=CACurrentMediaTime()
        var scale=1.0
        if !UIAccessibility.isReduceMotionEnabled {
            if let start=pressBegan {
                let t=min(1,max(0,(now-start)/0.07))
                scale=1-0.12*(1-pow(1-t,3))
            } else if let start=releaseBegan {
                let elapsed=max(0,now-start)
                if elapsed<0.28 {
                    scale=1-0.12*exp(-22*elapsed)*cos(34*elapsed)
                }
            }
        }
        // The live system renderer accepts vector paths, so carry Aura's
        // character, face and bubble through the same cross-app geometry.
        // iOS still chooses the outline colour; this is not a bitmap overlay.
        let path=UIBezierPath()
        let tip=captureSuppressed ? CGPoint(x:-100,y:-100) : point
        let body=[CGPoint(x:0.07,y:0.02),CGPoint(x:0.94,y:0.57),CGPoint(x:0.60,y:0.64),
                  CGPoint(x:0.79,y:0.94),CGPoint(x:0.59,y:1),CGPoint(x:0.40,y:0.70),CGPoint(x:0.14,y:0.92)]
        path.move(to:.zero)
        for p in body.dropFirst() { path.addLine(to:CGPoint(x:(p.x-0.07)*24,y:(p.y-0.02)*30)) }
        path.close()
        for x in [7.0,11.5] {
            path.append(UIBezierPath(roundedRect:CGRect(x:x,y:12,width:1.7,height:3.4),cornerRadius:0.85))
        }
        let smile=UIBezierPath()
        smile.move(to:CGPoint(x:8,y:18))
        smile.addQuadCurve(to:CGPoint(x:12,y:18),controlPoint:CGPoint(x:10,y:20))
        path.append(smile)
        let elapsed=max(0,now-bubbleBegan)
        let pop=UIAccessibility.isReduceMotionEnabled ? 1 : min(1,elapsed/0.48)
        let bubbleScale=pop>=1 ? 1 : max(0.01,1-exp(-7*pop)*cos(10*pop))
        let bubble=UIBezierPath(roundedRect:CGRect(x:0,y:-25,width:31,height:19),cornerRadius:8)
        let tail=UIBezierPath()
        tail.move(to:CGPoint(x:6,y:-6));tail.addLine(to:CGPoint(x:7,y:-2));tail.addLine(to:CGPoint(x:11,y:-6))
        bubble.append(tail)
        for index in 0..<3 {
            let phase=max(0,elapsed-0.35-Double(index)*0.11)
            let bounce = !UIAccessibility.isReduceMotionEnabled && phase>0 && phase<1.95 ? max(0,sin(phase/0.65 * .pi*2))*2 : 0
            bubble.append(UIBezierPath(ovalIn:CGRect(x:8+Double(index)*6,y:-17-bounce,width:2.4,height:2.4)))
        }
        bubble.apply(CGAffineTransform(translationX:-6,y:6))
        bubble.apply(CGAffineTransform(scaleX:bubbleScale,y:bubbleScale))
        bubble.apply(CGAffineTransform(translationX:6,y:-6))
        path.append(bubble)
        path.apply(CGAffineTransform(scaleX:scale,y:scale))
        path.apply(CGAffineTransform(translationX:tip.x,y:tip.y))
        if !captureSuppressed { path.apply(navigationScreenTransform) }
        return path
    }

    func pressFeedback() {
        guard enabled else { return }
        wake(); releaseBegan=nil; pressBegan=CACurrentMediaTime()
    }

    func releaseFeedback() {
        guard enabled else { return }
        pressBegan=nil; releaseBegan=CACurrentMediaTime()
        wake()
    }

    func cancelFeedback() { pressBegan=nil; releaseBegan=nil }

    func testFeedback() {
        guard !testing else { return }
        start(); testing=true
        testTask=Task { [weak self] in
            guard let self else { return }
            defer { self.cancelFeedback(); self.testing=false; self.testTask=nil }
            do {
                for _ in 0..<50 {
                    if self.connected { break }
                    try await Task.sleep(for:.milliseconds(100))
                }
                try await self.ensurePresented()
                for _ in 0..<5 {
                    self.pressFeedback()
                    try await Task.sleep(for:.milliseconds(110))
                    self.releaseFeedback()
                    try await Task.sleep(for:.milliseconds(600))
                }
                self.status="Click animation preview completed. No taps sent."
            } catch { self.status=error.localizedDescription }
        }
    }

    func isEnabled() async -> Bool { enabled }

    /// Capture the app's pixels without the inspector arrow covering text.
    /// Never proceed until the companion confirms that its overlay is hidden.
    func beginScreenRead() async throws -> Bool {
        guard enabled else { return false }
        guard connected,!captureSuppressed else { throw TappError.notConnected }
        captureSuppressed=true; writeState()
        do {
            let deadline=Date.now.addingTimeInterval(3)
            while !rendererHidden && Date.now<deadline {
                try Task.checkCancellation()
                guard enabled,connected else { throw TappError.notConnected }
                try await Task.sleep(for:.milliseconds(20))
            }
            guard rendererHidden else { throw TappError.notConnected }
            try await Task.sleep(for:.milliseconds(50))
            return true
        } catch { endScreenRead(true); throw error }
    }

    func endScreenRead(_ suppressed:Bool) {
        guard suppressed else { return }
        captureSuppressed=false; rendererReady=false; writeState()
    }

    func ensurePresented() async throws {
        guard enabled else { return }
        guard connected else { throw TappError.notConnected }
        wake()
        let deadline=Date.now.addingTimeInterval(3)
        while (!rendererReady || rendererHidden) && Date.now<deadline {
            try Task.checkCancellation()
            guard enabled,connected else { throw TappError.notConnected }
            try await Task.sleep(for:.milliseconds(20))
        }
        guard rendererReady,!rendererHidden else { throw TappError.notConnected }
    }

    func start() {
        guard !enabled else { return }
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { status = "Open hitapp before starting Tapp."; return }
        session = UUID().uuidString
        sequence = 0; acknowledgedSequence = -1; rendererReady = false
        from = CGPoint(x: window.bounds.midX,y: window.bounds.height*0.55); destination = from
        let view = UIView(frame: window.bounds)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElements = ["A","B","C","D"].map { name in
            let element = TappCursorElement(accessibilityContainer: view)
            element.owner = self
            element.accessibilityLabel = "Tapp cursor \(name)"
            element.accessibilityIdentifier = "tapp.cursor.\(name)"
            element.accessibilityTraits = .image
            element.isAccessibilityElement = true
            return element
        }
        var controller = window.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        (controller?.view ?? window).addSubview(view)
        container = view
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--test-switcher-corners-chat") {
            var methods=[String:[String]]()
            for root:AnyClass in [UIAccessibilityElement.self,UIView.self,UIWindow.self,UIWindowScene.self,UIApplication.self] {
                var current:AnyClass?=root
                while let cls=current {
                    let name=NSStringFromClass(cls)
                    if methods[name] == nil {
                        var count:UInt32=0
                        if let list=class_copyMethodList(cls,&count) {
                            defer { free(list) }
                            methods[name]=(0..<Int(count)).compactMap { index in
                                let method=list[index],selector=NSStringFromSelector(method_getName(method))
                                let lower=selector.lowercased()
                                guard lower.contains("accessibility") && ["scene","screen","window","convert","path","frame"].contains(where:lower.contains) else { return nil }
                                return selector+" "+String(cString:method_getTypeEncoding(method)!)
                            }
                        }
                    }
                    current=class_getSuperclass(cls)
                }
            }
            if let data=try? JSONSerialization.data(withJSONObject:methods,options:.prettyPrinted) {
                try? data.write(to:documents.appendingPathComponent("tapp-coordinate-methods.json"),options:.atomic)
            }
        }
        #endif
        enabled = true; connected = false; idle = false; lastInteraction = .now; bubbleBegan = CACurrentMediaTime()
        UserDefaults.standard.set(true,forKey:"tapp.cursor.enabled")
        expires = .now.addingTimeInterval(90)
        status = "Waiting for the Mac companion…"
        allowance.begin { [weak self] in self?.park() }
        writeState()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05,repeats: true) { [weak self] _ in
            Task { @MainActor in self?.readHeartbeat() }
        }
    }

    func stop() {
        cancelFeedback()
        testTask?.cancel(); testTask = nil; testing = false
        from = point; destination = from; motionID = UUID()
        enabled = false; connected = false
        navigationDisplayMode=false; navigationPresentationID=nil; navigationCompensation = .identity
        UserDefaults.standard.set(false,forKey:"tapp.cursor.enabled")
        captureSuppressed=false; rendererHidden=false
        timer?.invalidate(); timer = nil
        writeState()
        container?.removeFromSuperview(); container = nil
        allowance.end()
        status = "Tapp stopped."
    }

    func cancelMotion() async {
        cancelFeedback()
        from = point; destination = from; started = CACurrentMediaTime(); motionID = UUID()
        sequence += 1; writeState()
    }

    func beginNavigationPresentation() -> UUID {
        let id = UUID()
        navigationPresentationID = id
        navigationDisplayMode=true
        wake()
        return id
    }

    func endNavigationPresentation(_ id:UUID) {
        guard navigationPresentationID == id else { return }
        navigationPresentationID = nil
        lastInteraction = .now
        cancelFeedback()
    }

    func wake() {
        guard enabled else { return }
        if idle { rendererReady = false; bubbleBegan = CACurrentMediaTime() }
        idle = false; lastInteraction = .now
        expires = .now.addingTimeInterval(90)
        if NativeControlModel.shared.hasContinuedCornerRun { allowance.end() }
        else { allowance.begin { [weak self] in self?.park() } }
        writeState()
    }

    private func park() {
        guard enabled else { return }
        from = point; destination = from; started = CACurrentMediaTime()
        idle = true; expires = .distantFuture
        rendererReady = false
        writeState()
        allowance.end()
    }

    func move(to target: NativeScreenText) async throws {
        guard target.valid else { throw ScreenControlError.invalidArguments }
        let anchor=target.cursorAnchor
        try await move(x:anchor.x,y:anchor.y)
    }

    func move(x: Double,y: Double) async throws {
        try await moveCursor(x:x,y:y,maximumY:0.90)
    }

    /// The whole arrow reaches the physical bottom edge without clipping.
    func moveToHomeEdge() async throws {
        try await moveCursor(x:0.5,y:0.97,maximumY:0.97)
    }

    func moveToNavigationRestingPoint() async throws {
        try await moveCursor(x:0.5,y:Self.navigationRestingY,maximumY:0.97)
    }

    #if DEBUG
    func moveToNavigationCorner(x:Double,y:Double) async throws {
        guard navigationPresentationID != nil,[0.06,0.92].contains(x),[0.08,0.94].contains(y) else {
            throw ScreenControlError.invalidArguments
        }
        try await moveCursor(x:x,y:y,maximumY:0.94,minimumY:0.08)
    }
    #endif

    private func moveCursor(x:Double,y:Double,maximumY:Double,minimumY:Double=0.12) async throws {
        guard enabled,connected,let container else { throw TappError.notConnected }
        guard x.isFinite,y.isFinite,x>=0.02,x<=0.98,y>=minimumY,y<=maximumY else { throw ScreenControlError.invalidArguments }
        wake()
        // Do not spend the animation while the companion is still parked.
        let readyDeadline = Date.now.addingTimeInterval(3)
        while !rendererReady && Date.now < readyDeadline {
            try Task.checkCancellation()
            guard enabled,connected else { throw TappError.notConnected }
            try await Task.sleep(for:.milliseconds(20))
        }
        guard rendererReady else { throw TappError.notConnected }
        let current = point
        let next = CGPoint(x: x*container.bounds.width,y: y*container.bounds.height)
        let distance = hypot(next.x-current.x,next.y-current.y)
        duration = min(0.38,max(0.18,distance/1800))
        from = current; destination = next; started = CACurrentMediaTime()
        let id = UUID(); motionID = id; sequence += 1
        let commandSequence = sequence
        writeState()
        try await Task.sleep(for: .seconds(duration+0.05))
        // Require fresh presentation acknowledgements after the movement.
        let deadline = Date.now.addingTimeInterval(2)
        while acknowledgedSequence < commandSequence && Date.now < deadline {
            try Task.checkCancellation()
            guard enabled,connected,motionID == id else { throw TappError.notConnected }
            try await Task.sleep(for: .milliseconds(40))
        }
        try Task.checkCancellation()
        guard enabled,connected,motionID == id,acknowledgedSequence >= commandSequence else { throw TappError.notConnected }
    }

    func testMovement() {
        guard !testing else { return }
        start(); testing = true
        testTask = Task { [weak self] in
            guard let self else { return }
            defer { self.testing = false; self.testTask = nil }
            let began=Date.now
            let runID=UUID().uuidString
            var completed=0
            func report(_ error:String? = nil) {
                let value:[String:Any] = ["runID":runID,"started":began.timeIntervalSince1970,
                    "time":Date.now.timeIntervalSince1970,"completedMoves":completed,
                    "verified":completed==15 && error==nil,"error":error ?? ""]
                if let data=try? JSONSerialization.data(withJSONObject:value) {
                    try? data.write(to:self.documents.appendingPathComponent("tapp-movement-report.json"),options:.atomic)
                }
            }
            report()
            do {
                for _ in 0..<50 {
                    if self.connected { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                for _ in 0..<3 {
                    for p in [(0.25,0.55),(0.75,0.55),(0.5,0.35),(0.5,0.65),(0.5,0.55)] {
                        try await self.move(x: p.0,y: p.1)
                        completed += 1; report()
                        try await Task.sleep(for: .milliseconds(150))
                    }
                }
                self.status = "Tapp movement test completed."
            } catch { self.status = error.localizedDescription; report(error.localizedDescription) }
        }
    }

    func testClick() {
        guard !testing else { return }
        start(); testing = true
        testTask = Task { [weak self] in
            guard let self else { return }
            defer { self.testing = false; self.testTask = nil }
            do {
                for _ in 0..<50 {
                    if self.connected { break }
                    try await Task.sleep(for: .milliseconds(100))
                }
                guard self.connected else { throw TappError.notConnected }
                try await self.move(x:0.5,y:0.72)
                let controller = NativeScreenController(device: NativeControlModel.shared,cursor:self)
                let bundle = "com.jackadamslovell.TappClickTarget"
                try await controller.configure(enabled:true,allowedBundleID:bundle,mode:.act)
                let read = try await controller.perform(.read,arguments:["bundle_id":.string(bundle)])
                try read.text.write(to:self.documents.appendingPathComponent("tapp-click-read.txt"),atomically:true,encoding:.utf8)
                if let image=read.screenshot { try image.write(to:self.documents.appendingPathComponent("tapp-click-before.png"),options:.atomic) }
                let labels = read.text.components(separatedBy:"\n").filter { $0 == "Centre ready" }
                guard labels.count == 1 else { throw ScreenControlError.staleScreen }
                let result = try await controller.perform(.tap,arguments:["bundle_id":.string(bundle),
                    "observation_id":.string(read.observationID),"label":.string("Centre ready")])
                let verified = result.text.components(separatedBy:"\n").contains("Centre clicked")
                self.status = verified ? "Tapp click verified in the separate test app." : "Tap dispatched; the counter change was not verified."
                let report: [String:Any] = ["verified":verified,"outcome":result.outcome,"time":Date.now.timeIntervalSince1970]
                try JSONSerialization.data(withJSONObject:report).write(to:self.documents.appendingPathComponent("tapp-click-report.json"),options:.atomic)
                if let image = result.screenshot { try image.write(to:self.documents.appendingPathComponent("tapp-click-after.png"),options:.atomic) }
            } catch {
                self.status = error.localizedDescription
                let report: [String:Any] = ["verified":false,"error":error.localizedDescription,"time":Date.now.timeIntervalSince1970]
                if let data = try? JSONSerialization.data(withJSONObject:report) {
                    try? data.write(to:self.documents.appendingPathComponent("tapp-click-report.json"),options:.atomic)
                }
            }
        }
    }

    func cancelCornerRun() async { testTask?.cancel(); await cancelMotion() }

    func testAI(request:String) {
        guard !testing else { return }
        testTask=Task { [weak self] in
            guard let self else { return }
            do { _ = try await self.performAITest(request:request) }
            catch { self.status="Tapp AI stopped: \(error.localizedDescription)" }
            self.testTask=nil
        }
    }

    /// One real model-selected click against the separate counter-only fixture.
    /// All coordinates and success checks come from local fresh observations.
    func performAITest(request:String) async throws -> String {
        guard !testing else { throw ScreenControlError.busy }
        guard !request.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,request.count<=500 else { throw TappAIError.invalidRequest }
        start(); testing=true
        defer { testing=false }
        let runID=UUID().uuidString,began=Date.now
        let device=NativeControlModel.shared
        var stage="connecting",selected="",verified=false
        func report(_ error:String? = nil) {
            let value:[String:Any] = ["runID":runID,"started":began.timeIntervalSince1970,
                "time":Date.now.timeIntervalSince1970,"request":request,"stage":stage,
                "modelSelectedLabel":selected,"verified":verified,"error":error ?? ""]
            if let data=try? JSONSerialization.data(withJSONObject:value) {
                try? data.write(to:documents.appendingPathComponent("tapp-ai-report.json"),options:.atomic)
            }
        }
        report()
        do {
            for _ in 0..<300 {
                if connected { break }
                try await Task.sleep(for:.milliseconds(100))
            }
            guard connected else { throw TappError.notConnected }
            try await move(x:0.5,y:0.72)
            try await device.beginCornerBatch(totalClicks:1,title:"Tapp AI test",resetFixture:true)
            let controller=NativeScreenController(device:device,cursor:self)
            let bundle="com.jackadamslovell.TappClickTarget"
            try await controller.configure(enabled:true,allowedBundleID:bundle,mode:.act)
            stage="reading"; status="Tapp is reading the test page…"; report()
            let before=try await controller.perform(.read,arguments:["bundle_id":.string(bundle)])
            try before.text.write(to:documents.appendingPathComponent("tapp-ai-before.txt"),atomically:true,encoding:.utf8)
            if let data=before.screenshot { try data.write(to:documents.appendingPathComponent("tapp-ai-before.png"),options:.atomic) }
            try TappAIPlanner.validateInitialScreen(before.text)
            stage="choosing"; status="AI is choosing the requested test button…"; report()
            let target=try await TappAIPlanner(model:ConfiguredModelClient()).select(request:request,screenText:before.text)
            selected=target.rawValue
            try Task.checkCancellation()
            guard enabled,device.hasContinuedCornerRun else { throw CancellationError() }
            stage="moving-and-clicking"; status="Tapp is clicking \(selected)…"; report()
            let result=try await controller.perform(.tap,arguments:["bundle_id":.string(bundle),
                "observation_id":.string(before.observationID),"label":.string(selected)])
            stage="verifying"; report()
            try result.text.write(to:documents.appendingPathComponent("tapp-ai-after.txt"),atomically:true,encoding:.utf8)
            if let data=result.screenshot { try data.write(to:documents.appendingPathComponent("tapp-ai-after.png"),options:.atomic) }
            try TappAIPlanner.verifyResult(result.text,selected:target)
            device.updateCornerProgress(completed:1,total:1)
            stage="cleanup"; report()
            try await device.endCornerBatch(success:true)
            verified=true; stage="complete"; report()
            device.completeCornerBackground(success:true)
            status="AI selected \(selected). One click and its counter change were verified."
            return status
        } catch {
            report(error.localizedDescription)
            try? await device.endCornerBatch()
            device.completeCornerBackground(success:false)
            throw error
        }
    }

    func testCorners(passes:Int = 1) {
        guard !testing,[1,10].contains(passes) else { return }
        start(); testing = true
        testTask = Task { [weak self] in
            guard let self else { return }
            defer { self.testing = false; self.testTask = nil }
            let runID=UUID().uuidString
            let began=Date.now
            var completed=[String]()
            var stage="connect"
            @MainActor func report(_ error:String? = nil) {
                self.writeCornerReport(completed:completed,stage:stage,error:error,
                    passes:passes,runID:runID,started:began)
            }
            report()
            do {
                for _ in 0..<50 {
                    if self.connected { break }
                    try await Task.sleep(for:.milliseconds(100))
                }
                guard self.connected else { throw TappError.notConnected }
                try await self.move(x:0.5,y:0.72)
                let device=NativeControlModel.shared
                try await device.beginCornerBatch(totalClicks:passes*4)
                let controller=NativeScreenController(device:device,cursor:self)
                let bundle="com.jackadamslovell.TappClickTarget"
                try await controller.configure(enabled:true,allowedBundleID:bundle,mode:.act)
                stage="read"; report()
                var result=try await controller.perform(.read,arguments:["bundle_id":.string(bundle)])
                try result.text.write(to:self.documents.appendingPathComponent("tapp-corners-read.txt"),atomically:true,encoding:.utf8)
                if let image=result.screenshot { try image.write(to:self.documents.appendingPathComponent("tapp-corners-before.png"),options:.atomic) }
                let names=["Top left","Top right","Bottom left","Bottom right"]
                var counts=Dictionary(uniqueKeysWithValues:names.map { ($0,0) })
                func label(_ name:String,_ count:Int) -> String {
                    let words=["zero","done","two","three","four","five","six","seven","eight","nine","ten"]
                    return count==0 ? name : "\(name) \(words[count])"
                }
                func verified(_ text:String) -> Bool {
                    let lines=text.components(separatedBy:"\n")
                    return names.allSatisfy { name in lines.filter { $0 == label(name,counts[name]!) }.count == 1 }
                }
                // Require a fresh zero-count fixture before the first input.
                guard verified(result.text) else { throw TappError.counterNotVerified }
                for pass in 1...passes {
                    for name in names {
                        try Task.checkCancellation()
                        stage="Pass \(pass)/\(passes) · \(name) · dispatch"; report()
                        self.status=stage
                        result=try await controller.perform(.tap,arguments:["bundle_id":.string(bundle),
                            "observation_id":.string(result.observationID),"label":.string(label(name,counts[name]!))])
                        stage="Pass \(pass)/\(passes) · \(name) · verify"
                        try result.text.write(to:self.documents.appendingPathComponent("tapp-corners-after.txt"),atomically:true,encoding:.utf8)
                        if let image=result.screenshot { try image.write(to:self.documents.appendingPathComponent("tapp-corners-after.png"),options:.atomic) }
                        counts[name]! += 1
                        guard verified(result.text) else { throw TappError.counterNotVerified }
                        completed.append("\(pass): \(name)")
                        device.updateCornerProgress(completed:completed.count,total:passes*4)
                        if name=="Bottom right",let image=result.screenshot {
                            try image.write(to:self.documents.appendingPathComponent("tapp-corners-pass-\(pass).png"),options:.atomic)
                        }
                        report()
                    }
                }
                stage="cleanup"; report()
                try await device.endCornerBatch(success:true)
                stage="complete"; report()
                self.status="\(passes) consecutive corner pass\(passes==1 ? "" : "es") verified. Stayed on the test page."
                device.completeCornerBackground(success:true)
            } catch {
                self.status="Corner check stopped at \(stage): \(error.localizedDescription)"
                report(error.localizedDescription)
                try? await NativeControlModel.shared.endCornerBatch()
                NativeControlModel.shared.completeCornerBackground(success:false)
            }
        }
    }

    private func writeCornerReport(completed:[String],stage:String,error:String?,passes:Int,runID:String,started:Date) {
        let report:[String:Any]=["verified":completed.count==passes*4 && stage=="complete" && error==nil,
            "runID":runID,"requestedPasses":passes,"completedPasses":completed.count/4,
            "completed":completed,"stage":stage,"error":error ?? "",
            "started":started.timeIntervalSince1970,"time":Date.now.timeIntervalSince1970]
        if let data=try? JSONSerialization.data(withJSONObject:report) {
            try? data.write(to:documents.appendingPathComponent("tapp-corners-report.json"),options:.atomic)
        }
    }

    private func writeState() {
        let size = container?.bounds.size ?? CGSize(width: 1,height: 1)
        let transform=navigationScreenTransform
        let state: [String:Any] = ["session":session,"enabled":enabled,"sequence":sequence,
            "expires":expires.timeIntervalSince1970,"x":destination.x/size.width,"y":destination.y/size.height,
            "duration":duration,"requestedRate":120,"idle":idle,"captureSuppressed":captureSuppressed,
            "assistiveTouchRunning":UIAccessibility.isAssistiveTouchRunning,
            "navigation":navigationDisplayMode,
            "screenTransform":[transform.a,transform.b,transform.c,transform.d,transform.tx,transform.ty]]
        if let data = try? JSONSerialization.data(withJSONObject: state) {
            try? data.write(to: documents.appendingPathComponent("tapp-session.json"),options:.atomic)
        }
    }

    private func readHeartbeat() {
        guard enabled else { return }
        // Keep the same AX elements alive when the settings sheet closes.
        // Their identifiers remain stable as the view joins the visible host.
        if UIApplication.shared.applicationState == .active, let container,
           let window=UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where:\.isKeyWindow) {
            var host=window.rootViewController
            while let presented=host?.presentedViewController, !presented.isBeingDismissed { host=presented }
            if let view=host?.view, container.superview !== view { view.addSubview(container) }
        }
        if navigationPresentationID == nil,UIApplication.shared.applicationState == .active { navigationDisplayMode=false; navigationCompensation = .identity }
        if !idle && !navigationDisplayMode && (Date.now >= expires || (navigationPresentationID == nil && Date.now.timeIntervalSince(lastInteraction)>3)) { park() }
        guard let data = try? Data(contentsOf: documents.appendingPathComponent("tapp-host.json")),
              let value = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
              value["session"] as? String == session,
              let time = value["time"] as? Double, abs(Date.now.timeIntervalSince1970-time)<2,
              value["active"] as? Bool == true else {
            if connected { status = "Tapp lost its Mac connection. Input will wait." }
            connected = false; return
        }
        if !connected { status = "Tapp connected · AssistiveTouch can stay off." }
        if !connected { connected = true }
        rendererReady = value["rendererReady"] as? Bool == true
        rendererHidden = value["rendererHidden"] as? Bool == true
        acknowledgedSequence = value["sequence"] as? Int ?? -1
    }
    private enum TappError: LocalizedError {
        case notConnected, counterNotVerified
        var errorDescription: String? {
            switch self {
            case .notConnected: "Tapp is not connected to its Mac companion. No new click was sent."
            case .counterNotVerified: "The tap returned, but its counter change was not verified. No tap was retried."
            }
        }
    }
}

struct TappCursorSection: View {
    @ObservedObject private var tapp = TappCursorModel.shared
    @State private var aiRequest="Tap the upper right button"
    var body: some View {
        Section("Tapp cursor") {
            Toggle("Tapp",isOn: Binding(get:{ tapp.enabled },set:{ $0 ? tapp.start() : tapp.stop() }))
            Text(tapp.status).font(.footnote)
            Button("Test smooth movement") { tapp.testMovement() }.disabled(tapp.testing)
            Button("Test one click in the test app") { tapp.testClick() }.disabled(tapp.testing)
            Button("Tap each corner") { tapp.testCorners() }.disabled(tapp.testing)
            Button("Ten corner passes · stay on page") { tapp.testCorners(passes:10) }.disabled(tapp.testing)
            Button("Preview click animation") { tapp.testFeedback() }.disabled(tapp.testing)
            TextField("Ask Tapp to click a test button",text:$aiRequest)
                .textInputAutocapitalization(.sentences)
            Button("Test Tapp with AI") { tapp.testAI(request:aiRequest) }
                .disabled(tapp.testing || aiRequest.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            Text("Starts a fresh Tapp Click Test page. AI selects one button; Tapp clicks once and checks the result.")
                .font(.caption).foregroundStyle(.secondary)
            if #available(iOS 26.0, *) {
                HStack {
                    VStack(alignment:.leading,spacing:4) {
                        Text("Red Liquid Glass").font(.subheadline)
                        Text("Appearance preview · cross-app colour is still system-controlled.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    TappGlassCursor().frame(width:16,height:24)
                }
            }
            Text("Tiny Aura character with a face and animated speech bubble. Uses the Mac companion while we develop on-phone rendering. AI pointing and taps wait for Tapp to reach the observed target. The current system colour is green.").font(.footnote)
        }
    }
}

/// Reusable material for Tapp's app-owned renderer. The accessibility audit
/// renderer accepts geometry only; this preview is not a cross-app material.
private struct TappArrowShape: Shape {
    func path(in rect:CGRect) -> Path {
        var path=Path()
        path.move(to:CGPoint(x:rect.minX,y:rect.minY))
        for p in [CGPoint(x:0,y:36),CGPoint(x:9,y:28),CGPoint(x:16,y:43),
                  CGPoint(x:23,y:40),CGPoint(x:16,y:25),CGPoint(x:29,y:25)] {
            path.addLine(to:CGPoint(x:rect.minX+p.x/29*rect.width,y:rect.minY+p.y/43*rect.height))
        }
        path.closeSubpath()
        return path
    }
}

@available(iOS 26.0, *)
private struct TappGlassCursor: View {
    var body:some View {
        Color.clear
            .glassEffect(.regular.tint(.red),in:TappArrowShape())
            .overlay(TappArrowShape().stroke(.white.opacity(0.65),lineWidth:0.6))
            .shadow(color:.black.opacity(0.25),radius:2,y:1)
            .allowsHitTesting(false)
            .accessibilityLabel("Small red Liquid Glass cursor preview")
    }
}
