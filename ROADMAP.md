# hitapp product plan

## Tapp navigation progress and current blocker — 2026-10-19

Tapp visibly reached all four phone corners outside a stationary App Switcher card on the physical iPhone Air with AssistiveTouch OFF. The owner confirmed this result. Measured screen-space compensation and its working source checkpoint are saved in [Tapp Lab](DeveloperTools/TappLab/README.md).

The next acceptance gate is keeping the entire cursor visible and smooth while cards move. It still slides offscreen during horizontal browsing; requested-coordinate clamping alone has not fixed the compositor movement. Automatic companion recovery has already passed three forced transport-loss tests and a subsequent AI click through chat. The new bounded AI navigation planner is implemented and unit tested, but live navigation acceptance and reliable app closing remain unfinished.

## Tapp verified cursor and click milestone — 2026-10-19

**The physical iPhone Air passed ten consecutive four-corner runs: 40 native clicks with AssistiveTouch OFF, without leaving the fixture.** Independent button counts, touch coordinates, ordered native input and owned-media cleanup all pass. The owner accepted the higher-refresh motion. [Evidence and reproduction](DeveloperTools/TappLab/README.md).

The companion targets 120 refresh requests/second with four distinct elements and fewer heartbeat writes. Measured acknowledgements are approximately 116/second during movement-only testing and 28/second during the complete native-click run; these are not measured display FPS. Absolute geometry, a fixed cursor frame and bottom-centre target anchoring remove the earlier stretched path from all ten saved pass captures. The existing accepted movement curve is retained.

The first AI integration is implemented: `Test Tapp: tap the upper right button` in chat, or the dedicated Tapp AI test control. The model selects one freshly observed fixture label; Tapp obtains coordinates locally, revalidates, moves, clicks once and verifies the selected counter. The fixture resets automatically, and only its five labels plus the user's request reach the model. Forty-four focused planner/controller tests pass. Two live configured-model runs also pass on the physical phone: “Tap the upper right button” and “Click the button in the middle” each selected the correct label, produced exactly one independently received native click, changed only the expected counter and completed media cleanup. The chat UI entry path also passed: a request typed and sent through hitapp selected Top right, produced exactly one verified native click, and displayed the success message when returning to chat. [Chat evidence](DeveloperTools/TappLab/Evidence/ai-chat-upper-right-verification.json). The first attempt stopped without clicking on an expired Mac companion tunnel; a companion restart restored the connection. [Upper-right evidence](DeveloperTools/TappLab/Evidence/ai-upper-right-v2-verification.json) · [Middle evidence](DeveloperTools/TappLab/Evidence/ai-middle-verification.json).

Next milestones:

1. Keep Tapp visibly within the physical screen during App Switcher motion, preserving the accepted movement curve. Automatic recovery for expired companion tunnels now passes forced transport-loss coverage; longer sleep/lock testing remains.
2. Expand the existing native AI tools to verified tasks in another allowed app, keeping the accepted cursor motion.
3. Test app switching, lock/unlock and reconnection; separately establish force-quit expectations.
4. Replace the paired Mac rendering dependency if an evidenced on-phone route becomes available.
5. Complete the intended appearance and contextual conversation UI.

Mac assistance remains required. Cross-app colour is system-controlled; red Liquid Glass is currently an in-app preview. Actual idle fading, indefinite lifetime, force-quit survival and standalone phone operation remain open requirements.

## Tapp UI requirement — HeyClicky, 2026-10-18

The owner clarified: **“Literally the same UI as heyclicky.”** Tapp should use HeyClicky's floating buddy/cursor and nearby conversation UI as the visual and interaction reference: a small character over the current app, a transparent surrounding surface, free positioning and contextual responses. Keep the Tapp name and cute character. The required target remains the **physical iPhone Air across apps with AssistiveTouch OFF**, without an XCTest automation overlay. An in-app preview or simulator demonstration does not fulfill this requirement.

**The Picture in Picture experiment is rejected.** It visibly floated over hitapp and Settings with the five accessibility/feature getters false, but its video tile, system controls and corner-constrained positioning are the wrong UI. The owner rejected it; playback stopped and audio-session deactivation was recorded. The source is archived outside the build under `DeveloperTools/TappLab/RejectedExperiments/PictureInPicture`; the active probe no longer includes the mode or background-audio declaration. Evidence: [physical events and cleanup](DeveloperTools/TappLab/Evidence/device-pip-rejected-events.json).

[HeyClicky's official site](https://www.heyclicky.com/) describes a Mac app. Its UI is the requested reference, but its existence does not establish an iOS overlay mechanism. **The requested physical cross-app Tapp is still not working.** Prior renderer permission and inactive native-pointer results below remain unresolved; PiP is not a completed milestone or fallback product direction.

## Tapp pointer-service phone experiments — 2026-10-18, 21:44

**The phone was unlocked and both pending physical experiments ran. Tapp still does not work across apps with AssistiveTouch off.** The ordinary visibility/keep-alive assertions and the additional system-pointer-scene preparation each ran alongside hitapp's existing Fast / 10-second motion loop. Each loop completed **334 native reports, 3 local captures, no hover, no steering and no target arrivals**. Both saved in-flight frames show no cursor. Mac screen sharing was disconnected during motion.

Each research run recorded ten observations with visibility 0, interaction state 0 and position `{0, 0}`, and no state-change callbacks. The native report lacks per-report timestamps, so the exact duration of overlap is not independently established. Scene preparation returning without an exception is not proof that a scene activated. Both runs recorded normal assertion cleanup; the second also requested scene invalidation. Native mouse removal and connection closure were verified. AssistiveTouch, Dwell, Pointer Control and both runtime feature flags remained false, including the final 21:44:33 check.

Saved [assertion-plus-HID evidence](DeveloperTools/TappLab/Evidence/device-combined-20261018-2141-summary.json), [scene-plus-HID evidence](DeveloperTools/TappLab/Evidence/device-scene-combined-20261018-2144-summary.json), and code/reproduction instructions in [TappLab](DeveloperTools/TappLab/README.md). Added state-change delegates and a finite optional pointer-scene probe. Signed phone build installed as sequence **3728**. Both corresponding simulator cleanup checks passed; production hitapp code was not changed.

The remaining obstacle is a demonstrated rendering/input route on the physical phone, not device unlock. Direct custom rendering still fails at the previously traced displayable-context permission boundary; requesting native pointer visibility and preparing its scene did not activate pointer input. Do not mark this feature complete, enable AssistiveTouch as a substitute, or present the simulator demo as physical support. A next implementation needs a different, evidenced mechanism rather than a longer run of these same requests.

## Tapp physical off-state comparison — 2026-10-18, 20:00

The requested native-HID comparison now ran on the physical iPhone Air with AssistiveTouch **OFF** and the Mac preview disconnected during motion. Fast / 30 seconds produced 1,015 native-format reports and 9 local captures, but **no hover events, feedback steering or target arrivals**. The saved in-flight frame has no cursor; no working off-state pointer was established. Own mouse removal, connection close and activity end were recorded. Read-only checks before and after found AssistiveTouch, Dwell, Pointer Control, AXAction and AXAction_PointerControl all **false**. See the [raw result](DeveloperTools/TappLab/Evidence/device-native-pointer-off-20261018.txt) and [Tapp handoff](DeveloperTools/TappLab/README.md).

Recorded a [fresh simulator video](DeveloperTools/TappLab/Evidence/tapp-live-demo-20261018-195639.mp4) showing the cute renderer moving across apps and parking on Home, followed by normal cleanup. Added `--state-only` and a finite `--pointer-service` mode to the independent phone research app. The next hypothesis is visibility/keep-alive assertions combined with the existing 10-second mouse loop. Updated phone and simulator diagnostic builds pass; the phone app is installed, but the combined physical experiment has **not run** because the phone locked. Cancelled the pending launch and disconnected the preview; no passcode attempt or accessibility setting changes. Production hitapp source remains unchanged.

**20:07 lifecycle repair:** simulator testing exposed a crash in `BSSimpleAssertion dealloc` when an active pointer assertion was released. Both research targets now explicitly invalidate visibility/keep-alive assertions before release. The [phone-style simulator regression](DeveloperTools/TappLab/Evidence/20261018-200621-pointer-service-cleanup/result.json) passed normal background cleanup and external termination in 31.87 seconds. Repaired signed phone build installed as database sequence 3712. Device lock query reports `passcodeRequired: true`; next physical assertion-plus-HID test is pending unlock, with no launch queued. This lifecycle pass does not establish pointer visibility.

## Tapp cross-app research — 2026-10-18, after 18:45

**Tapp now renders as a cute mint character over Settings, a separate app and Home on the isolated iPhone Air simulator with AssistiveTouch OFF. The physical iPhone requirement remains blocked.** It moves, parks centrally and remains visible in a capture 70 seconds after switching out, beyond background-task expiration. The finite external runner then removes it. This proves simulator cross-app drawing, not permanent lifetime, native input or a physical-device pass.

Added independent `TappOverlayProbe`, `TappDeviceProbe` and shared Core Animation renderer under [TappLab](DeveloperTools/TappLab/README.md). Both remote and local context tests on the normally signed iOS 27.2 phone returned valid contexts with display ID **0**, despite requesting **1**; the mint character did not appear. Offline inspection of the exact phone-build QuartzCore image traces `displayable` permission to `com.apple.QuartzCore.displayable-context`, absent from our signature. Calling Pointer Control's setter is also gated by runtime features; no phone feature-flag state is inferred from the static binary.

The repeated `20261018-184942-layer-idle` run passed its 70-second observation and explicit external termination/recovery checks. Visual review confirmed the character present before termination and gone afterwards. Updated simulator and signed phone diagnostic builds passed. No physical input or permanent-lifetime pass is claimed.

**Latest phone state: AssistiveTouch OFF, Dwell OFF, Pointer Control getter OFF.** This follows the owner's renewed instruction to pursue off-state operation and supersedes historical ON-baseline restoration notes below. Further phone interaction stopped when the phone entered personal use. The separate Tapp Research app remains installed; updated diagnostics build successfully but have not been reinstalled. Production hitapp sources and native input behavior were not changed. The off-state native-HID A/B comparison remains unrun; the physical renderer test is a different experiment. See [evidence and handoff](docs/research/assistivetouch-2026-10-18/README.md#tapp-cross-app-renderer-follow-up).

## Installed naming migration and cleanup — 2026-10-18

**hitapp is now the installed app name**, not just the roadmap name. The signed in-place update (device database sequence 3664) renames visible UI, voice/Shortcuts labels and Live Activity text while retaining the original bundle ID, intent type identities, URL scheme, native pairing identity and stored settings. The Dynamic Island hand remains. All 123 strict core tests and the signed build passed. Owner-approved removal of iCTRL and iCTRLUITests-Runner, including their phone-local data, is verified by device inventory; local source remains available for reinstallation, but deleted phone data was not preserved. Tailscale and the separate simulator work were untouched. The phone was locked after installation, so launch/control revalidation is pending; no touch or accessibility settings changed. See the README's phone-update checkpoint for verification details.

Naming-update follow-up: the owner unlocked the phone and the updated hitapp launched successfully through the device service. Visual UI and control revalidation remain separate; the other agent's simulator preview was left untouched.

## Historical pointer dependency experiment — 2026-10-18, 18:27

The unchanged physical-phone baseline (AssistiveTouch ON, Dwell OFF; Fast / 30 seconds; Mac preview disconnected during movement) completed 1,010 motion-only reports, 9 local captures, real hover feedback, 73 steering commands and 1 target arrival. The owner confirmed visible pointer movement. Temporary mouse removal was verified; the connection closed and tunnel process was absent. Hand/no-Automation visibility was not specifically reconfirmed for this run. The off-state comparison has **not run**: another session twice switched the shared Device Hub to the separate Tapp Lab simulator, including after the owner said it was free. Cleanup inspection confirmed AssistiveTouch remained ON, with Dwell last verified OFF. Coordinate exclusive Device Hub use before continuing. See the [dated research record](docs/research/assistivetouch-2026-10-18/README.md#main-agent-execution-handoff); do not infer physical support from the separate simulator demo.

## Latest implementation checkpoint — 2026-10-18, 18:13

Persistent native access is installed: screen scope/mode and navigation survive launch, Stop remains persistent, and routine reads/navigation no longer request the same approval repeatedly. The physical in-app Open Settings command passed without an approval card; 123 strict core tests pass. iOS permissions, pairing, app scope, freshness checks and consequence review are not bypassed. Dynamic Island/native engine remains; cursor work was untouched.

The selected Lalith received one send attempt for `Hello`: Apple MessageUI returned `.sent` after Codex clicked Send through the Mac phone preview. This is iOS acceptance, not delivery verification and not an autonomous phone-engine send. Do not send another Hello as a retry. Remaining messaging work: native Send-button recognition/dispatch, contact resolution for normal chat commands, and wiring the tested single-send journal into runtime persistence. The installed exact `Draft text … at +…: …` command only prepares the composer.

`hitapp` is the product name for a native iPhone assistant that users can summon from anywhere, give visual context to, and trust with approved actions.

Naming decision (2026-10-18): use **hitapp** for the product and installed app. The naming migration above supersedes the earlier roadmap-only decision. Source identifiers and the project directory remain **PocketAgent** for compatibility; historical test evidence below retains the labels present at the time. The existing user-created shortcut name “Pocket Voice” was not changed by this update.

## Product promise

Ask naturally. Let the agent inspect an explicitly allowed app and carry out a supervised, approved screen action on your own iPhone.

The owner requests HeyClicky's floating buddy/cursor and nearby conversation UI for Tapp, alongside screen assistance: inspect the requested screen, explain it, point at an observed control, carry out an authorized operation, and inspect the result. Cross-app display on the physical iPhone with AssistiveTouch OFF is the required research outcome. The existing in-app annotated capture remains only the current implementation; it does not satisfy that Tapp requirement.

The current priority is a personal developer-installed screen-control prototype using the native Swift CoreDevice engine. The old iCTRL/XCTest runner is retained only as an explicit legacy fallback, not used by the agent. This is distinct from a normal App Store assistant. The interaction is:

1. **Summon** — Action button, Siri, Control Center, Lock Screen, Share Sheet, or the app.
2. **Understand** — voice, text, screenshot, link, document, or selected content.
3. **Propose** — answer, instructions, or a concrete action preview.
4. **Approve** — require explicit confirmation for external or sensitive changes.
5. **Execute** — a bounded, approved native screen operation, or an explicitly authorized API tool.
6. **Report** — an in-app result, notification, or Live Activity.

## MVP: prove the interaction

The first internal build should do five things unusually well:

- Open instantly and accept speech or text.
- Accept a screenshot and understand its visible text.
- Explain an unfamiliar screen with short, numbered guidance.
- Create an Apple Reminder only after showing an approval card.
- Preserve a clear, conversational task history.

Already implemented:

- SwiftUI conversation interface
- Push-to-talk transcription
- Screenshot picker with local Vision OCR
- Provider-independent Swift agent runtime
- OpenAI-compatible model connection and Keychain storage
- Tool-call approval boundary
- Current-time and Reminders tools
- Siri and Shortcuts App Intent
- Demo mode and portable core tests

## Next build sequence

### Planned: “Hi Tapp” voice activation — 2026-10-19

Owner request: say **“Hi Tapp”** to activate hitapp while it is in the background. **Roadmap item only; not implemented or verified on the physical phone.**

- Start with user-configured iOS **Vocal Shortcuts**. Add setup guidance for Settings → Accessibility → Vocal Shortcuts, training “Hi Tapp” and assigning a Siri request such as “Open hitapp” or the appropriate hitapp shortcut. iOS performs phrase recognition on-device; the user completes setup in Settings.
- Reuse the existing App Intent entry points. Verify the open-app route first, then connect the phrase to a “Start Tapp” action using the existing voice/conversation flow. Preserve the distinction between opening the composer and starting a conversation without an app switch.
- Verify on the physical iPhone Air from Home and another app with hitapp backgrounded. Separately test locked/unlocked, suspended, cold-launch and force-quit states; record unlock requirements and failures rather than assuming equivalent support. Check phrase recognition, time to response, accidental activation, cancellation and disabling the shortcut.
- Keep an app-owned “Hi Tapp” detector, such as Porcupine, as a later feasibility investigation. It requires an active microphone session and evidence for background lifetime, interruptions and battery impact. Background audio must have a legitimate intended use; do not promise Siri-like always-on availability or automatic foreground presentation. This does not change the version-1 non-goal of app-owned always-on microphone monitoring.

Exit condition: the configured phrase reliably activates the intended hitapp entry point from the background on the physical phone, with documented lock/lifecycle limits and clear user setup and disable instructions. Activation alone does not authorize screen capture or actions.

References: [Apple Vocal Shortcuts](https://support.apple.com/guide/iphone/use-vocal-shortcuts-iph7f242ea2c/ios), [App Intents](https://developer.apple.com/documentation/appintents/app-intents), [Siri shortcut lock behaviour](https://support.apple.com/guide/shortcuts/run-shortcuts-with-siri-apd07c25bb38/ios), [background recording](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/record), [background-service review rules](https://developer.apple.com/app-store/review/guidelines/#software-requirements), [Porcupine iOS SDK](https://picovoice.ai/docs/quick-start/porcupine-ios/).

### Product direction: Siri-first hitapp

Target interaction: **Siri or Action button → spoken request → review/approval → bounded native action → spoken result**. Keep the app as setup, history and diagnostics, not a compulsory stop for every conversation. Preserve the Dynamic Island hand during actual control/capture, and never restart XCTest as a fallback.

Delivery gates:

1. Route “Ask” to the background conversation intent; reserve “Open” for the foreground composer. Finish the Dictate Text → model answer → visible/spoken result shortcut and Action-button mapping.
2. Verify actual speech, a visible or spoken reply, cancellation, lock handling, cold launch and offline errors on the physical phone. A typed system-card test is not a microphone test.
3. Verify each existing native navigation action independently. Then prototype an explicit system-surface action approval using the same scoped executor. The current voice intent is conversation-only; background execution and screen ownership must be proven before removing the foreground requirement.
4. Add task-local screen context and memory without making old observations authoritative or carrying approvals into a new request.

Background workstream: the separate agent completed `TaskMemory.swift` and 12 passing synthetic tests (strict concurrency and warnings-as-errors). Parent reviewed the implementation. It is opt-in, scoped, bounded, expiring in-memory history only; no capture, persistence, Xcode/app/model/device integration or new phone permissions. Expiration is enforced on access, so future integration must explicitly forget at task end, lock or scope loss. Returned copies cannot be recalled. Memory never grants action authority or replaces a fresh observation.

### Owner requirement: always-visible real cursor

The owner explicitly rejected a session-only interpretation: **the real cursor must remain visible across apps and between tasks, and park in the middle of the display when idle**. A temporary lab cursor, the AssistiveTouch floating button, an in-app drawn cursor, or a timed pointer session does not satisfy this. Preserve the Dynamic Island hand and never restore the XCTest Automation Running screen. Always visible does not authorize unattended clicks, sensitive actions, capture or lock-screen interaction.

This is not implemented or proven. The current pointer experiment creates and removes a temporary device, depends on authenticated media and a finite local route, and stops when its foreground page is left. Audit persistence through app backgrounding, pointer auto-hide, cursor-position feedback across apps, idle recentering, sleep/reboot recovery, explicit user stop and battery use before promising continuous operation. A separate read-only agent review is in progress. Do not weaken session limits or silently hold capture open to simulate completion.

### Navigation permission simplification (separate from cursor visibility)

At the owner's request, exact user-entered Home/App Switcher/one-page commands can use an explicitly started five-minute, ten-attempt navigation session without a new card or model round trip. Compound/ambiguous requests and model-proposed actions still use the existing approval path. This is not an always-visible cursor implementation, a blanket permission grant, or a bypass for Apple permissions. Installed build sequence 3632 removes the unnecessary geometry requirement from the fixed Home button event; only the App Switcher edge swipe still needs detected or measured bottom geometry. Two direct Home runs completed with the Mac preview disconnected. The app-owned first result capture showed Home; the owner confirmed the repeat returned Home with the hand visible and no Automation Running. No extra approval card or model round trip. App Switcher, page gestures and Siri-driven navigation remain pending. Core validation: 113 tests in 12 suites; signed build and code-sign verification passed. Cursor implementation is being handled separately by the owner's other agent; this work changed only navigation behavior.

### Current priority: voice without an app switch

Owner rejected the initial foreground dictation shortcut and requested a Siri-like interaction. The background-only intent receives system text, asks for confirmation, and returns a model answer/dialog. “Ask Pocket Agent” now routes to this background action; “Open Pocket Agent” alone opens the composer. A physical typed-input test displayed request and confirmation over Home without opening the app, but the final reply and microphone path remain unverified. `Pocket Voice` exists with Dictate Text (On Tap) → Dictate to Pocket Agent, using Dictated Text as Request. Explicit Show Result and the custom Action-button remap are pending. Voice exposes no screen tools or queued actions. The owner separately approved permanent AssistiveTouch ON with Dwell Control OFF; both were verified. Do not restore it OFF after ordinary tests unless asked.

Navigation demo regression and fix: two approved Home edge swipes failed physically, including one without the Mac preview. A detector-only follow-up stopped before input because the Home indicator was hidden. The replacement now uses a fixed native Home button event without requiring coordinates, verifies that the app backgrounds and captures the result locally. Home has passed physically as recorded above; App Switcher's edge swipe still requires observed/measured geometry. Model guidance distinguishes Home scope from app-scoped screen permission. No XCTest fallback or arbitrary button control was added.

### Next phase requested: live screen context and memory (not enabled)

After the voice flow is stable, add explicitly started, bounded capture sessions using the existing native screenshot route, local OCR, capture-age markers and an obvious stop control. The hand indicator must reflect actual capture/control activity. No ambient always-on recording, silent extension of sessions, or implicit expansion of the allowed app. Stop on lock or loss of scope; do not promise that OCR can reliably identify every sensitive screen.

Use a short-lived in-memory screen/event buffer for the current task: observations, proposed actions, approvals, execution results and uncertainty. Re-read before every input rather than using memory as live screen truth. Raw pixels are not saved by default or uploaded to the model automatically. Any retention duration, cross-app capture or transmission beyond the existing consent needs an explicit choice.

Long-term memory should be separate and opt-in: user-reviewed preferences and successful workflow summaries, stored locally with device data protection, provenance and dates. Provide inspect/edit/delete, pause, forget this session and clear all controls. Never treat remembered instructions as approval to act. Exclude passwords/tokens and avoid saving message/payment/health details by default; detection is best-effort and must not be represented as a guarantee. No new recording or durable memory collection was started by this planning request.

### Later milestone: remove the AssistiveTouch dependency

The owner reiterated that AssistiveTouch is temporary. Leave it enabled for current tests, but investigate a pointer/input path that works with AssistiveTouch OFF. Hiding the accessibility menu is not completion. Acceptance requires independent physical proof of visible movement, deliberate input and stop/cleanup with AssistiveTouch off, retained hand activity, and no XCTest Automation Running screen. Start with an in-app custom pointer and separately assess cross-app feasibility; do not imply that an in-app cursor proves a global overlay. If the current engine cannot meet this without a different supported mechanism, report that constraint rather than silently turning accessibility back on.

**Reverse-engineering update (2026-10-18):** inspected Apple's actual `assistivetouchd` binaries from installed iOS 27.0/27.1 simulator runtimes, including ARM64 branches and embedded entitlement declarations. Both contain a feature-gated **Pointer Control path separate from the AssistiveTouch-enabled check**. This is a concrete lead for an AssistiveTouch-off test using the existing 17-byte native mouse engine, not physical proof on the project's iOS 27.2 phone. Prior AssistiveTouch-on passes establish the working baseline; they do not establish that every iOS pointer path requires AssistiveTouch. Apple's global window hosting and pointer repositioning use private privileges absent from our signed app, so rebuilding the visual menu does not establish a custom cross-app renderer. See the [research report, reproducible inspector and binary evidence](docs/research/assistivetouch-2026-10-18/README.md).

Next gates for this workstream:

1. Inspect the exact phone build's separate Pointer Control options; compare bounded native motion with AssistiveTouch on, off, and off with Pointer Control enabled if available. Keep Dwell off and restore the owner's AssistiveTouch-on baseline after an arranged temporary off test.
2. If off-state movement succeeds, independently prove a deliberate approved input and stop/owned-device/media cleanup, with the hand visible and no XCTest. The current mouse probe is motion-only; native touch input and mouse-button support are separate results.
3. Prove cross-app position feedback, idle visibility with auto-hide configured, centring, background/route lifetime, lock handling and battery use in a dedicated bounded experiment. Do not remove the existing foreground guard or timers to claim persistence.
4. Keep custom cursor artwork over other apps as a separate unresolved capability. An Apple-rendered pointer with AssistiveTouch off could remove the toggle dependency without granting hitapp its own global renderer.

Research changed no runtime code, phone settings, permissions or installed app. Always-visible cross-app completion remains unproven.

**Main-agent handoff (owner requested, 2026-10-18):** the owner will have the main agent run the physical test. Start with the [execution handoff and results checklist](docs/research/assistivetouch-2026-10-18/README.md#main-agent-execution-handoff). All research and the reproducible inspector are saved locally. Physical cases A/B/C are pending; no runtime patch or phone test was performed by this research chat.

**Tapp isolated simulator lab (2026-10-18):** the owner named the cursor **Tapp** and requested further Xcode work on a separate iPhone Air. Added standalone [TappLab](DeveloperTools/TappLab/README.md), opened in Xcode with its own iOS 27.0 iPhone Air simulator (`07758927-591E-4941-8DED-C9ADD1369A99`); iOS 27.1 rejected that simulator device type. App-owned motion preview supports four-target travel, exact centre parking, Stop and scene/layout cancellation. Five Mac unit tests and the simulator build passed; the simulator UI verified four arrivals, return to centre, manual Stop and scene-inactive cancellation. Read-only private getters report Pointer Control and its feature gate **off**; this simulator's Accessibility UI omits Touch/Pointer Control options. This is a new runtime observation, not a physical-device conclusion. No system hover was observed, no HID input was injected, and no cross-app cursor was demonstrated. Main app runtime code and physical phone settings were not changed. The physical A/B/C handoff remains pending.

### Current request: visible agent-controlled mouse

Latest implementation: added an approval-gated model-selected inert-target phase to the existing pointer lab, plus on-device dictation with review-before-send, an explicit **Dictate to Pocket Agent** shortcut, and a separate opt-in `phone_navigate` tool for Home, App Switcher and one Home-page swipe left/right. New model proposal tests and real Ollama command-mapping tests pass without physical phone contact. Native report encoding tests and signed builds pass. The owner then explicitly requested Action-button mapping: changed Voice Memo to Pocket Agent's **Dictate request** and visually verified Settings. No microphone or AssistiveTouch setting was changed. Physical single-target arrival, navigation gestures, actual microphone/shortcut execution and cable-free use remain pending. Mac Ollama remains the inference provider; no claim of fully phone-only operation. See README for the exact consent flow and limitations.

The owner clarified the eventual interaction: **Action button → dictate a request → agent-controlled visible pointer/actions**, retaining the Dynamic Island hand and no XCTest Automation Running screen. They want to remove the AssistiveTouch dependency eventually, not merely hide its menu. A custom cursor inside Pocket Agent is feasible; a custom cursor/companion over arbitrary other apps without accessibility support remains unproven and is not promised by the current engine.

Phone-only roadmap (not implemented): keep the Swift executor and Vision OCR on-device; connect the existing App Intent entry point to explicit voice capture; require supported on-device speech recognition with no network fallback; replace the Mac Ollama provider with an explicitly on-device Foundation Models session or a small locally downloaded open-weight model through MLX Swift. Preserve the same approval/scoping boundary and test model reliability, peak memory, heat and battery on the iPhone Air. Apple Foundation Models is not open-weight. No cloud/Private Cloud Compute fallback in a local-only mode. Initial model downloads and developer installation can still require a network/Mac; offline runtime must be tested separately from setup. Calling Gmail/Spotify/etc. online APIs still requires internet even if inference is local. The developer-service control route is experimental and does not establish App Store compatibility or indefinite background execution.

References: [Apple on-device Foundation Models](https://developer.apple.com/foundation-models-framework/), [MLX Swift iOS examples](https://github.com/ml-explore/mlx-swift-examples), [on-device speech requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition), and [Action button shortcuts](https://support.apple.com/en-ie/guide/iphone/iphe89d61d66/ios).

The owner clarified that a visible moving cursor/companion is part of the desired experience. A Swift motion-only virtual mouse experiment is now built separately from normal chat tools. It creates its own descriptor/identity, verifies registration, sends a bounded relative path while Pocket Agent remains active, and verifies removal; no mouse buttons, touchscreen contacts, model request or XCTest launch are involved. The test page deliberately draws no fake cursor. The existing hand Live Activity is reused.

The owner approved temporarily enabling AssistiveTouch, then restoring it. Dwell Control stayed off. Initial product-label checks blocked motion because iOS rewrites both labels. The final verifier uses the absent-before, echoed, unique ID plus exact descriptor and mouse usage. The physical retest sent all 80 motion reports with the Mac preview disconnected and XCTest stopped, verified temporary-mouse removal and completed own-media cleanup. **The owner reported “Pointer didnt move”: visible movement failed despite successful protocol dispatch.** A requested follow-up successfully opened Settings through the native engine (not a mouse click), with the hand icon visible in the preview. AssistiveTouch was then restored off and verified. Nine pointer tests plus seven native regression tests pass; prior core suite reported 70 tests passed. See README for metadata evidence.

**Subsequent fix and physical pass:** the old generic six-byte report was incompatible with CoreDevice's native 17-byte PointerReport. After correcting signed X/Y offsets and zeroed button/modifier fields, the owner confirmed “Pointer moved; hand visible; no Automation Running” with the Mac preview disconnected. Own mouse/media cleanup passed; AssistiveTouch was restored off and verified. Metadata: `pointer-native-format-20261018.txt` under `DerivedData/NativeControlV2`.

The owner then requested much greater acceleration, a longer test and screen capture for localisation. Implemented Fast/Turbo software ramps, 10/30/45-second windows (30 default), bounded 50 Hz motion, local periodic screenshots/OCR and app-only hover feedback toward inert targets. Stop remains fixed on screen; no fake live cursor or clicks. Last-capture annotations are labelled as observations. Twenty targeted tests and 35 core regression tests passed at that baseline. **The approved 30-second Fast test then completed on the physical phone with Mac preview disconnected:** 1,144 reports, nine captures, real hover delivery, 317 feedback steering commands and four target arrivals. Raw capture includes the actual system cursor. Own mouse/media cleanup passed; XCTest stayed stopped and AssistiveTouch was restored off. Evidence: `DerivedData/NativeControlV2/pointer-fast-30s-20261018.txt` and `.png`. The owner confirmed “Yes—hand visible, no Automation Running”. Precision/repeatability, arbitrary-app localisation and end-to-end physical verification of the new dictation/agent-target flow remain unfinished.

### Current update: native agent integration and app/API inventory

Screenshot capture is fixed and verified inside the physical iPhone app, with a returned local Settings preview. Chat now targets the native engine for read/point/tap/swipe, preserves per-step approval and the app-owned Dynamic Island icon, and never starts XCTest automatically. Native typing remains unavailable. The latest signed build is installed. The old helper was verified stopped. A new authenticated, certificate-validated home-Wi-Fi route avoids the local-VPN/Tailscale model conflict; nine gateway checks and two live model tests passed. The live native-agent test uses synthetic OCR, not the physical phone.

Remaining before PA-009 can be called complete for ordinary use: physical chat read/result round trip, native Settings navigation tap/swipe with fresh screenshot verification, owner confirmation of physical overlay absence during those integrated actions, and disconnect/expiry recovery. Phone testing is paused while the owner is using the phone. Existing independent native input/overlay proof remains valid, but does not replace these integrated tests. OCR is not a foreground-app/hittability guarantee; keep the device untouched during each operation.

Owner requested an installed-app scan to identify API candidates. Read only app names/bundle IDs using the developer-device inventory; no account contents or tokens were inspected. Promising installed candidates include Apple Calendar/Reminders, Google Calendar, Gmail, Todoist, Slack, GitHub, Spotify and Sonos. No new accounts were connected and no OAuth permissions granted.

Recommended first wave (proposed, not implemented):

- Calendar/Reminders via [Apple EventKit](https://developer.apple.com/documentation/eventkit), subject to explicit iOS data-access permission. A reminder-creation tool already exists; broader calendar/task access does not.
- Todoist tasks/projects via the [official API](https://developer.todoist.com/api/v1/), with separately approved credentials/scopes.
- [Gmail](https://developers.google.com/workspace/gmail/api/guides) and [Google Calendar](https://developers.google.com/workspace/calendar/api/guides/overview), starting with scoped read access and separately approved mutations.

Use the same AgentTool approval boundary for connectors. Keep credentials in Keychain, expose explicit operations instead of arbitrary model-supplied URLs, treat returned text as untrusted, and avoid duplicated writes on retries. Installation on the phone is not authorization to access an account or evidence that its full feature set is available through an API.

### Priority milestone — Prove real screen control

Implemented in source:

- A pinned iCTRL developer-tool checkout and reproducible build preflight
- Loopback-only Swift encrypted client with device-approved pairing and Keychain credentials
- Screen Control diagnostics and manual screenshot/tree previews
- Scoped screen-read, label-tap, swipe and text-entry agent tools
- Approval of every screen tool, stale-screen checks, cancellation and no automatic gesture replay
- Finite background completion allowance; return to Pocket Agent after each operation
- Guide me / Act with approval modes, with write operations blocked in code in Guide me mode
- `screen_point` resolves a unique observed label and optional observed control type, then marks its measured bounds on a captured image without tapping
- Local screenshot cards shared by manual and agent operations; image bytes stay local, while approved screen text goes to the model
- Enlarged captured-screen previews, capture age, expired-observation messaging, and fail-closed geometry/change checks
- An isolated simulator UI-test project using the pinned iCTRL dispatcher, without modifying the upstream checkout

Verified: Xcode is installed and selected; simulator and developer-signed iPhone builds compile; the app runs on iPhone Air in the simulator and is installed and visually verified on Jack’s physical iPhone Air (iOS 27.2). The physical app passed its live gpt-oss:20b connection test over private Tailscale HTTPS, and its provider settings were saved. Local gpt-oss:20b also answers and calls Swift tools through Ollama in the simulator. A real simulator test through the pinned iCTRL dispatcher and production controller reads Settings, locates/captures General for highlighting, verifies guide-only refusal, taps General in action mode, verifies About appears, and returns to Pocket Agent. This test does not validate network pairing or physical-device screen control.

Physical setup update: the signed runner and companion were installed. Screen Control is optional in Pocket Agent Settings, off by default, with in-app helper start, pairing/check, scoped enablement, and a confirmation before shutdown. In-app Start launched the loopback-only helper and returned to Pocket Agent. Device-approved encrypted pairing and authenticated Check now pass on the physical phone. A model-requested, explicitly approved Settings read captured the real VPN page, returned to Pocket Agent and produced an Ollama answer. This proves read-and-return, not a physical-phone tap. The separate companion UI is optional, but a separate test-runner process is still required by this implementation.

Remaining: verify physical-phone Settings → General tap/return, suspension/cancellation, disconnect and reboot recovery. Physical General highlighting, helper shutdown/process exit, restart with retained pairing, and authenticated Check passed. The helper-owned Dynamic Island icon appeared on the phone and disappeared on shutdown. All 50 core tests, including four live Ollama tests, passed on 2026-10-18 after adding the iPhone operating guide. Core tests and simulator actions do not establish physical-phone gesture compatibility.

Exit condition: a screen is read, a harmless control tapped, and the resulting screen verified on the actual iPhone without a model. Then repeat using an explicitly approved model tool call.

### Device test findings — 2026-10-18

Keep this register current while testing. “Fixed” requires a check on the actual phone; usability work and unverified behaviour are not counted as resolved bugs.

| ID | Priority / status | Finding and evidence | Acceptance check |
| --- | --- | --- | --- |
| PA-011 | P2 · presentation fixed on phone | The visible-pointer full-screen modal disappeared before a test could start. Replaced it with navigation in the existing stack and an explicit alert; the physical phone now retains the page through connection/registration. Added stage/reason cancellation diagnostics. | Page remains open during bounded motion; leaving it or backgrounding still cancels. Do not remove foreground safeguards. |
| PA-012 | Fixed · physical movement verified | The generic six-byte report was incompatible with Apple's native 17-byte PointerReport. Corrected signed X/Y offsets; no buttons/modifiers. Owner confirmed pointer movement, hand visible and no Automation Running with Mac preview disconnected. Own mouse/media cleanup and AssistiveTouch-off restoration verified. | Preserve this baseline. Faster/longer tests and closed-loop targeting require separate physical verification. |
| PA-013 | Physical Fast test passed · follow-up tuning | 30-second test: 1,144 reports, nine captures, actual iOS hover events, 317 feedback steering commands, four target arrivals. Raw screenshot includes cursor. Owner confirmed hand visible and no Automation Running. Own mouse/media cleanup passed, no XCTest process, AssistiveTouch restored off. | Validate unplugged operation, precision, repeatability, cancellation and other speeds before agent integration. Cross-app localisation and reboot startup remain unproven. |
| PA-001 | P1 · fixed on phone | In the Screen Control Form, tapping Check also invoked Pair again. Both buttons inherited the row's automatic button style, causing unwanted pairing requests. Added `.buttonStyle(.borderless)` to their HStack. Rebuilt and installed; Check returned `Connected to iCTRL 1.98.12` without a new auth request. | Check sends only authenticated `device_info`; Pair remains a separate explicit action. Add a UI regression test; portable unit tests do not exercise SwiftUI hit handling. |
| PA-002 | P1 · open UX | Setup requires Start → notification/passcode → Pair → notification → Check → choose mode/app → enable. User repeatedly needed help and expected one integrated experience. | One guided setup entry point with visible prerequisite stages, authenticated readiness, and clear next action. Preserve device approval and per-action consent. Never auto-pair, auto-approve or replay gestures. |
| PA-003 | P1 · open UX | The first pairing expired before approval reached the runner. Upstream allows about 60 seconds; the app only shows a static waiting message. A late tap did not pair the app. | Show countdown/expired state and explain long-press → Allow. Retry only on explicit user request. Do not weaken or bypass the runner's approval. |
| PA-004 | P1 · investigate / open UX | Pairing survived but the helper became unreachable. Runner log records `willTerminate` at 14:12:06; cause is not established. Restart required an iOS “Enable UI Automation” passcode prompt. | Distinguish paired from running, foreground-authorization-required, unavailable and ready. Preserve keys across helper restarts. Verify stop/start and reboot recovery; never claim a launch callback proves readiness. |
| PA-005 | P2 · open UX | The Screen Control form is very long. Manual read and targeting controls sit below setup text and require substantial scrolling. Device Hub scrolling also overshot; this alone is not proof of a native app scroll defect. | Put the current state and primary action first; collapse advanced setup/diagnostics and move manual tests into a focused view. Keep Stop reachable. |
| PA-006 | P1 · open product clarity | The user expected the apps to be merged. Controls are integrated, but the developer test runner remains a separate installed process; the companion UI is optional. Technical labels and separate icons obscure that distinction. | Pocket Agent is the normal entry point and manages the helper lifecycle. Explain the remaining developer helper once during setup. Do not claim a single binary, silently delete companion apps, or hide required iOS permissions. |
| PA-007 | P2 · open UX | Provider onboarding required manually entering a private HTTPS URL, model name and gateway key. The gateway and Ollama also need the Mac awake and are not configured for automatic login startup. | Guided private-Mac connection setup with explicit key handling and clear offline/restart status. No public exposure or embedded secret. Autostart needs an explicit product decision. |
| PA-008 | P2 · observed / open UX | After capture returned, the chat still said “Working on your approved action” while waiting on the model. The captured card and conversation layout made the next status harder to find. | Separate capturing/returning/thinking stages, show one clear latest result, and keep the next approval visible. Preserve a truthful distinction between captured preview and live screen. |
| PA-009 | P1 · current-architecture blocker | User sees the iOS “Automation Running” overlay on the physical phone while other apps run. It is excluded from mirrored screenshots, so it was initially misidentified as the runner startup shell. The Dynamic Island icon does not replace this XCTest system overlay. User clarified that stopping control or substituting Mac remote control does not meet the requirement. A physical tap did not fade the overlay on this phone. Original runner is active again with authenticated connection verified; no overlay-removal patch installed. | Keep the Dynamic Island icon and functioning on-phone control. Do not stop the helper as an overlay-removal workaround. Removal remains unimplemented and must be verified on the physical display with control still working. Do not suppress passcode/authorization prompts. [Primary implementation documentation](https://github.com/appium/appium-xcuitest-driver/blob/master/docs/troubleshooting/index.md). |
| PA-010 | P2 · guidance improved / partial verification | Model initially described General and offered a later highlight despite the request. A follow-up produced a real approved `screen_point` and a correctly outlined General preview. Added a system-level iPhone operating guide covering exact observations, navigation, typing/swipes, limits, verification and consent. | New live-model test requests `screen_point` with the exact randomized observation ID after a synthetic read; passed. The updated guide is installed, but a fresh end-to-end physical highlight with that new prompt remains untested. Prompting does not replace controller enforcement. |

Verified physical-phone evidence: read-and-return in `DerivedData/Phone/runner-screen-test.log`; observed General lookup/capture/return without a tap in `runner-highlight-test.log`; ActivityKit startup and listener readiness in `runner-island-test.log`; authenticated shutdown and normal process exit in `runner-island-stop-test.log` (all under the same directory). The outline was visually checked on the captured General button. The compact icon was visually checked while the helper ran and after shutdown; stale/crash behavior and Lock Screen/expanded layout are not yet verified on device. No payment, message send, deletion, VPN change or other consequential action was used. Physical automated tap remains pending. Following the user's clarification, the original runner is running again and Settings-only Act with approval is enabled; authenticated Check returned iCTRL 1.98.12. Per-operation approval remains required. The user reports the system overlay persists after a physical tap. Leave the helper running rather than treating shutdown as a fix.

Native replacement investigation (2026-10-18): new user-approved developer identity is paired and reverified. The Debug app includes a read-only native-connection check, not a replacement input engine. Swift direct-network authentication works from the Mac and advertises Universal HID/app services; the same credentials/protocol are reset when used from the phone to itself. Current runner and island remain running. A local-only VPN route is the next candidate, but it may disconnect Tailscale/model access and has not been enabled or separately approved. PA-009 remains unresolved; do not claim the system notice is removed. See README's native-control experiment section for reproducible evidence and credential locations (never log key contents). The app update resets its Screen Control opt-in to off, as designed.

Follow-up: user approved building/testing the temporary local VPN route. The signed Swift `PocketControlTunnel` extension is now embedded in Pocket Agent, with a single-peer route, strict packet filtering, no logging, a two-minute expiry and Start/Verify/Stop UI. Four packet tests and four capability/deadline tests pass. The full core suite reports 54 tests with four live-model tests skipped. On-phone VPN permission, native authentication through this route, independent HID input, Dynamic Island ownership migration and physical overlay absence still need verification. Do not mark PA-009 fixed on a successful build or merely connected VPN. Tailscale must be reconnected after the test; stopping this extension alone does not restore it.

Local-route UI verification: the nested test sheet dismissed itself and its parent before Start could be used. Replaced it with a navigation destination within Screen Control, rebuilt and reinstalled successfully, and verified the panel remains open on the physical phone. Start now presents the genuine iOS “Pocket Agent Would Like to Add VPN Configurations” prompt. Handed permission/passcode entry to the user; no approval or native-service test performed by the agent at this point. Existing runner hand icon remains visible.

Physical test result (2026-10-18, following VPN approval): local route connected; Pocket Agent authenticated directly from this iPhone and discovered touch/app/display/screencapture services. Read-only admission test passed. Saved `DerivedData/NativeControlV2/local-route-success-20261018.txt`. Local route then stopped explicitly and Tailscale reconnected. Current runner and Dynamic Island untouched. Next required work is an independent, consent-gated native media/HID input engine, followed by actual controlled input with XCTest stopped and physical confirmation of no Automation Running overlay. Connection success alone does not satisfy PA-009.

**Latest native-engine result (2026-10-18, supersedes earlier connection-only status):** installed Swift CoreDevice engine + Pocket Agent-owned Live Activity. Three real proof-button taps passed; the latter two ran with the XCTest runner stopped and the Mac's phone preview disconnected. The final retest recorded 0 → 1, 220 video datagrams, and own-stream cleanup (`DerivedData/NativeControlV2/native-retest-20261018.txt`). Native Settings launch passed. After an initial negative report, the old runner was discovered active again and shut down through authenticated control. On the isolated retest the owner confirmed: “The screen is gone; hand icon is visible.” The required physical-display behavior is therefore verified for the bounded native prototype. PA-009 remains open for normal-agent integration, not because the native input/overlay experiment failed. Existing chat `screen_*` tools still target iCTRL. Screenshot capture still fails after transport fixes; native accessibility/typing/swipes, background lifetime, and local-VPN/Tailscale coexistence remain unfinished. Legacy Start now warns explicitly that it brings back Automation Running and is blocked during a native test. Both engines are stopped after testing, fallback installation/pairing retained, and Tailscale restored with a successful ping.

### Milestone 1 — Run on iPhone

- Install/select Xcode and an iOS simulator runtime.
- Set the Apple development team and unique bundle identifier.
- Compile in the simulator, repair platform-specific warnings, and verify permissions.
- Physical installation and launch are complete. Test microphone, OCR, Reminders, Siri, and Shortcuts on the phone; investigate the signed build's non-fatal SSU artifact archive error if shortcut discovery fails.
- Add a basic app icon and launch presentation.

Exit condition: a spoken request and a screenshot-guidance request both work on a real iPhone.

### Milestone 2 — Make it available from anywhere

- Add a Share extension for images, links, text, and documents.
- Add Lock Screen and Control Center launch controls.
- Add an App Shortcut suitable for the Action button.
- Add “Hi Tapp” activation through user-configured Vocal Shortcuts and the existing App Intent entry points; complete the physical-device checks in the planned voice-activation workstream above.
- Accept screenshots directly from the system Share Sheet.
- Return users to the originating app through a safe deep link when available.

Exit condition: users can invoke hitapp without hunting for its app icon.

### Milestone 3 — Useful Apple-native tools

- Calendar availability and event creation
- Reminder search, completion, and creation
- Contacts lookup with narrowly scoped access
- Maps search and directions handoff
- Draft email and message content without silently sending it
- Configurable Shortcuts execution

Every write-capable tool receives an approval policy: never, once per action, or always.

Exit condition: the assistant reliably completes three recurring daily workflows.

### Milestone 4 — Durable background work

- Add a Swift Vapor service for long-running research and integrations.
- Create a persisted task state machine: queued, running, awaiting approval, completed, failed, or cancelled.
- Add APNs notifications and Live Activity progress.
- Keep provider credentials server-side where appropriate.
- Synchronize non-sensitive task history while retaining local deletion controls.

Exit condition: a task survives the app being closed and reports a trustworthy result later.

### Milestone 5 — Screen guidance

- Improve OCR with layout and bounding-box preservation.
- Return annotated screenshot overlays showing what to tap.
- Add visual-model analysis for screens that cannot be understood through OCR alone.
- Evaluate user-initiated live screen capture only on supported iOS versions.
- Extend verified screen control to unlabelled controls only after reliable visual targeting and stale-frame validation are demonstrated.

Exit condition: common interface questions can be resolved in fewer than three exchanges.

## Swift architecture

### iPhone

- SwiftUI and Observation for presentation
- Swift concurrency and actors for task orchestration
- App Intents for Siri, Shortcuts, controls, and Action button
- Vision for local OCR and layout extraction
- Speech and AVFoundation for voice
- EventKit, Contacts, MapKit, and supported system frameworks for tools
- SwiftData for local conversations and task metadata
- Keychain for device credentials
- ActivityKit and UserNotifications for progress

### Server, when needed

- Vapor or Hummingbird in Swift
- PostgreSQL for durable task state
- APNs for results and approval requests
- OAuth tokens encrypted at rest
- A queue with idempotent tool execution and auditable outcomes

The iPhone remains useful without the server. The server is introduced only for tasks that must outlive iOS foreground execution.

## Safety and privacy rules

- No passive or continuous screen capture.
- Process screenshot text locally before sending only the context needed by the model.
- Treat all content from screens, links, and documents as untrusted data.
- Never execute instructions discovered inside that content.
- Preview sends, purchases, deletions, account changes, and public actions.
- Store secrets in Keychain, never source code or UserDefaults.
- Log what tool ran and its outcome without logging secret values.
- Offer one control that deletes local conversation and task history.

## Explicit non-goals for version 1

- Unrestricted or unsupervised control across all iPhone apps
- Always-on microphone or screen monitoring
- Fully autonomous purchasing or messaging
- Replacing Siri at the operating-system level
- Running a large language model entirely on-device
- Supporting every model provider before the core experience is excellent

## Validation

Test with a small group using repeatable scenarios:

- “Explain this settings screen.”
- “Remind me about this tomorrow.”
- “What should I tap next?”
- “Turn this shared page into a short action list.”
- “Find a time for this and prepare a calendar event.”

Measure time to first useful response, task completion rate, approval clarity, corrections per task, and how often users successfully invoke the assistant outside its main app.

## Immediate decisions

1. Product name selected: **hitapp**. Installed-app and shortcut renaming remain a separate migration.
2. First model provider selected: local Ollama with gpt-oss:20b on the Mac. The user-approved Tailscale HTTPS gateway with an app access key passed a real Mac model request and nine authorization/route checks. The iPhone joined the tailnet, and Pocket Agent independently passed its live model connection test; endpoint, model and Keychain credential are saved. Neither Ollama nor its management API is exposed directly to the LAN or public internet.
3. Choose the three daily workflows the private beta must master.
4. Decide whether the first beta is personal-only or intended for TestFlight users.

## Design exploration — 2026-10-18

Research direction, not a completed redesign. Another agent reviewed public official product imagery; no branding or proprietary assets were copied. The user asked us to explore rather than supplied a fixed visual style.

| Reference | Useful idea for hitapp |
| --- | --- |
| [Raycast for iOS](https://www.raycast.com/ios) | Compact composer, voice and attachment access, and a clearly identified model. |
| [Claude for iPhone](https://apps.apple.com/us/app/claude-by-anthropic/id6473753684) | Quiet conversation canvas, readable answers, restrained navigation, and inline result previews. |
| [Perplexity for iPhone](https://apps.apple.com/us/app/perplexity-ai-search-chat/id1668000334) | Structured answer/result cards with an accessible follow-up composer. |
| [Apple Shortcuts](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-the-app-apd5ba077760/ios) | Explicit action steps, required input, cancellation, and result previews. |

Recommended combination: **Raycast's quick access, Claude's readability, and Shortcuts' visible action controls**, expressed with native SwiftUI rather than copied assets.

- A single chat-first screen, not an initial dashboard. Keep history/new conversation, title, and settings in the header; attachment, text, microphone, and send at the bottom.
- Show `gpt-oss:20b · On your Mac` for the simulator connection, with separate model and screen-controller states. Never suggest the model runs on the phone or that a model connection proves screen control works.
- Inline approval card: target app, exact proposed action, brief reason, optional fresh preview, specific action button, and Cancel. One approval authorizes one action.
- Compact activity states: Connecting, Thinking, Waiting for approval, Reading Settings, Completed, or Couldn't complete. Keep Stop reachable and show completion only after a verified result.
- System typography and symbols, Dynamic Type, generous spacing, automatic light/dark mode, neutral surfaces and a blue accent. Use labels and symbols in addition to amber approval/red failure colors.
- Keep ordinary connection errors contextual. [Apple's alert guidance](https://developer.apple.com/design/human-interface-guidelines/alerts) supports reserving modal alerts for important actionable interruptions.

Alternative to compare in a future mockup: a darker technical activity-console treatment. The native direction is the recommendation because this is a personal phone assistant, not a desktop developer console.
