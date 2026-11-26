#!/bin/bash
# Build the pinned helper with the reviewed, status-only lifecycle patch.
# Never reset or overwrite other source edits. No installation or pairing.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
runner_source="$project_root/DeveloperTools/iCTRL"
status_source="$project_root/DeveloperTools/RunnerStatus"
runner_commit="$(sed -n 's/^commit=//p' "$project_root/DeveloperTools/ICTRL.lock")"
[[ "$(git -C "$runner_source" rev-parse HEAD)" == "$runner_commit" ]] || { echo 'Runner pin mismatch.' >&2; exit 1; }
if git -C "$runner_source" apply --reverse --check "$status_source/lifecycle.patch" 2>/dev/null; then
    echo 'Status lifecycle patch already applied.'
elif git -C "$runner_source" diff --quiet -- iCTRLUITests/iCTRLUITests.swift; then
    git -C "$runner_source" apply --check "$status_source/lifecycle.patch"
    git -C "$runner_source" apply "$status_source/lifecycle.patch"
else
    echo 'Runner lifecycle has other edits. Review them; nothing was overwritten.' >&2
    exit 1
fi
xcodegen generate --spec "$status_source/project.yml"
xcodebuild -quiet -project "$status_source/PocketRunner.xcodeproj" -scheme iCTRL \
    -derivedDataPath "$project_root/DerivedData/RunnerStatus" \
    -destination 'generic/platform=iOS' -allowProvisioningUpdates build-for-testing ARCHS=arm64
bash "$project_root/Scripts/package-runner-status.sh"
