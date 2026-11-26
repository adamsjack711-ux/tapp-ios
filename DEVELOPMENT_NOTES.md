# hitapp

## Phone update and cleanup — 2026-10-18

Installed the renamed **hitapp** build on Jack’s physical iPhone at device database sequence **3664**. Home Screen name, main UI, voice/Shortcuts labels, model self-description and native Live Activity text use hitapp. The bundle ID `com.jackadamslovell.PocketAgent`, signing team, Keychain identifiers, URL scheme `pocketagent`, App Intent types and native pairing identity remain unchanged for an in-place update. Existing `remote-pairing.plist` and preferences-file size/modification metadata were unchanged after installation. The Dynamic Island hand implementation remains intact.

After explicit owner confirmation, uninstalled **iCTRL** (`com.jackadamslovell.ictrl`) and **iCTRLUITests-Runner** (`com.jackadamslovell.ictrl.uitests.xctrunner`) and their app-local data. The device inventory now contains only hitapp among these three project apps. Legacy source/build materials remain on the Mac, but the deleted phone-local data was not backed up. Tailscale, unrelated apps and the other agent’s simulator were not changed. The native runner-stopped check inspects running processes and does not require the removed apps to be installed.

Verification: all **123 core tests in 13 suites** passed with strict concurrency and warnings as errors; signed iOS build and strict code-sign verification passed; device app inventory confirmed the new name and removals. The phone remained locked after installation, so this checkpoint does not claim a new physical UI, control, microphone or Dynamic Island run. No accessibility setting was changed. The existing inert cursor-click prototype remains experimental and was not run; this update does not establish mouse clicking or AssistiveTouch-off support. Its explicit closure capture was corrected during build preparation; no separate Tapp Lab experiment was installed.

Unlock follow-up: after the owner unlocked the phone, the device reported `passcodeRequired: false` and successfully launched the updated app. The development-app inventory again contained hitapp only. Device Hub remained on the other agent's Tapp Lab simulator and was not switched, so no new visual UI or phone-control verification is claimed from this launch check.

Earlier checkpoints below retain their original app labels and test conditions.

## Latest verified state — 2026-10-18, 18:13

- **Repeated access prompts:** the owner explicitly requested persistent access. This personal build restores native app scope/mode and navigation across launches, defaults the already-paired setup to Settings/Act automatically, and remembers an explicit Stop. No five-minute/ten-command navigation expiry remains in the app path. Reads, highlights, scrolling and a narrow list of Settings navigation rows use standing access. Unknown/consequential taps still require review; pairing, iOS permissions, stale-screen checks, Guide mode and app-scope enforcement remain intact. This is saved authorization, not continuous background execution or continuous recording.
- **Installed and tested:** signed build installed at device database sequence 3656. All 123 core tests passed with strict concurrency and warnings as errors. On relaunch the physical phone preview showed Screen Control already on. The in-app `Open Settings` command ran without an approval card and Settings was visually verified afterward. Native result: `DerivedData/NativeControlV2/navigation-standing-access-20261018.txt`. Mac preview was disconnected during native execution. Dynamic Island/native engine code remains in place; no legacy runner was started. No new physical-only Automation Running observation was claimed.
- **First message:** the local draft command prepared exactly one `Hello` for the user's selected Lalith. At 18:13 the owner explicitly requested clicking Send. Codex clicked the verified Send control **through the Mac phone preview**, and the on-phone MessageUI delegate reported `.sent` (accepted by iOS, not a delivery receipt). Do not repeat this send. This proves local draft preparation and system-composer submission, **not autonomous Send input from the phone engine**. Native Send recognition/dispatch, natural-language contact resolution and persisted runtime send-journal integration remain unfinished. Do not claim those features work.

The historical entries below describe earlier approval policies and tests; the current access behavior above supersedes their off-after-launch/per-step-approval descriptions.

Pocket Agent is a native SwiftUI iPhone assistant prototype with supervised, per-operation screen control. The agent now uses the on-phone Swift CoreDevice engine, not the separate iCTRL XCTest runner. Its transport dependencies include native C code. This remains a personal developer build, not an App Store compatibility claim.

## Dictation, navigation and agent targeting — 2026-10-18

- **Voice launch bug / Siri-like system flow:** `DictatePocketAgentIntent` now uses `openAppWhenRun = false` / `.background`, requires an unlock, confirms system-supplied text before model submission, and returns an answer and system dialog. The old pending-microphone launch path is removed. “Ask Pocket Agent” now routes to this background intent; only “Open Pocket Agent” opens the composer. The signed routing update was installed (device database sequence 3608), and both labels were visible in Spotlight. The earlier physical typed-input test showed request and confirmation over Home without foregrounding the app; an actual microphone test and final response card remain unverified.
- **Voice shortcut setup:** `Pocket Voice` exists with **Dictate Text (On Tap) → Dictate to Pocket Agent (Request = Dictated Text)**. Adding an explicit **Show Result** and mapping this custom shortcut to the Action button remain pending. Do not add Open App or Open Pocket Agent. iOS owns the dictation UI and its language/privacy settings; this differs from the strictly on-device in-app recognizer. Voice currently exposes **no tools or screen access**, does not queue/execute phone actions, uses the Mac model, and retains four turns in memory only. Phone actions still require opening the app and approving. iOS 18+ is required; older systems fail without launching.
- **Persistent pointer support:** the owner explicitly requested leaving AssistiveTouch enabled, with Dwell Control off. Both states were visually verified on the physical phone after this update; do **not** restore AssistiveTouch to off as part of ordinary test cleanup now. No tracking-sensitivity, payment-confirmation, always-running helper, or permission change was made. This setting is pointer support, not authorization for unattended movement/clicks.
- **Dictation:** tap the microphone labelled “Dictate request”, speak, stop, review/edit, then Send. Existing chat drafts are preserved as a prefix. The pointer lab also has a dictation button (explicitly replaces that test request). Recording stops after 60 seconds, when leaving the app, or when entering a different panel/action. Recognition requires an available on-device language; there is no server-audio fallback. Only reviewed text is sent to the configured model after Send. Audio is not stored by this app. Physical microphone/recognition testing is still pending.
- **Earlier Action button setup (superseded):** originally mapped Voice Memo to the foreground **Dictate request** App Shortcut. The owner rejected that app-opening interaction. Its stable intent identity now runs in the background, but automatic microphone capture needs the custom shortcut above.
- **Home navigation:** separately opt in at **Screen Control → Home navigation**, off after launch. Exact user-entered “Go Home”, “Open the App Switcher”, or “Swipe one Home Screen page left/right” commands run without another card during the five-minute, ten-attempt session; model-proposed actions still require approval. Page navigation explicitly returns Home first, then requires a best-effort English Home-layout observation before one sideways swipe. Unknown/hidden/localized Search affordances stop that second gesture. This is not proof of foreground-app identity. At page boundaries widgets or App Library may appear. No arbitrary coordinates, card taps, app closing, unlocks or XCTest. The result capture remains local and the phone is left at its destination; reopen Pocket Agent manually. **Return to Home has now passed on the physical phone; App Switcher and sideways page navigation remain unverified.**
- **Agent target:** the visible-pointer page now offers **Agent target / Loop test**. First approve a local read and proposal request; only the typed request and the four uniquely observed inert labels go to the configured model. Then separately approve movement to the selected label within 60 seconds. The grant is single-use, fresh local OCR is required, and movement stops on observed arrival within 14 points or the 30-second limit. No clicks. The previous loop diagnostic remains available. The native engine and app-owned hand activity are retained; no fallback to XCTest. **The integrated single-target physical test and unplugged operation are still pending.**
- **Navigation regression found in the live demo:** two approved Go Home attempts stayed in Pocket Agent, including a retry with the Mac preview disconnected before approval. The returned local capture also showed Pocket Agent. Do not count either as a pass. The model initially confused disabled app-scoped screen tools with separately enabled Home navigation; configuration guidance now separates the scopes, and the four-command live model regression passed without phone contact. The next build locally detects a contrasting bottom Home indicator in a fresh capture, fails closed if missing/ambiguous, sends a fixed native Home event instead of the failed edge drag, and rejects a result if the app never backgrounds. App Switcher uses the measured indicator height; its physical behavior remains unverified. No arbitrary hardware-button tool or XCTest fallback is exposed.
- Validation: the background-conversation live Ollama test passed separately. Home-navigation scope/recognizer tests and seven native wire tests pass. These establish proposal/encoding/detection behavior, not physical navigation success. Earlier pointer/native lifecycle tests and simulator checks remain historical baseline evidence; see ROADMAP for pending gates.

Native Home event protocol references: [pymobiledevice3 implementation](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/remote/core_device/hid_service.py) and [ipb's captured button protocol](https://github.com/ipbtools/ipb/blob/main/docs/protocol.md#hid-button). These describe an experimental developer-service route, not a public iOS API or App Store compatibility promise.

Latest follow-up (installed device database sequence **3632**): removed an unnecessary bottom-indicator requirement from the coordinate-free native Home event. Only the App Switcher edge swipe requires a detected indicator or measured own-app bottom safe area matched to a fresh screenshot. Fresh-screen, foreground, permission-prompt and legacy-runner checks remain. Failures now distinguish no navigation input from an attempted input with an uncertain outcome. **Two direct “Go Home” runs completed with the Mac preview disconnected before execution.** The first app-owned result capture visibly showed Home; on the repeat the owner confirmed “Returned Home; hand visible; no Automation Running”. Neither run required a second approval card or a model round trip. Status evidence: `DerivedData/NativeControlV2/navigation-home-button-20261018.txt` and `navigation-home-repeat-20261018.txt`. App Switcher, page navigation and voice-to-navigation remain pending. Attached screenshots, compound requests and model-generated calls cannot take the direct-command path; no iOS permission is bypassed. Full core validation passes **113 tests in 12 suites**, including the isolated memory agent's 12 tests, with strict concurrency and warnings-as-errors; nine opt-in live tests are skipped in this default run. Signed iPhone build and strict code-sign verification pass.

**Always-visible cursor requirement:** the owner clarified that the real pointer must stay visible across apps even when no task runs, centred when idle. This is not implemented. The bounded navigation session above is not a substitute. Current pointer code is a temporary foreground lab with timed native/media/route cleanup and app-only hover feedback; removing timers alone would not establish background persistence or reliable cross-app centering. The roadmap now uses the product name **hitapp**; installed UI and identifiers remain Pocket Agent.

The agent still uses Mac Ollama. On-device dictation and phone-side execution do not make inference phone-only. AssistiveTouch remains necessary for the previously verified visible-pointer experiment and is now left enabled at the owner's request. Return to Home uses a fixed native Home button event; App Switcher and page navigation use native touchscreen gestures, not the mouse. Home's physical pass does not validate the remaining flows.

Reference: Apple's [on-device recognition requirement](https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/requiresondevicerecognition) and [App Switcher gesture](https://support.apple.com/en-hk/guide/iphone/iph1a1f981ad/27/ios/27).

## Visible mouse experiment — 2026-10-18

The owner wants a visible cursor/companion moving on the actual iPhone screen, eventually controlled by Action-button dictation without AssistiveTouch. **Physical movement now passed:** after the native report-format fix, the owner confirmed “Pointer moved; hand visible; no Automation Running.” The Mac preview was disconnected during that 80-report test. This is still a movement-only diagnostic, not an agent mouse-click tool. AssistiveTouch was restored off and verified in Settings afterward; Dwell Control and global tracking sensitivity were left unchanged.

- Read-only native inventory succeeded on the paired iPhone. It exposes touchscreen `257`, keyboard `512`, buttons `1026`, AVP `1280`, and trackpad-style gesture `1281`. The gesture device carries `_CoreDevice_suppressMousePointer`; it must not be assumed to provide a visible on-device mouse. No existing device properties were changed.
- `PocketPointerProbe` defines its own relative-motion-only descriptor. The actual wire must match Apple's `UniversalHID.PointerReport`: 17 bytes, report ID 5, signed 8-bit X/Y at bytes 1/2, buttons/modifiers/acceleration/flags all zero. The old six-byte generic-USB layout was incompatible despite successful dispatch. Static inspection of the shipped UniversalHID field getters established the layout; independent golden-vector tests cover it.
- Registration must return the new identity (verified absent before creation), and inventory must confirm exactly one matching ID, mouse usage and exact descriptor before motion. iOS rewrites Product labels; names are not identity proof. The old XCTest runner must be stopped and native media authentication verified. The successful physical test verified temporary-mouse removal and own-media cleanup. Metadata: `DerivedData/NativeControlV2/pointer-native-format-20261018.txt`; the owner's physical confirmation supplies the visual evidence.
- Debug path: **Screen Control → Native replacement · experimental → Native engine test → Visible pointer experiment**. Start with native diagnostics disconnected. The test page draws no cursor, requires a Dwell Control-off acknowledgement and an explicit movement-only approval, starts after an eight-second countdown, checks Pocket Agent remains active before each report, and offers Stop. It reuses the existing approved local VPN and app-owned Dynamic Island hand activity. Loop test does not contact the model; the new Agent target mode has a separate read/proposal approval as described above. Neither changes accessibility settings or invokes XCTest.
- Requested follow-up adds Precise/Fast/Turbo software velocity ramps (3/10/20 maximum relative units at up to 50 Hz), plus 10/30/45-second windows (Fast, 30 seconds by default). Native acceleration flags and global tracking settings remain untouched. All reports remain button-free, foreground-checked, cancellable, and bounded by both time and report count.
- The longer test pauses motion for local PNG/OCR captures about every three seconds, detects four inert test labels, and steers using fresh iOS hover coordinates **inside Pocket Agent only**. It never infers pointer position by summing sent deltas. Without any hover observation it runs a diagnostic acquisition sweep; after feedback is lost it pauses directed movement. No clicks, no model request, no automatic agent-tool enablement. The last PNG stays on the phone (`PocketControl/pointer-test-frame.png`); the post-test preview explicitly distinguishes OCR/hover annotations from captured cursor pixels.
- **30-second Fast physical test passed its capture/feedback gates at approximately 16:55 America/Vancouver:** 1,144 reports, nine local captures, real hover events, 317 feedback steering commands and four detected target arrivals. The saved raw screenshot shows the system cursor and all four OCR targets; no app cursor is drawn. Mac preview was disconnected during the test; process inspection afterward showed only Pocket Agent, no XCTest or local tunnel. Own-mouse removal and own-media cleanup completed. The owner separately confirmed “Yes—hand visible, no Automation Running.” AssistiveTouch was restored off and visually verified, Dwell stayed off, global tracking sensitivity unchanged; preview disconnected afterward. Evidence: `DerivedData/NativeControlV2/pointer-fast-30s-20261018.txt` and `.png`.
- Remaining: validate precision/repeatability, interrupted-session cleanup, other speeds and cross-app pointer localisation before exposing a mouse tool to the agent. A custom animated companion over other apps remains unresolved. The existing native tap/swipe tools are separate from this movement-only experiment.
- Physical diagnostics: the original lazy-form modal dismissed before testing; a navigation destination now stays open and an explicit alert is used for approval. Initial product-label equality checks blocked all reports because iOS rewrites the labels. After the identity/descriptor fix, the test completed 80 reports and verified removal: `DerivedData/NativeControlV2/pointer-motion-test-20261018.txt`. The owner then reported no pointer movement. Error paths also attempt verified own-media cleanup before closing the route. The old XCTest runner remains stopped.
- Requested follow-up: Pocket Agent's **Open Settings · native engine** command successfully launched Settings, with the blue hand visible in the preview. Metadata: `DerivedData/NativeControlV2/settings-launch-after-pointer-20261018.txt`. AssistiveTouch was then switched off and verified. This was a native app-launch test, not a successful mouse click or an LLM-driven action; no claim about a new physical-screen Automation Running observation is made.
- Validation: 13 pointer unit tests plus seven native wire/lifecycle tests pass, including signed report boundaries, ramp bounds, steering slowdown and duration choices. Another 35 screen-control/native-controller/local-route regression tests pass. Device build and strict code-sign verification pass; installed database sequence 3576. Software tests are separate from the physical Fast test evidence above. No claim of arbitrary-app mouse control or LLM-driven mouse operation is made.

Protocol research: [pymobiledevice3 HID service](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/remote/core_device/hid_service.py) documents registration and warns that the actual native report can differ from the advertised descriptor; [ipb's protocol notes](https://github.com/ipbtools/ipb/blob/main/docs/protocol.md) distinguish dispatch from demonstrated effects. Apple's [continuous-hover API](https://developer.apple.com/documentation/swiftui/view/oncontinuoushover(coordinatespace:perform:)) supplies positions within app views, not a cross-app pointer-location API. [AssistiveTouch pointer support](https://support.apple.com/en-ug/111775) remains a dependency of this physical experiment.

## Current native integration — 2026-10-18

- Installed the integrated Debug build on the iPhone Air. Native screenshots now work in the phone app: an approved Settings read returned a real PNG/OCR preview and returned to Pocket Agent, with the Mac preview disconnected. No XCTest runner process was running. Metadata-only evidence: `DerivedData/NativeControlV2/native-integrated-read.txt`.
- The fix announces modern RemoteXPC capabilities using the already-approved pairing UUID and pipelines the screenshot-service handshake. Transport tests cover handshake order, peer identity, odd request IDs, either response stream and flow-control credit for large screenshots.
- Chat now registers native `screen_read`, `screen_point`, `screen_tap` and `screen_swipe`. Every read/action still requires approval. Guide mode cannot send input. Typing is deliberately unavailable; there is no automatic fallback to XCTest.
- Screenshots stay local. Vision OCR labels (not an accessibility tree) go to the configured model only for an approved agent step. Manual previews do not contact a model. Exact unique labels, fresh single-use observation IDs and a fresh screen comparison are required before input. Permission-prompt detection is best-effort, not a security guarantee or proof of foreground-app identity. Keep the phone unlocked, portrait, and untouched during a step.
- Pocket Agent owns the hand Live Activity during each native operation and ends it during cleanup. Native sessions are bounded to 90 seconds; the single-peer packet tunnel has a separate two-minute expiry. This is not continuous background control.
- Earlier native proof-button taps and Settings launch passed independently of XCTest and the Mac preview. The owner confirmed the physical Automation Running notice was gone and the hand icon visible. The newly integrated chat read/tap/swipe sequence still needs physical testing; phone interaction was paused when the owner resumed using the phone.
- Latest core validation: 70 tests reported passing, with four old opt-in Ollama tests skipped. Includes two live home-Wi-Fi tests: real `gpt-oss:20b` reply, and real model → approval → synthetic native OCR → final response. That synthetic test does not operate a phone. Twenty targeted RemoteXPC/discovery tests pass. The signed iPhone build and strict code-sign verification passed.

Use **Guide me on screen → Scope & consent**, choose the allowed app and enable native control. Do not start the old helper. Legacy controls are collapsed at the bottom and explicitly warn that they bring back Automation Running. Start with Settings; never use payment, deletion or sending as a test.

### Approved home-Wi-Fi model connection

The local control VPN replaces Tailscale on the phone. The separately approved LAN route keeps model access available without Tailscale:

- Caddy listens only on `192.168.1.75:11436` and allows only the current phone (`192.168.1.69`) and this Mac. It forwards to the existing authenticated loopback gateway; Ollama is still loopback-only. No router ports, public listener, admin API or access log were added.
- `HomeWiFiModelTransport` reroutes only `POST https://jacks-mac-studio.tail6472bd.ts.net/v1/chat/completions`. It keeps the existing app access key and validates the TLS certificate against that DNS name using system trust, expiration and normal SSL policy. Redirects are refused. There is no accept-any-certificate exception. Unit tests reject unapproved routes and a self-signed certificate with the correct name.
- Settings has an owner-approved home-Wi-Fi toggle, default on for this personal build only when that exact provider is selected. Other providers retain ordinary URLSession routing. Both LAN IPs must remain unchanged; DHCP reservations or future explicit reconfiguration are needed if they change. The phone must be on this Wi-Fi, and the Mac awake.
- Source: `DeveloperTools/ModelGateway/Caddyfile.home-wifi`. Certificate/private key are outside the repo in `~/Library/Application Support/PocketAgent/home-wifi.crt` and `home-wifi.key`. Never log them. The certificate must be renewed before expiry.
- Current-session launchd job: `com.pocketagent.home-wifi-gateway`; no login LaunchAgent was installed. After logout/reboot, restart the underlying model gateway and Ollama, then run `/opt/homebrew/bin/caddy run --config /Users/jackadamslovell/Documents/PocketAgent/DeveloperTools/ModelGateway/Caddyfile.home-wifi --adapter caddyfile` in a terminal. Do not start a second listener while the job is active. Stop the current job with `launchctl remove com.pocketagent.home-wifi-gateway`.
- All nine authenticated/unauthenticated route checks passed over LAN HTTPS. Reproduce with `POCKET_GATEWAY_CONNECT_TO='jacks-mac-studio.tail6472bd.ts.net:11436:192.168.1.75:11436' bash Scripts/check-model-gateway.sh https://jacks-mac-studio.tail6472bd.ts.net:11436`. Run the opt-in live Swift tests with `POCKET_AGENT_LIVE_HOME_WIFI=1 swift test`.

The following older setup/test notes are historical unless stated otherwise; they do not instruct the native agent to start XCTest.

Status (2026-10-18): Xcode 27.1 builds the app for both the arm64 iOS Simulator and a developer-signed physical iPhone, with compiler warnings treated as errors. Pocket Agent runs on Jack’s iPhone Air (iOS 27.2) and passed its live **gpt-oss:20b** connection test through the private Tailscale HTTPS gateway to Mac Ollama. Physical-phone tests now verify encrypted pairing, authenticated Check, helper start/return, approved Settings read/return, and highlighting the observed General button in a captured preview without tapping. The helper also acknowledged shutdown, turned control off and exited. A simulator UI test additionally verifies Guide me refuses taps and Act with approval can navigate Settings → General. The helper-owned Dynamic Island icon appeared and ended correctly on the phone; physical-phone tap/return still needs verification. Fresh installations remain in demo mode until configured.

## Included in this MVP

- Native SwiftUI conversation UI
- Speech recognition and push-to-talk
- Screenshot selection and on-device Vision OCR
- OpenAI-compatible model client with credentials stored in Keychain
- A tested, provider-independent Swift agent loop
- Tool calling with a hard approval gate for sensitive actions
- Current-time and Apple Reminders tools
- Siri, Shortcuts, and Action button discoverability through App Intents
- Demo mode that works without an API key
- Screen Control panel: native screenshot/OCR preview, scoped consent and approved actions; legacy pairing/diagnostics retained separately
- Native CryptoKit implementation of iCTRL encrypted v1 JSON-RPC, with the pairing key in device-only Keychain
- Native agent tools for opening/reading an app, pointing at exact OCR text, tapping and swiping; no native typing yet
- One user-selected target app, fresh observation tokens, stale-screen and ambiguous-element rejection
- Finite background completion allowance and cancellation; no claim of unattended background operation
- Guide me mode (read/point only) and explicitly selected Act with approval mode
- `screen_point`: measured, unique-control highlighting on a captured screenshot, with optional observed control-type filtering
- Captured-screen cards in the conversation and control panel, including enlarged preview and capture-age warnings
- Agent screenshot previews stay local; approved screen text, not image bytes, goes to the configured model

The interaction reference is [HeyClicky's on-demand screen assistance](https://www.heyclicky.com/about): inspect, explain, point, act, and verify. This is **not** a global iPhone overlay, continuous screen surveillance, or invisible operation of a second app while you use another.

## Run it

1. Install Xcode from Apple.
2. Open `PocketAgent.xcodeproj`.
3. For simulator testing, choose **iPhone Air** as the run destination and press Run. No developer account is needed for the simulator. Xcode's **Settings → Components** installs the required runtime; the iOS 27.0 runtime supports iPhone Air.
4. For a physical iPhone, add your Apple developer account in Xcode Settings, then select the PocketAgent target, open **Signing & Capabilities**, and choose your development team. Choose the connected, trusted iPhone and press Run.
5. Open Settings inside the app and choose **Use Ollama on this Mac** in the simulator, or enter an HTTPS OpenAI-compatible `/v1` base URL, model name, and API key for a remote provider.

The app targets iOS 17 or newer. To run on a physical device, use a unique bundle identifier owned by your Apple Developer account.

## Verify the portable agent core

```sh
swift test
```

The current suite discovers 88 tests, including eight opt-in live tests. It covers approval boundaries, batch rejection, per-turn limits, legacy encryption/pairing, native OCR actions, pointer target proposals, fixed navigation commands, no automatic retries, stale/ambiguous screens, cancellation, model request validation, home-Wi-Fi routing and TLS rejection. Legacy typing tests do not imply native typing support. Live tests using synthetic OCR do not establish physical gesture compatibility.

## Local Ollama setup (verified on this Mac)

- Ollama 0.40.6, installed through Homebrew; model `gpt-oss:20b` (20.9B, MXFP4, approximately 13 GB on disk).
- API base URL: `http://localhost:11434/v1`. No API key. Existing cloud keys are never sent to loopback endpoints.
- Runs on the Mac's GPU, not inside the iPhone. This Mac has an M1 Max and 32 GB unified memory.
- `~/.homebrew/services/ollama.env` binds only `127.0.0.1:11434`, disables Ollama cloud features, sets a 16,384-token context, allows one model/request at a time, and unloads the model after ten idle minutes.
- Started with `brew services run ollama`, which does not register automatic startup at login. After restarting the Mac, run that command again. Stop it with `brew services stop ollama`.
- In Pocket Agent's simulator Settings, choose **Use Ollama on this Mac**, then **Test connection**. The model label shows the configured destination; it is not a continuous health check. The first answer can take longer while the model loads.

Run all tests, including actual local inference and a read-only tool round-trip:

```sh
POCKET_AGENT_LIVE_OLLAMA=1 swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

The live checks verify a response, one Swift tool execution with a unique result code echoed back, and an approval request declined with zero tool executions. They do not create reminders or control another app. On this machine the cold first answer took about 38 seconds; the warm tool round-trip took about four seconds. These are one-run measurements, not performance guarantees.

For a Debug simulator build, launching with `--use-local-ollama` saves the local preset. Adding `--test-local-model` also sends one current-time test prompt through the real app. These switches are compiled out of physical-device and Release builds.

**Physical iPhone:** `localhost` on a phone points to the phone, not your Mac. Ollama remains bound to Mac loopback; the private gateway below provides the phone connection. Connecting a model does not install or enable the screen-control runner.

### Private phone-to-Mac model gateway

Configured on 2026-10-18, with the user's approval for Tailscale HTTPS. The physical iPhone joined the tailnet, and Pocket Agent's Test connection displayed “Model replied successfully.” The endpoint, model and Keychain credential were saved in the app.

- App base URL: `https://jacks-mac-studio.tail6472bd.ts.net/v1`; model: `gpt-oss:20b`.
- Tailscale Serve terminates HTTPS privately on port 443 and forwards to Caddy on `127.0.0.1:11435`. No public Funnel endpoint is configured for this service.
- Caddy 2.11.7 was installed through Homebrew. The source configuration is `DeveloperTools/ModelGateway/Caddyfile`. It permits only authenticated `POST /v1/chat/completions` and `GET /v1/models`, caps bodies at 1 MB, removes the gateway credential before forwarding, and has no access log or admin endpoint. Ollama remains on `127.0.0.1:11434`.
- A random 32-byte key is stored as hex in `~/Library/Application Support/PocketAgent/model-gateway.key`, mode 600. It is not committed, embedded in the app, or included in these docs. Enter it in Pocket Agent's API key field, which saves to device Keychain.
- Runtime copies of the Caddyfile and startup script live beside that key. The current-session launchd job is `com.pocketagent.model-gateway`; it was submitted without installing a login LaunchAgent. Both the Mac and Ollama must remain running. The gateway must be restarted after logout/reboot; Tailscale Serve's configuration alone does not start Ollama or Caddy.
- Verification: all nine gateway authorization/route checks passed with `bash Scripts/check-model-gateway.sh https://jacks-mac-studio.tail6472bd.ts.net`. A real HTTPS chat request from this Mac received `Connected.` from `gpt-oss:20b`. Pocket Agent on the physical iPhone then independently passed its own live model connection test over the private HTTPS endpoint.

To start the gateway manually in a terminal after reboot, run `bash Scripts/start-model-gateway.sh` and leave it running. Do not start a second copy while the launchd job owns port 11435. To stop this setup, run `/Applications/Tailscale.app/Contents/MacOS/Tailscale serve --https=443 off` and `launchctl remove com.pocketagent.model-gateway`; this does not delete the private key or Ollama model. Config changes require restarting the gateway. The plaintext loopback listener is intentional: transport beyond the Mac uses Tailscale HTTPS, with normal certificate validation in the app.

References: [Tailscale Serve](https://tailscale.com/docs/reference/tailscale-cli/serve), [HTTPS certificate visibility](https://tailscale.com/docs/how-to/set-up-https-certificates), [Caddy request matching](https://caddyserver.com/docs/caddyfile/matchers).

The Ollama installation also added Homebrew's Python 3.15 and MLX dependencies and upgraded SQLite to 3.54.1. Homebrew replaced its default Python command links and backed up previous conflicting paths in `~/Library/Caches/Homebrew/Backup`; existing Python environments were not deliberately modified.

Implementation references: [OpenAI's local Ollama guide](https://developers.openai.com/cookbook/articles/gpt-oss/run-locally-ollama), [Ollama's compatible API](https://docs.ollama.com/api/openai-compatibility), and [Ollama configuration FAQ](https://docs.ollama.com/faq).

## Legacy runner setup (historical fallback; not needed by native agent)

Screen Control is an **optional feature in Pocket Agent → Settings → Optional features → Screen Control**, off after each app launch. Chat does not require it. The in-app panel has Start screen helper, Pair, Check, a scoped Screen Control switch, manual approved actions, and confirmed helper shutdown.

The runner is still a separate app/test bundle, not an entitlement added to Pocket Agent. It is **not installed automatically** by building this app. The separate iCTRL companion UI is optional; the in-app controls are intended to replace it for ordinary sessions. The developer image and signing lifecycle still require developer setup.

1. Install full Xcode, open it once, sign into your Apple developer account, and select its Command Line Tools under Settings → Locations.
2. Connect and trust your iPhone. Enable Developer Mode. Use an Xcode release that supports the phone's iOS version.
3. Install XcodeGen (`brew install xcodegen`), then run:

   ```sh
   bash Scripts/prepare-screen-runner.sh --check
   bash Scripts/prepare-screen-runner.sh --build
   ```

   The build fetches the pinned [iCTRL](https://github.com/OpenMinis/iCTRL) source if missing and its upstream idevice framework. It uses your development certificate/provisioning configuration; no credentials belong in the repo. It refuses to overwrite a changed runner checkout.
4. Open `DeveloperTools/iCTRL/iCTRL.xcodeproj`. Select your phone and use **Product → Test**. Xcode prepares the developer disk image and starts the runner. Approve its device prompts. Keep remote access **off**.
5. Run `PocketAgent.xcodeproj` on the same phone. Open the hand-tap **Screen Control** button, choose **Pair with runner**, then approve the Pocket Agent request in the runner notification. Pairing is a single request with a 90-second client timeout; do not repeatedly press Pair.
6. Check the connection, leave the target as `com.apple.Preferences`, choose **Guide me** or **Act with approval**, and explicitly enable supervised control. Guide me is the default. Stop control before changing mode or target.

For Pocket Agent's **Start screen helper** button, after the last runner build run `bash Scripts/prepare-runner-launch-link.sh`, then install the generated `iCTRLUITests-Runner.app`. This adds upstream's `ictrl://` launch scheme and re-signs the generated app with its existing development identity; this launch-link-only script does not modify source. The separate running-icon build below applies a reviewed lifecycle patch. Pocket Agent registers a return URL that cannot enable control, pair, or send a prompt. Opening the helper is not proof of a running server: verify using authenticated Check. A later Xcode rebuild can remove the launch-link packaging, so reapply it before installation.

Physical setup progress: the loopback-only runner and optional companion are installed. In-app start/return, device-approved pairing, authenticated RPC, approved Settings read/highlight/return, and acknowledged shutdown/process exit have passed. Pairing keys remain in Keychain. A ready notification alone is not proof that a screen action succeeded.

### Helper running icon (developer build)

`bash Scripts/build-runner-status.sh` builds the pinned runner with the reviewed `DeveloperTools/RunnerStatus/lifecycle.patch`, a small ActivityKit status owner, and a WidgetKit extension. It packages/signs only the generated runner product; it does not install, pair, enable remote access or authorize actions. Install `DerivedData/RunnerStatus/Build/Products/Debug-iphoneos/iCTRLUITests-Runner.app` after building. The ordinary upstream preflight intentionally rejects the locally patched checkout; use this status-build script for the customized helper.

The Dynamic Island is an icon, not chat progress. It reflects listener readiness, refreshes locally every 30 seconds, becomes unknown after 90 seconds without an update, and ends on normal shutdown. Compact icon appearance/removal and helper restart with retained pairing are verified on the physical iPhone. Stale/crash behavior and expanded/Lock Screen layouts remain unverified. ActivityKit does not provide background execution.

**Important:** the original runner's icon does **not** replace iOS's persistent “Automation Running” system overlay. That overlay is omitted from mirrored screenshots, which caused it to be mistaken for the runner's brief startup shell. It is a known XCTest limitation ([Appium documentation](https://github.com/appium/appium-xcuitest-driver/blob/master/docs/troubleshooting/index.md)). The user requires functioning on-phone control and the Dynamic Island icon together; stopping all control is not a fix. The native-engine experiment below now has independent physical-input evidence, but remains separate from the chat agent's iCTRL-backed tools. Activity content contains only generic status, never screen text, screenshots or credentials.

### Native control replacement experiment (2026-10-18)

**Physical-display result confirmed by the owner:** after another isolated native tap and Settings launch, the user reported “The screen is gone; hand icon is visible.” The legacy runner was verified absent during and after the test. This establishes an XCTest-free input path with the required physical-display behavior on this phone, **not a finished replacement for the existing chat tools**. The bounded test has ended, its local VPN is stopped, and Tailscale connectivity was restored (successful private-network ping). No control engine is left running.

**Latest result — native engine installed and input verified:** `PocketNativeEngine` implements authenticated CoreDevice media negotiation, local-only video draining, Universal HID touch reports and restricted app launch in Swift, without XCTest. `NativeControlModel` exposes supervised Debug controls inside Pocket Agent. `PocketNativeActivity` owns its own hand-icon Live Activity, independently of the old runner. These are bounded developer tests, not a finished replacement for every chat-agent screen tool.

- One measured proof-button touch passed with the original helper still available (`native-touch-success-20261018.txt`: 0 → 1, 228 video datagrams).
- The original XCTest runner was then shut down through its authenticated app control. Its main process disappeared; pairing and the installed fallback were retained.
- A second approved touch passed with XCTest stopped **and Device Hub switched away from the physical phone for the entire touch/cleanup interval** (`native-only-touch-20261018.txt`: 0 → 1, 224 datagrams). The app does not increment this counter in test code; only the button's real action increments it.
- The native engine launched Settings. Pocket Agent's own blue hand icon was visually verified there (`native-settings-launch-20261018.txt`). The owner initially still saw Automation Running; investigation found the old runner active again (PID 976). After authenticated shutdown, another independent native tap passed (0 → 1, 220 datagrams; `native-retest-20261018.txt`), Settings opened, and the owner confirmed the screen was gone with the hand icon visible. Mirrored screenshots alone cannot establish that condition.
- Native media startup replaces a simultaneous Device Hub video stream on this iOS version, so the Mac preview may briefly show a display error. Keep Device Hub disconnected during independent proofs. Frames are counted/discarded, not sent to the model or saved.
- A start reply echoes our exact client UUID but does not expose the daemon's internal stop identifier. `SyncStreamToken` can identify another audio session: never use it as an owned token. Cleanup closes only our XPC connection and checks the active-session list for our UUID. It never sends `stopAll` or guesses another client's ID. Malformed status fails closed. Native-only cleanup passed on this phone.
- Screenshot capture remains broken on the phone: the final retest failed with a closed userspace TCP connection. HTTP/2 receive-window replenishment, optional either-stream response handling and per-chunk TCP receive credit are implemented and pass the transport suite, but did not fix the physical screenshot request. Do not report screen reading as verified.
- To prevent confusing the two engines, the old Start button is now labelled “Start legacy XCTest helper,” requires confirmation that it brings back Automation Running, and refuses startup while a native test is active. The experimental entry is labelled “Native replacement” → “Native engine test.”
- Limits: native session 105 seconds; local VPN 120 seconds; not yet wired into the existing agent's `screen_*` tools; no native accessibility tree/typing/swipe implementation; no unbounded background execution. The local VPN replaces Tailscale, so model access must be restored afterward. These remaining integration issues keep PA-009 open.

Evidence files above are under `DerivedData/NativeControlV2` and contain metadata, not credentials or screen images. The core suite passed (54 discovered, four live-model tests skipped), the full local `rork-device` suite passed, and the signed physical-device build passed strict verification. New focused coverage includes five wire-format/media-sink tests, two cleanup-status tests and eleven RemoteXPC transport tests.

The following records describe the earlier connection-only stages, not the current native engine's capabilities:

The user approved a separate developer pairing for an XCTest-free control engine. The iPhone accepted **Pocket Agent Native Control**, and a second USB verification succeeded without re-enrollment. A fresh Ed25519 identity was generated for this experiment; the Mac's pre-existing trust keys were not exported into the app.

- The Swift transport is a local, Apache-2.0-licensed `rork-device` checkout at `3e4fed0b807695f6ac24ead827f1a264eaae0063` under `DeveloperTools/rork-device`. Local additions: a clearly named pairing host, `PocketControlProbe` (read-only RSD capability inspection with exact-device binding), three tests, and a read-only `remote-pairing pocket-probe` CLI comparison command. Upstream licenses/notices remain in that checkout. Its networking dependencies include native C libraries; this is not a claim that every dependency is Swift.
- `PocketAgent/Services/NativeControlSetup.swift` adds a Debug-only entry inside the existing Screen Control panel. It does not start media streaming, send touches, stop XCTest, or change the Dynamic Island. The approved identity lives outside the repo at `~/Library/Application Support/PocketAgent/NativeControl/remote-pairing.plist` (0600) and in the app's `Library/Application Support/PocketControl/remote-pairing.plist` (0600, complete protection, excluded from backup when checked). Never print or embed its contents in a build.
- **Physical result:** direct connections from Pocket Agent to this phone's own loopback, Wi-Fi and Tailscale IPv4 addresses reached the listener but reset before authentication completed. Unreachable interfaces were also reported. The same Swift protocol and identity successfully authenticated from the Mac over the phone's Wi-Fi address and discovered both Universal HID and app services. This distinguishes successful pairing from the still-blocked on-phone route; it does not prove that taps work or that the overlay is gone.
- The current runner was left active (PID 856 during verification), with its hand icon visible. The app update preserves pairing but, as before, Screen Control defaults off on launch. The experimental probe cannot enable it. No replacement input engine has been activated and no VPN settings were changed.
- The user subsequently authorized building and testing a local-only route, including the temporary Tailscale/Ollama interruption. `PocketControlTunnel` is now embedded in Pocket Agent, using the public `packet-tunnel-provider` entitlement. Its networking technique is **based on [LocalDevVPN](https://github.com/StephenDev0/LocalDevVPN), by StephenDev0 / Stossy11 / the SideStore Team**. Attribution also appears in the test UI, and the full StosVPN license is included in the app's `THIRD_PARTY_NOTICES.txt` resource.
- The local test routes only synthetic peer `10.7.0.1/32`, reflects validated IPv4/TCP packets between that peer and `10.7.0.0`, excludes the default route, and installs no DNS/IPv6 routing. Pair verification negotiates a second dynamic TCP port, so this is not restricted solely to port 49152. Other addresses, protocols, fragments and malformed headers are dropped; packets are not logged. The extension expires after 120 seconds and does not enable on-demand reconnect. Stopping it **does not automatically reconnect Tailscale**; restore Tailscale through its app afterward.
- Debug Screen Control → Native control → Local connection test presents Start, Verify and Stop controls. Saving the VPN profile requires the owner's on-phone approval. Authentication has a 15-second socket-closing deadline, followed by a 10-second discovery deadline. Verification still does not send any input, start a media stream, stop XCTest, or claim the overlay has disappeared. Keep the original helper and island until independent native input is physically verified.

Local-route implementation validation: four packet isolation/validation tests and four native capability/deadline tests passed. The core suite reported 54 tests (four opt-in live model tests skipped). The physical-device Debug build with its embedded packet-tunnel extension compiled and passed strict signature verification. VPN approval and on-phone route authentication remain pending; the replacement input engine and PA-009 are not complete.

**Physical local-route test, 2026-10-18:** after user approval of the VPN configuration, Start connected successfully. The on-phone Verify action authenticated through the synthetic local peer and discovered Universal HID, app service, `com.apple.coredevice.displayservice` and `com.apple.coredevice.screencaptureservice`. Evidence copied from the app (no keys or screen contents): `DerivedData/NativeControlV2/local-route-success-20261018.txt`. This resolves the self-origin authentication blocker for this test. Stop disconnected the local route, and Tailscale was reconnected from its existing app. The original runner's hand icon remained visible throughout. No replacement touches, media session or physical overlay-absence test has run; PA-009 remains open.

Validation: three capability-probe tests passed. The core test run passed with four opt-in live-Ollama tests skipped (50 discovered); no new physical input test occurred. `xcodebuild` produced and installed the Debug connection-check build using `DerivedData/NativeControlV2`. An empty `ManifestLoading` cache file had blocked package resolution; it was moved to `ManifestLoading.pocket-agent-empty-file-backup-20261018` in the same cache directory, not deleted. Global command-line warnings-as-errors conflicts with a dependency's suppress-warnings setting; the normal app build succeeds.

### iPhone operating guide

The system prompt includes a versioned-in-source operating guide: observe → identify an exact control → request one approval → act → verify. It covers navigation, observed control types, finger-direction swipes, append-only typing, expired captures, guide-only mode, unsupported hardware/system actions and untrusted screen instructions. Explicit highlight requests should call `screen_point` after reading, not merely offer it later. This is guidance, not a guarantee of model competence: the controller still enforces scope, mode, freshness and consent. A live Ollama test checks the next highlight call against a synthetic screen and randomized observation ID without touching a phone.

Pin: `DeveloperTools/ICTRL.lock`. Upstream source includes its Apache-2.0 license and dependency notices. The client follows its protocol but exposes only a small fixed set of operations; it does not download or execute runner-served skills.

After a reboot the developer image must be remounted and the runner restarted. For phone-only startup, upstream documents its companion image-mounter app or StikDebug; **that lifecycle has not been verified here**. Development signing must also remain valid. See the [upstream installation guide](https://github.com/OpenMinis/iCTRL#installation).

## First on-device check (no model required)

1. In Screen Control choose **Open app, read & preview screen** and approve it. Expect Settings to open briefly, then Pocket Agent to return with a still image and UI text.
2. Enter an exact visible label from that text (for example `General` on an English Settings screen). If the name matches both a control and its text, choose the observed control type; the tested iOS 27.0 Settings row is a `Button`. Choose **Show me where · no tap** and approve. Expect a measured outline in a captured preview inside Pocket Agent. This does not draw over Settings or tap anything.
3. To act, stop control, choose **Act with approval**, enable it, and obtain a fresh read. Choose **Tap this control** and approve. Expect a new preview of the resulting page. Reads expire after 120 seconds; re-read when instructed.
4. Try one swipe on a harmless list. Test typing only in a disposable search/draft field. Text is appended, never cleared or submitted, and newline/control characters and secure text fields are rejected.
5. Stop screen control; further screen requests should fail. Reopening the app starts with control off.
6. Only then configure a model and ask: “Read Settings, bundle ID com.apple.Preferences, and show me where General is.” Each screen tool must display an approval card before execution. Screen text is sent to that provider after approval; manual previews are not. **Ask Pocket Agent about this app** prepares a question without capturing or sending it automatically.

Do not interact with the target app during an approved operation. This is a supervised prototype, not a security boundary against a compromised runner. Keep the device unlocked; Pocket Agent does not unlock it or dismiss system permission prompts.

## Reproduce the real simulator screen test

Build and install Pocket Agent on the chosen simulator first. With XcodeGen installed and the pinned iCTRL checkout present:

```sh
xcodegen generate --spec DeveloperTools/ScreenRunnerSimulator/project.yml
xcodebuild test -project DeveloperTools/ScreenRunnerSimulator/ScreenRunnerSimulator.xcodeproj -scheme ScreenRunnerSimulator -destination 'platform=iOS Simulator,id=1854D1C3-BCA9-475A-973A-D4C1EDAD26D0' -derivedDataPath DerivedData/ScreenRunner -only-testing:ScreenRunnerTests/ScreenInteractionUITests -parallel-testing-enabled NO -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO
```

Replace the simulator ID with your own. This test drives the real Settings app through iCTRL's dispatcher and the production `ScreenController`; it does not start an HTTP server, approve pairing, contact a model, or prove physical-device compatibility. Its only write-like action is navigating to General. The upstream runner includes native compatibility code and emits warnings under Xcode 27; the app and portable core are built with warnings as errors. The simulator test does not enable the conditional runner-status lifecycle hooks.

Passing result: `DerivedData/ScreenInteraction-4.xcresult`. The test attaches a real screenshot and `GuidanceCapture.json`. For visual QA only, a Debug simulator build can load that JSON from its Documents folder with `--preview-captured-screen`. This shows an explicitly labelled recorded test capture; it does not pair or enable control. This code is excluded from physical-device and Release builds.

## Current limits

- Simulator launch, signed phone installation, helper cold start, encrypted pairing, authenticated Check, physical Settings read/highlight/return and helper shutdown/restart are verified. Physical Settings → General tapping remains unverified. All 50 core tests passed, including four live Ollama tests; the latest app with the iPhone operating guide is installed.
- The signed phone build succeeded, but Xcode's App Intents processor logged an SSU artifact archive error. Siri/Shortcuts discovery and Action button assignment still need an actual-device check; successful app launch does not verify those features.
- Control is single-step: activate target → verify/read → approved action → read result → return. A finite iOS background allowance can expire mid-step; reopen the app manually if needed.
- Timeouts and cancellation never trigger automatic replay. A request already sent may have completed, even when no result arrived. Inspect the phone before another attempt.
- Screen reads use accessibility text with upstream OCR fallback. Screenshots are local previews; the model adapter does not send them as vision input.
- Taps require a unique exact accessibility label/ref. Unlabelled icons, coordinate-only targets, missing/ambiguous controls and changed layouts are intentionally not supported yet.
- A paired key grants broader rights at the runner than the app's tool allowlist. **Forget local pairing** removes this app's key only; revoke its session in iCTRL to invalidate the server grant.
- No App Store/TestFlight compatibility claim for the testing runner, always-on recording, persistent task recovery or on-device model inference.

## Security boundaries

- Screenshots are processed only after attachment or an explicitly approved manual preview.
- Extracted screen text is labeled as untrusted context in the system prompt.
- API credentials are stored in the device Keychain.
- Tools marked sensitive pause before execution and require an explicit Allow action.
- Screen control is off by default, limited to one chosen app, and every agent screen operation requires approval, including reads.
- Pairing/RPC uses loopback only. Redirects are refused, no global insecure-network exception is enabled, and no key is written to UserDefaults or source files.
- A changed screen, system alert, ambiguous control or unknown outcome stops the step. These checks reduce mis-taps but do not make sensitive actions safe to leave unattended.
