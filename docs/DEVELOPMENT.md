# Developing Tapp

[← Tapp](../README.md) · [Documentation](README.md)

iOS app project for Jack and Lalith. The hosted backend implementation is not included. The Xcode project and source folders still use the internal name PocketAgent. The app display name in this source is Tapp. The previously installed build used hitapp; a new build must be installed to update the device name. The App Store Connect record was last documented as Tapp.ai; this local rename does not change that record.

Run the commands below from the repository root.

## Working from Windows

Clone this repository with GitHub Desktop, or run:

```sh
git clone https://github.com/adamsjack711-ux/tapp-ios.git
cd tapp-ios
git switch -c your-change
```

Edit the source in your preferred editor, commit your changes, push the branch, and open a pull request. You can also download a snapshot from Code > Download ZIP, but cloning makes it easier to send changes back.

Windows can edit and push the code. GitHub Actions uses a hosted Mac to test and compile changes. After the Apple signing credentials are configured, pushes to `main` also build and upload to TestFlight. Jack's Mac does not need to be online. See [the cloud build guide](../CI/README.md) for setup and release status.

## Opening on a Mac

Open `PocketAgent.xcodeproj` and select the `PocketAgent` scheme. The source project was last used with Xcode 27.1. The local `DeveloperTools/rork-device` package is included; Xcode resolves its remote Swift package dependencies on first use.

For a simulator run, select an iPhone simulator. Configure your own model service in the app settings; local service addresses in older notes and scripts describe Jack's setup.

Core tests can be run from the repository root on a Mac:

```sh
swift test
```

## Reporting a bug during the beta

With your Tapp backend URL and your own beta access code configured, open
Settings → Help → Report a bug. Enter a summary and what happened, then send it.
You can turn off the optional app/device information before sending. The success
screen shows a reference ID. If delivery is uncertain, retry in the same form to
avoid creating a duplicate report.

Reports use your existing beta account and do not spend AI allowance. Screenshots,
conversations and logs are not attached. Leave out credentials and private information.
The backend retains reports for 30 days and erases them on account deletion. It
accepts up to 10 new reports per account per UTC day.

Requires the backend's `POST /v1/bug-reports` endpoint and a new app build containing
this form. Administrators read reports on the backend host with
`npm run account -- reports [ACCOUNT_ID]`.

## Uploading updates

App Store Connect: https://appstoreconnect.apple.com/apps/6824725354/distribution

Keep these bundle identifiers unchanged for updates:

- App: `com.jackadamslovell.PocketAgent`
- Local control extension: `com.jackadamslovell.PocketAgent.LocalControl`
- Live Activity extension: `com.jackadamslovell.PocketAgent.NativeActivity`

Lalith must accept the App Store Connect invitation. App Manager access permits uploads and release management, but Jack's Individual membership does not give invited users automatic access to certificates and profiles.

Distribution signing is still pending. The cloud workflow is prepared to use an Apple Distribution certificate, matching profiles for all three bundle IDs, and an App Store Connect API key stored in GitHub secrets. See [CI/README.md](../CI/README.md). Keep signing private keys, distribution certificates, provisioning profiles, API keys, and pairing records out of Git.

After cloud signing is configured, the workflow increments the build number, archives the app, and uploads it to App Store Connect. Apple then processes it for TestFlight. Public App Store submission remains a separate step.

## Included source and dependencies

The app, both extensions, assets, tests, scripts, developer tools, and local rork-device source are included. Third-party license files are preserved. The PEM files under the rork-device test fixtures are unchanged upstream test data, not personal signing credentials.

Build products, caches, virtual environments, device evidence, user-specific Xcode state, and nested Git histories are excluded. The optional legacy iCTRL framework binary is excluded from the source package. If working on that separate tool, restore it on a Mac with:

```sh
bash DeveloperTools/iCTRL/Scripts/fetch-idevice.sh
```

Existing project history and engineering notes are in `DEVELOPMENT_NOTES.md` and `ROADMAP.md`. They include historical experiments and are not a guarantee that every feature is ready for App Store review.
