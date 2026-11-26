# Tapp Lab

## Aura live character — 19 October 2026

The Aura UI update exposed a companion discovery bug: finding cursor A first
then always traversing backward left the cursor group. Discovery now walks
forward from A and backward from D, with up to 12 bounded discovery steps.
After that fix, physical run `561CC56B-85EC-48A8-BD22-7AF54020C9DB`
completed all 15 movement steps with AssistiveTouch off. Evidence:
`Evidence/tapp-aura-movement-report.json` and `Evidence/tapp-aura-companion.txt`.

The owner clarified that the **live cross-app cursor** must be the tiny Aura
character with its animated speech bubble, not only the character in the UI.
`TappCursorModel.renderedPath` now carries its silhouette, eyes, smile, bubble
and staggered bouncing dots. Wake replays the bubble; Reduce Motion disables
its motion. Bounds include the larger bubble. The existing compositor still
controls colour/fill: this does not reproduce Aura's glossy gradient bitmap.

The iOS build passed (`Evidence/tapp-aura-character-build.txt`), but installation
failed because CoreDevice reported the iPhone unavailable after the owner left.
**Character rendering, bubble animation and navigation recognition remain
physically unverified.** The phone still has the preceding Aura UI build and
plain live arrow. Do not describe the character update as installed or tested.
Next: install the current Debug-iphoneos build, launch `--tapp-test-movement`,
inspect the character, then run `--test-switcher-instant-chat` and verify its
fresh report and screenshot. The companion remains running with reconnect.


## Outside-card movement and current screen-boundary bug — 2026-10-19

The physical iPhone Air passed a visually measured four-corner movement test outside hitapp's stationary App Switcher card, with AssistiveTouch OFF and no clicks. Two observed cursor anchors measure the card's scale and offset; inverse compensation places the cursor in phone coordinates. All four requested corners matched within 0.02 normalized units. The owner also confirmed the visible result. [Verification](Evidence/navigation-outside-card-verification.json) and the source checkpoint in `Evidence/VerifiedNavigationOutsideCardBaseline/` preserve this working result.

**Hard screen bounds during card movement are still failing.** The arrow slides with the host card during horizontal browsing. Clamping the requested phone point, including the arrow body, does not cancel the later compositor movement. The application-root container experiment also failed the right swipe; its evidence is in `Evidence/navigation-application-root-report.json`. The current diagnostic tests path offsets after the swipe to distinguish displacement from loss of rendering. The offset probe recovered the cursor after a swipe without repeating input, confirming displacement rather than total loss of rendering. With eased horizontal input and a settled release, two three-step diagnostic runs completed show/right/left with verified post-swipe recovery; the arrow still left the screen during those transitions. All tested UIKit point-conversion methods returned identity transforms. A focus acknowledgement is not a visible-arrival check. Do not treat these experiments as a completed screen-boundary or smooth-navigation fix.

An explicit `Tapp navigate:` chat route and bounded AI planner are implemented and build successfully. Four planner tests, including six invalid-plan cases, pass. The planner accepts only show/left/right plans, requires show first, and uses the existing locally verified executor. The configured model selected `show` for “Bring up my open apps so I can choose one.” through the actual chat dispatch. The phone completed App Switcher entry and automatically placed Tapp outside the card at bottom center, verified from a fresh capture. See `Evidence/navigation-ai-show-plan.json` and `Evidence/navigation-ai-show-report.json`. This is one-step AI navigation acceptance, not a multi-step or app-closing pass. Every `phone_navigate` App Switcher entry now routes through that measured navigation presentation as well.

## AI gesture tools

The real chat tool registry includes `screen_hold` and `screen_drag` alongside read, point, tap, swipe, phone navigation and named App Switcher actions. Hold uses a fixed 650ms contact. Drag holds for 500ms, follows an eased path, settles for 120ms and releases. Both resolve exact observed labels; drag requires a destination from the same fresh observation. The executor checks screen freshness and alerts immediately before input, consumes observations once, and never retries input. Legacy controllers reject these native-only gestures. Forty-six focused controller/planner/schema tests pass, including invented/duplicate drag targets, arbitrary-coordinate rejection and observation replay. Physical hold/drag acceptance is pending.

## Automatic reconnection and navigation language — 2026-10-19

The companion now discards failed device discovery and service connections, discovers a fresh address/port, and retries after 1, 2, 4, then at most 8 seconds. The same Tapp session is eligible after failure; it is no longer permanently blacklisted. Connection attempts, service teardown and renderer cleanup are bounded. Disabled Tapp stays disabled, missing state waits for first use, and cancellation exits instead of reconnecting. Rendering recovery never replays phone input. Initial AI-test connection readiness now waits up to 30 seconds before any input begins.

Six connection lifecycle tests pass. A physical-device diagnostic closed only the companion's own file transport three times. The same companion process recovered the same hitapp PID/session in 2.156, 3.174 and 5.096 seconds, discovering four connections. A subsequent request submitted through chat selected the middle button and produced exactly one independently verified click in 15.99 seconds. See [reconnection evidence](Evidence/tapp-reconnection-verification.json), [live log](Evidence/tapp-live-reconnection.txt), [chat acceptance](Evidence/ai-reconnected-chat-verification.json), and [unit tests](Evidence/tapp-reconnection-tests.txt). This is forced transport-loss coverage, not an overnight Mac sleep or locked-phone guarantee. The Mac must still be running and the phone available/unlocked for control.

Navigation understanding now accepts Tapp addressing and polite requests, common Home/App Switcher/Home-page/Settings phrases, and precise meanings for scroll versus swipe direction. Back, keyboard dismissal and named-app opening feed explicit guidance to the model through the existing app-scoped tools; they do not broaden saved access or invent controls. `Tapp, show navigation commands` describes availability. Unsupported system controls produce a direct explanation without dispatch. Twenty-eight focused Swift tests pass, including aliases, negation/questions, compound requests, scope and direction semantics. Live navigation acceptance is in progress.

## Verified 40-click baseline and AI integration — 2026-10-19

**Ten consecutive corner passes now pass on the physical iPhone Air with AssistiveTouch OFF.** All four independent UIKit counters reached 10. The fixture remained foregrounded, received exactly 40 presses and 40 releases at the validated coordinates, and the native input trace records exactly 40 operations plus owned-media cleanup. No clicks were retried. The complete run took 123.25 seconds. See [independent verification](Evidence/ten-pass-high-refresh-verification.json), [app report](Evidence/ten-pass-high-refresh-report.json), [fixture events](Evidence/ten-pass-high-refresh-counts.json), [native trace](Evidence/ten-pass-high-refresh-trace.jsonl), and [tenth pass](Evidence/ten-pass-high-refresh-pass-10.png).

The owner accepted the higher-refresh motion. That motion is preserved as the baseline. The companion targets 120 updates/second, with one outstanding request per each of four distinct accessibility elements, and writes heartbeats on presentation changes or every half-second. The 15-move test completed; measured refresh acknowledgements had a median of 116.4/second without native media and 27.9/second during the full click run. These are **not measured display FPS**. See [timing summary](Evidence/high-refresh-timing-summary.json) and [movement report](Evidence/high-refresh-movement-report.json). All ten pass screenshots have a compact green cursor, approximately 51 × 74–75 pixels; the long diagonal artifact is absent from those captures.

Click reliability fixes include one persistent HID channel, renewal between completed gestures after 45 seconds, a read-only service reply before initial input and after release, and release timestamps generated after the hold. The batch establishes its media session before the initial observation. A single extra pre-input screen read can recover transient OCR variation, but exact original labels and bounds must still match. The user-initiated continued-processing task is bounded to 180 seconds, records progress, and supports cancellation. Final reports are written before completing the background task. Source checkpoints are in `Evidence/VerifiedFortyClickBaseline/`.

### AI test integration

The installed app accepts **`Test Tapp: tap the upper right button`** in chat, or a request under **Guide me on screen → Test Tapp with AI**. The AI test resets only the disposable Tapp Click Test app, reads its five original button labels locally, sends those labels and the user's request to the configured model, and accepts exactly one observed label from one tool call. Coordinates and screen images are not sent to the model. Tapp then revalidates the screen, moves, sends one native click, and checks that exactly the selected counter changed. Unknown labels, multiple calls, coordinate-bearing calls, stale screens and unverified outcomes stop the test. No click is retried. Two live configured-model tests now pass on the physical phone: “Tap the upper right button” selected `Top right`, and “Click the button in the middle” selected `Centre ready`. Each produced exactly one native press/release at the validated coordinates, changed only the expected independent counter, and verified owned-media cleanup. AssistiveTouch remained OFF. See [upper-right verification](Evidence/ai-upper-right-v2-verification.json), [middle verification](Evidence/ai-middle-verification.json), and their corresponding reports, counters, traces and after screenshots. The first took 28.60 seconds including model response; the second took 13.54 seconds. Forty-four focused planner and screen-controller tests also pass.

The chat UI entry path now also passes on the physical phone. On 19 October at 08:24–08:25 Vancouver time, `Test Tapp: tap the upper right button` was typed into hitapp’s composer and submitted with its Send button, with no diagnostic launch arguments. Run `81B81486-B670-44B7-8DAA-46FBE57DCCC4` completed in 27.82 seconds. Independent counters and touch logs confirm exactly one native click at the validated target, with owned-media cleanup. Returning to hitapp displayed “AI selected Top right. One click and its counter change were verified.” and an available composer. AssistiveTouch remained OFF. See [chat success](Evidence/ai-chat-upper-right-chat-success.png), [verification](Evidence/ai-chat-upper-right-verification.json), [report](Evidence/ai-chat-upper-right-report.json), [fixture counters](Evidence/ai-chat-upper-right-counts.json), [input trace](Evidence/ai-chat-upper-right-trace.jsonl), and [clicked target](Evidence/ai-chat-upper-right-after.png). The earlier two runs used debug launch arguments into the same method.

The first chat attempt correctly stopped without clicking because the long-running companion retained an expired device tunnel after time away. Restarting only the Mac companion restored the connection; then the request was resubmitted explicitly through chat. The failed attempt is preserved in `Evidence/ai-chat-disconnected-report.json`. This failure motivated the automatic reconnection fix documented above. No app code or accepted motion was changed for this chat test. The first AI attempt stopped before the model call because the cursor covered the centre label; the installed fix parks it below that label before reading. The failed attempt remains saved as `ai-upper-right-report.json`.

The general native screen tools already share Tapp's movement-before-click pipeline. Their model descriptions and runtime context now distinguish a live Tapp cursor from a captured preview. The first AI acceptance scope is the separate counter fixture; arbitrary cross-app tasks are not claimed complete.

### Run and verify

Run `.audit-venv/bin/python run_tapp_app_companion.py` here, then enable Tapp in hitapp. The companion follows the installed app container across rebuilds. The UI provides movement, one-click, ten-pass and animation previews. Discovery failures and expired tunnels now cause bounded automatic rediscovery; input is never replayed.

Debug launch arguments support `--tapp-test-movement`, `--tapp-test-ten-passes`, and `--tapp-test-ai 'Tap the upper right button'`. Use `xcrun devicectl device process launch --device <device> --terminate-existing com.jackadamslovell.PocketAgent -- <argument>`. Only explicit debug launch arguments start a diagnostic. For the ten-pass test, restart the counter fixture first; AI tests reset it themselves. For AI evidence, run `python3 verify_ai_run.py --prefix ai-upper-right-v2 --expected "Top right"` or `python3 verify_ai_run.py --prefix ai-middle --expected "Centre ready"`. These check the app report against independent counters, received touch coordinates and native cleanup. The offline verifier never controls a device: `python3 verify_corner_run.py --prefix ten-pass-high-refresh` checks the saved report, independent counters, received touch coordinates, foreground history and input cleanup.

**Limits:** the paired Mac companion still draws the cross-app cursor. The system controls its colour; red Liquid Glass is an in-app appearance preview. True idle opacity fading, indefinite background lifetime, force-quit survival, lock/unlock recovery and a phone-only renderer remain unverified. Temporary video datagrams required by native control are discarded; diagnostic OCR stills are saved, not continuous video recordings. The HeyClicky-style conversation UI remains future work.

# Working physical-device cursor prototype — 18 October, 23:37 onward

**A small custom arrow now visibly moves over hitapp and Settings on the physical iPhone Air with AssistiveTouch OFF.** The owner confirmed the live result. This is a new, Mac-assisted accessibility-audit rendering route; the failed app-window and native-pointer experiments below are separate routes.

Run the installed research build with `./run_tapp_cursor_demo.command` from this directory. It uses the existing paired developer connection, starts Tapp Research, obtains its two genuine accessibility elements, switches to hitapp and Settings, and refreshes inspector focus at 30 requests per second. The test cleans up its inspector visuals and connection afterward. The research app also has a 45-second/background-expiration stop. The `.audit-venv` environment uses [audit-requirements.txt](audit-requirements.txt).

The two elements share an elapsed-time trajectory. Alternating their identities forces the inspector to fetch a fresh custom `accessibilityPath`; repeatedly selecting one unchanged identity left the cursor at a cached position. The smaller arrow is about 16 × 24 points. The latest motion profile smoothly accelerates from 0.35 to 1.1 radians/second over two seconds, cruises for four seconds, and decelerates for two seconds. Motion follows elapsed time, not the number of delivered refreshes.

The 30-request/second test returned roughly 30 focus acknowledgements per second, and visible movement was confirmed over both apps. This is not a measured display frame rate. All recorded AssistiveTouch, Dwell, Pointer Control and runtime gates remained false. The app and service both recorded cleanup. No XCTest session, PiP, native touch injection or accessibility-setting writes were used.

**Remaining limits:** colour is controlled by the system inspector and is currently green; the requested red colour is not implemented. This is a finite Mac-assisted visual cursor prototype, not yet a standalone phone feature, a clicking/input integration, or a completed HeyClicky-style interactive UI. Long-duration background operation is unverified.

Evidence: [small moving arrow](Evidence/device-audit-small-moving-arrow.png), [30 Hz acknowledgements and cleanup](Evidence/device-audit-smooth-console.txt), [app states and cleanup](Evidence/device-audit-smooth-app-events.json), [earlier face over hitapp](Evidence/device-audit-path-hitapp.png), [earlier face over Settings](Evidence/device-audit-path-settings.png). Implementation: [device geometry](DeviceProbe/main.m), [host controller](run_audit_overlay_probe.py).


## Physical accessibility-window hosting experiments

Added and ran two new implementations on the physical iPhone Air, with AssistiveTouch OFF:

- `--ax-window`: creates `AXUIDaemonNonInteractiveWindow` with a transparent background, compact 42-point mint buddy and adjacent diagnostic response bubble. It appeared inside Tapp Research, then disappeared on switching to hitapp. Background observations show the drawable context ID becoming 0 even though the window object remained alive. Normal window release and cleanup were recorded.
- `--ax-window --system-ui-host`: requests a UIKit system UI service role under **our own** bundle identity and ordinary signature. The window initially received a context, then background observations returned context ID 0. No buddy appeared over hitapp. The process exited with code 0 after two observations, without a recorded cleanup or deadline event; the cause is not established. Process inspection confirmed it no longer existed. This mode is an experimental negative result, not a usable service.

Signed builds passed; the latest research build installed as sequence **3760**. All recorded AssistiveTouch reads were false, and a final state-only check also found Dwell, Pointer Control and both runtime gates false. No accessibility settings, signing permissions, production hitapp code or native input were changed. The buddy/bubble is diagnostic UI, not a completed HeyClicky clone. These results further narrow the hosting problem; extending a background timer cannot restore a context the system has removed.

See [combined evidence](Evidence/device-ax-hosting-summary.json), [ordinary-window events](Evidence/device-ax-window-events.json), [system-role events](Evidence/device-system-ui-host-events.json), [system-role console](Evidence/device-system-ui-host-console.txt) and [final state](Evidence/device-after-ax-host-state.txt). The original QuartzCore displayable-context permission barrier remains. Neither new route fulfills physical cross-app Tapp.


## Latest UI decision: HeyClicky reference; PiP rejected

The owner explicitly wants the same UI as HeyClicky: a small floating buddy/cursor with nearby conversation UI. The physical iPhone must display it across apps with AssistiveTouch OFF. A video window does not meet this requirement.

The physical PiP experiment displayed over hitapp and Settings, then was stopped after the owner's rejection. `device-pip-rejected-events.json` records playback pause, audio-session deactivation and PiP stop; the five accessibility/feature getters remained false. Its source is archived in TappLab's `RejectedExperiments/PictureInPicture` and excluded from the active build. The active probe's background-audio declaration has been removed. This is a rejected mechanism, not successful Tapp delivery. All earlier physical renderer/pointer failures below remain unresolved. The cleaned signed phone build passed and installed as sequence **3744**; its built Info.plist has no background-audio mode and its project has no PiP source references. See `Evidence/device-post-pip-removal-build.txt` and `Evidence/device-post-pip-removal-install.txt`.


Independent Xcode research targets for **hitapp’s Tapp cursor**. The owner requested a cute cursor and cross-app operation with AssistiveTouch **off**.

## Current result — 2026-10-18

**Cross-app rendering works on the dedicated iPhone Air simulator. It has not succeeded on the physical iPhone.** No off-state input success or permanent cursor milestone is claimed.

**21:44 follow-up:** after unlock, both physical combinations ran: visibility/keep-alive assertions plus native HID, then the same with system pointer-scene preparation. Each Fast / 10-second loop completed **334 reports, 3 captures, no hover, no steering and no arrivals**. Both fresh in-flight frames show no cursor. Each research run recorded ten observations with visibility 0, interaction state 0 and position `{0, 0}`; no state-change callbacks arrived. All five accessibility/feature getters stayed false. Assertions cleaned up normally; scene invalidation was requested in the second run. Native mouse removal and connection closure were recorded. See [first run](Evidence/device-combined-20261018-2141-summary.json) and [scene run](Evidence/device-scene-combined-20261018-2144-summary.json), including timing limits. Neither is a physical pointer pass.

**20:00 follow-up:** the physical native-HID off-state comparison has now run: Fast / 30 seconds, 1,015 native 17-byte motion reports, 9 local captures, **no hover, no feedback steering and no target arrivals**. The final saved in-flight frame shows no cursor. Owned mouse removal and connection cleanup were recorded. The Mac preview was disconnected before motion. AssistiveTouch, Dwell, Pointer Control and both runtime feature flags were false before and after. [Result](Evidence/device-native-pointer-off-20261018.txt), [frame](Evidence/device-native-pointer-off-20261018.png), [before](Evidence/device-state-only-20261018.txt), [after](Evidence/device-state-after-native-off-20261018.txt).

[Watch the fresh simulator demonstration](Evidence/tapp-live-demo-20261018-195639.mp4): movement over Settings and the separate lab app, then centre parking on Home. [Run metadata](Evidence/20261018-195643-layer/result.json) records normal cleanup and completed recovery; external termination returned false because the probe had already exited normally.

| Environment | Observed result |
| --- | --- |
| Dedicated iPhone Air, iOS 27.0 / 24A434 | Our mint character renders over Settings, a separate app and Home with AssistiveTouch, Pointer Control and Dwell getters all false. It moves and parks centrally. A screenshot shows it still present 70 seconds after switching out, after background-task expiration. |
| Normally developer-signed iPhone Air, iOS 27.2 / 24B5089g | Both remote and local CAContext constructors return valid contexts, but requested display ID 1 reads back as 0. No character appears in the research app capture. AssistiveTouch, Pointer Control and Dwell getters are false. |
| Simulator native pointer service | Keep-alive/show assertions return objects, but position remains `{0, 0}`, visibility state 0 and client interaction false. Preparing the pointer scene did not improve this. The initial cleanup failures were subsequently traced to releasing assertions before invalidating them; both probes now explicitly invalidate first. |

The physical phone’s last observed AssistiveTouch setting is **OFF**, following the owner’s explicit request to pursue off-state operation. Dwell remains OFF. This supersedes earlier research notes about restoring an ON baseline. The updated separate diagnostic is installed (sequence 3728). Both experiments ended, the final state-only check exited normally, and hitapp was resumed with the Mac preview disconnected. No passcode entry was attempted.

## Open and reproduce

Open `TappLab.xcodeproj` in Xcode. The three schemes are independent of hitapp’s production target:

- **TappLab**: original Swift app-local motion/appearance preview; simulator-only.
- **TappOverlayProbe**: Objective-C cross-app renderer and native-service research; simulator-only.
- **TappDeviceProbe**: ordinary signed iPhone diagnostic app, installed separately as **Tapp Research** (`com.jackadamslovell.TappDeviceProbe`). No private entitlements, input dispatch or accessibility setters. Stop and a 45-second/background-expiration limit remove its renderer.

The project is generated from `project.yml` using `xcodegen`. The dedicated simulator is **Tapp Lab — iPhone Air**, UUID `07758927-591E-4941-8DED-C9ADD1369A99`. The runner refuses another device or an unbooted simulator. It uses `simctl` directly and does not operate the shared physical-phone preview.

```sh
xcodegen generate
# Boot only if this dedicated simulator is not already booted:
xcrun simctl boot 07758927-591E-4941-8DED-C9ADD1369A99
xcodebuild -project TappLab.xcodeproj -scheme TappLab -sdk iphonesimulator \
  -destination 'id=07758927-591E-4941-8DED-C9ADD1369A99' -derivedDataPath Build build
xcrun simctl install 07758927-591E-4941-8DED-C9ADD1369A99 \
  Build/Build/Products/Debug-iphonesimulator/TappLab.app
python3 run_cross_app_probe.py --mode layer
python3 run_cross_app_probe.py --mode layer-idle
```

The runner builds before installation, switches between Settings, TappLab and Home, saves screenshots and JSON, terminates the probe, then verifies recovery completed without a pending settings journal. Idle mode deliberately keeps the renderer through background expiration and ends the external observation after 70 seconds; an external runner bounds its lifetime. This is **not** permanent unattended operation. Screenshot review remains required; neither a successful command nor a context ID is a visual pass.

Other modes are `native`, `native-scene`, `interfaces`, and the simulator-only, journaled `pointer-control` experiment. The Pointer Control setter is itself feature-gated, so a call cannot establish that the setting changed. Recovery records getter readback, not an independent measurement of an underlying stored preference.

`python3 run_pointer_service_probe.py` builds the phone-style probe for the dedicated simulator, backgrounds it into Settings, requires a normal cleanup event, and externally terminates it afterwards. Add `--prepare-pointer-scene` to also verify that scene preparation and invalidation requests complete. These cover lifecycle behavior, not visibility success. [Crash diagnosis](Evidence/assertion-cleanup-crash-summary.json): releasing a live visibility assertion trapped in `-[BSSimpleAssertion dealloc]` during background expiration. Both targets now invalidate visibility and keep-alive assertions before releasing them. The latest [state-observer regression](Evidence/20261018-214027-pointer-service-cleanup/result.json) and [scene regression](Evidence/20261018-214301-pointer-scene-cleanup/result.json) passed in 31.35 and 31.86 seconds respectively. The physical combinations also recorded normal cleanup.

The [repaired cleanup run](Evidence/20261018-200621-pointer-service-cleanup/result.json) passed in 31.87 seconds: background expiration, explicit invalidation, both assertion releases, client invalidation and final cleanup were recorded in order, followed by accepted external termination. All pointer observations still returned visibility 0, interaction false and position `{0, 0}`. The phone subsequently reported `passcodeRequired: true`; no new launch is queued.

The separate [native-scene retest](Evidence/20261018-200714-native-scene/result.json) also passed normal cleanup and recovery after the same fix. It still reported no active pointer. These two passes verify lifecycle handling, not a rendering breakthrough.

Build the phone diagnostic without installing or opening it:

```sh
xcodebuild -project TappLab.xcodeproj -scheme TappDeviceProbe \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath DeviceBuild -allowProvisioningUpdates build
```

For a later physical retest, the default launch uses `remoteContextWithOptions:`; `--local-context` selects the alternate constructor. The source reports display ID during motion, both runtime feature gates, the three accessibility states, cleanup, and explicit unattached-context status. No feature-flag or entitlement bypass is implemented. `Build/`, `DeviceBuild/`, `.build/` and Xcode user state are ignored.

`--state-only` records the five read-only states and exits without creating a renderer or UIKit scene. Even `devicectl --no-activate` disturbed foreground presentation on this phone, so do not run it during personal use or an active motion test. `--pointer-service` requests only pointer visibility and keep-alive assertions, with no custom drawing or input. It logs visibility/interaction/global-position readbacks and state-change callbacks until Stop, 45 seconds, or background expiration. Add `--prepare-pointer-scene` to request a system pointer scene and invalidate it during cleanup. These modes were each combined with hitapp's existing **10-second** native mouse loop, with the Mac preview disconnected before motion. Neither activated a pointer. The native report has no per-report timestamps, so exact overlap duration is not independently established. Assertions and scene requests alone are not a visibility pass.

## Renderer and evidence

`SharedRenderer/TappGlobalRenderer.m` draws an original mint face using Core Animation layers: blinking eyes, little pink cheeks and a smile. It uses a private CAContext with `displayable`, `displayId` and `ignoresHitTest` options. The layer is noninteractive; drawing it does not generate mouse or touch input. Motion uses display coordinates and ends at the centre. It is deliberately separate from native HID units.

Primary evidence:

- **Latest repeated pass:** [result and binary hash](Evidence/20261018-184942-layer-idle/result.json), [recovery getters](Evidence/20261018-184942-layer-idle/recovery-events.json), [70-second image](Evidence/20261018-184942-layer-idle/home-after-70-seconds.png), [renderer gone after termination](Evidence/20261018-184942-layer-idle/after-termination.png). Both images were visually reviewed. External termination was accepted and recovery completed without a settings journal. Both AXAction feature getters are also false in this simulator.
- [70-second cross-app run](Evidence/20261018-184216-layer-idle/result.json), [events and off-state getters](Evidence/20261018-184216-layer-idle/events.json), [Home after 70 seconds](Evidence/20261018-184216-layer-idle/home-after-70-seconds.png), [Settings](Evidence/20261018-184216-layer-idle/settings.png), [separate app](Evidence/20261018-184216-layer-idle/second-app.png). This earlier runner recorded expected external termination as `normalCleanupObserved: false`; it did not record recovery completion. Later runner revisions distinguish those outcomes.
- [Simulator display ID 1 readback](Evidence/20261018-184458-layer/events.json).
- [Phone remote-context log](Evidence/device-renderer-properties-console.txt), [phone local-context log](Evidence/device-renderer-local-context-console.txt), [phone foreground capture with AssistiveTouch off](Evidence/device-renderer-foreground-off.png). Both phone constructors read back display ID 0.
- [Native scene attempt](Evidence/20261018-184814-native-scene/events.json), [failed normal-cleanup result](Evidence/20261018-184814-native-scene/result.json).
- [Phone signed build log](Evidence/device-renderer-build.txt).

The incomplete `20261018-183854-layer` run used an older binary after a compile failure and is not success evidence. The runner now refuses to proceed after build failure. The early Safari capture was a transition frame and is not evidence of rendering over settled Safari content.

## Why the phone remains blocked

[Offline analysis of the exact phone build](../../docs/research/assistivetouch-2026-10-18/README.md#tapp-cross-app-renderer-follow-up) recovered QuartzCore’s caller-entitlement table and registration path. `com.apple.QuartzCore.displayable-context` supplies the constructor permission bit required to honor `displayable`. Our signed diagnostic lacks it. This is strong evidence for the observed simulator/phone difference, not a completed replacement for Apple’s renderer.

The separate native-HID route and both combined phone experiments have negative results as described above. The current blocker is no demonstrated physical rendering/input route, not device unlock. Another attempt needs a different, evidenced mechanism; extending the same loop is not a fix. No cross-app click, hand activity integration, rotation, battery or indefinite lifetime was verified by this renderer work. The production app and its working native motion baseline were not edited.

The original local Swift preview still has five passing Mac motion tests (clamping, stopping, centre arrival, geometry changes and invalid inputs), plus saved [route evidence](Evidence/final-route.json). Run `swift test --jobs 2` to reproduce them; these tests do not validate global rendering.
