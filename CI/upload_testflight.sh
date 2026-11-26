#!/bin/bash
set -euo pipefail

# Apple permits four digits in the first component and two in the others.
# Attempts distinguish reruns; the offset keeps CI above the initial build 1.
build_major=$((100 + GITHUB_RUN_NUMBER))
if (( build_major > 9999 || GITHUB_RUN_ATTEMPT > 99 )); then
  echo 'Build number range exhausted; update the version numbering before uploading.' >&2
  exit 1
fi
build_number="$build_major.$GITHUB_RUN_ATTEMPT.0"
archive="$RUNNER_TEMP/Tapp.xcarchive"
signing="$RUNNER_TEMP/tapp-signing"

xcodebuild archive \
  -project PocketAgent.xcodeproj -scheme PocketAgent \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$archive" -derivedDataPath "$RUNNER_TEMP/TappRelease" \
  -onlyUsePackageVersionsFromResolvedFile \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='Apple Distribution'

xcodebuild -exportArchive \
  -archivePath "$archive" -exportPath "$RUNNER_TEMP/TappExport" \
  -exportOptionsPlist "$signing/ExportOptions.plist" \
  -authenticationKeyPath "$signing/AuthKey_${ASC_KEY_ID}.p8" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

{
  echo '### Uploaded to App Store Connect'
  echo "Build: $build_number"
  echo 'Apple still needs to process the build before it appears in TestFlight.'
  echo 'https://appstoreconnect.apple.com/apps/6824725354/testflight'
} >> "$GITHUB_STEP_SUMMARY"
