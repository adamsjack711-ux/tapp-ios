# Tapp at AppFusion

Tapp is an iPhone assistant for people who prefer speaking a request to tapping through several menus. The AppFusion category is **Community and Accessibility**.

## Submission copy

**App name:** Tapp

**Problem:** People who prefer voice input still have to open an app, find the right control and type a query to do a simple search. Tapp lets them speak the request and shows the outcome in the destination app.

**Core feature:** A spoken search request starts an iPhone task. Tapp opens the target app, finds Search, enters the query and checks the result. The October 30 physical iPhone recording shows this flow in Spotify using the query “Daft Punk.”

**AI feature:** OpenAI services interpret the voice request and use the current screen to select and check the next action. The team should confirm the exact voice and visual model identifiers for the build it records.

**What existed before November 20:** The Tapp iOS app and backend, voice input, phone-task navigation and verification, including the recorded Spotify flow.

**What changed during AppFusion:** The AppFusion materials include editing footage, screenshots, an editable pitch deck, and a repeatable acceptance and recording plan. Before filing, add the exact app changes made during the event and the build or commit that contains them.

## Download and run Tapp

Use the **Current build** download on the [AppFusion preview release](https://github.com/LALITH-GAUTAM/appfusion-hackathon/releases/tag/tapp-appfusion-preview). GitHub access to this private repository is required.

On an Apple silicon Mac with Xcode 27.1 and an iOS 27 simulator, unzip the download and boot an iPhone in Simulator. Run these commands from the extracted folder with one simulator booted.

```sh
xcrun simctl install booted ./Tapp.app
xcrun simctl launch booted com.jackadamslovell.Tapp
```

The app opens without an access code. To try live AI, open **Settings → Account**, paste the privately supplied **Tapp access code**, then tap **Connect Tapp**. When the account shows **Connected**, return to chat. This build runs in Simulator. For the physical iPhone flow, see the [recorded Spotify demo](demo-footage/Tapp-Spotify-Phone-Capture.mp4). The team's physical-device setup uses Developer Mode and Wi-Fi.

## Presentation files

- [Editable four-slide deck](Tapp-AppFusion.pptx)
- [Existing iPhone footage and editing notes](demo-footage/)
- [November 23 simulator gallery](../README.md#inside-tapp) · Welcome, home, and the dark-mode composer
- October 30 iPhone recording stills · [Voice request](screenshots/01-voice-request.png) · [Spotify Search](screenshots/02-spotify-search.png) · [Matching results](screenshots/03-search-results.png)

## Verification so far

- The October 30 physical iPhone run completed the Spotify task and verified the exact typed text. The source trace recorded about 36 seconds. The editing clips shorten the waits.
- The November 22 local iOS integration baseline (`b4df7fb`) passed 956 Swift tests in 104 suites. This evidence covers the tested core code. Live voice, Spotify, connectivity and Stop still need their final device checks on the submission build.

## Final build check and recording plan

1. On an iPhone with a demo account, note the exact Tapp build number. Start from Tapp, say “Open up Spotify and search for Daft Punk,” and capture the request, the transition, the exact typed query and matching results. Record the real elapsed time and mark any cuts.
2. Try a spoken prompt that omits the search term. Check whether Tapp asks for it or shows a clear way to recover. Note the actual result and any change made after testing.
3. Repeat with connectivity disabled. Check the message and that the user can regain control. Reconnect and try again.
4. Use Stop during a task and verify that screen actions end. On the demo account, check that text, status and Stop are readable in the recording.
5. Make a 2–3 minute video. Use the October recording as a dated before example, explain what changed during the event, and show the current build's working core and AI flow. Include three to five app screenshots. The three Spotify stills show the prior build.
6. Put the final video, screenshots and deck into one Google Drive folder. Set access to “Anyone with the link can view.” Confirm that the Drive and submitted repo links both open for a judge. This team repo is currently private.
7. Confirm the registered team name, full names and contact email. File the form Monday, November 23, by 2:00 p.m. Kamloops time.

[Official AppFusion guide](https://aiclubtrusu.vercel.app/events/appfusion/guide) · [Submission form](https://aiclubtrusu.vercel.app/events/appfusion/submit)
