# Cloud builds

GitHub Actions runs on an Apple Silicon Mac hosted by GitHub. The workflow uses the stable Xcode 27 installation, so Jack's Mac does not need to be online.

## From Windows

1. Accept the GitHub repository invitation and clone the project.
2. Make changes on a branch and open a pull request. GitHub runs the core tests and compiles the iPhone simulator app and both extensions.
3. Merge into `main`. Once TestFlight signing is activated, the same workflow also creates a signed device archive and uploads it to App Store Connect.
4. Check the Actions page for progress, then TestFlight after Apple processes the build.

You can also use Actions > iOS build and TestFlight > Run workflow on `main`. Uploads never run for pull requests or other branches. The simulator artifact is for use with an iOS Simulator on a Mac; it is not an installable iPhone app. Public App Store submission remains a separate action in App Store Connect.

## Activation

Apple API access and distribution signing must be configured before uploads can run. Build/test jobs work without these credentials. The `testflight` job is disabled until the repository variable `TESTFLIGHT_ENABLED` is exactly `true`.

Store these encrypted secrets in the repository's `testflight` environment (or as repository Actions secrets):

| Secret | Value |
| --- | --- |
| `IOS_DISTRIBUTION_P12_BASE64` | Base64 of the Apple Distribution certificate and private key exported as a password-protected P12 |
| `IOS_P12_PASSWORD` | P12 export password |
| `IOS_APP_PROFILE_BASE64` | Base64 App Store Connect profile for `com.jackadamslovell.PocketAgent` |
| `IOS_TUNNEL_PROFILE_BASE64` | Base64 App Store Connect profile for `com.jackadamslovell.PocketAgent.LocalControl` |
| `IOS_ACTIVITY_PROFILE_BASE64` | Base64 App Store Connect profile for `com.jackadamslovell.PocketAgent.NativeActivity` |
| `ASC_API_PRIVATE_KEY` | Full contents of the App Store Connect API `.p8` key |
| `ASC_KEY_ID` | API key ID |
| `ASC_ISSUER_ID` | API issuer ID |

All three profiles must use the same distribution certificate and team `92X682GNVP`. The main app and LocalControl extension require the Network Extensions capability matching `PocketControlTunnel/LocalControl.entitlements`. Register any missing extension identifiers before generating profiles. An API key with the Developer role is sufficient for build uploads; it does not need Admin access.

After adding the secrets, set `TESTFLIGHT_ENABLED=true`, dispatch the workflow on `main`, and verify an actual upload. Until that succeeds, uploading is not verified. API keys are downloaded only once from Apple. Certificates and provisioning profiles expire and must be replaced in GitHub secrets when renewed.

## Operation

Each release uses `(100 + workflow run number).attempt.0` as its build number, shared by all app targets. Rerunning a workflow increments the attempt. The script stops if Apple's component limits would be exceeded. GitHub imports signing material into a temporary keychain and removes it after the job. Signing files and archives are never published as Actions artifacts. Only the unsigned simulator app is retained, for seven days.

People who can change workflows on `main` can use the release credentials. Repository write access is therefore trusted release access. GitHub-hosted Mac jobs consume the account's Actions allowance; existing billing limits remain in effect.
