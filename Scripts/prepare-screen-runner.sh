#!/bin/bash
# Fetch the exact reviewed runner source; do not overwrite an existing checkout.
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
runner_path="$project_root/DeveloperTools/iCTRL"
runner_commit="$(sed -n 's/^commit=//p' "$project_root/DeveloperTools/ICTRL.lock")"
mode="${1:---check}"
if [[ "$mode" != "--check" && "$mode" != "--build" ]]; then
    echo "Usage: bash Scripts/prepare-screen-runner.sh [--check|--build]" >&2
    exit 2
fi
if [[ ! "$runner_commit" =~ ^[a-f0-9]{40}$ ]]; then
    echo "Invalid pinned revision in DeveloperTools/ICTRL.lock" >&2
    exit 1
fi
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
    echo "Full Xcode with the iOS SDK is required. Install Xcode, launch it once, and select its Command Line Tools in Xcode Settings > Locations." >&2
    exit 1
fi
if ! command -v xcodegen >/dev/null; then
    echo "XcodeGen is required: brew install xcodegen" >&2
    exit 1
fi
if [[ ! -d "$runner_path/.git" ]]; then
    if [[ "$mode" == "--check" ]]; then
        echo "Runner source is missing. Run this script with --build to fetch the pinned revision."
        exit 1
    fi
    if [[ -e "$runner_path" ]]; then
        echo "An unrelated path exists at $runner_path. Nothing was replaced." >&2
        exit 1
    fi
    git clone --no-checkout https://github.com/OpenMinis/iCTRL.git "$runner_path"
    git -C "$runner_path" checkout --detach "$runner_commit"
fi
if [[ "$(git -C "$runner_path" rev-parse HEAD)" != "$runner_commit" ]]; then
    echo "Runner revision differs from the lock file. Nothing was reset or overwritten." >&2
    exit 1
fi
if [[ -n "$(git -C "$runner_path" status --porcelain -- . ':!iCTRLKit/BuildStamp.swift')" ]]; then
    echo "Runner checkout has local changes. Review them before building; nothing was changed." >&2
    exit 1
fi
# Upstream make build regenerates this tracked timestamp; it is not a source edit.
echo "Runner source verified at $runner_commit"
if [[ "$mode" == "--check" ]]; then
    echo "Prerequisites found. Signing, provisioning and on-device behavior still require verification."
    exit 0
fi
# Upstream builds a companion app plus its separately signed XCUITest runner.
# Its build downloads the idevice framework and may request provisioning updates.
# Configure your Apple development team in Xcode first; never embed credentials here.
make -C "$runner_path" build
echo "Build finished. Open DeveloperTools/iCTRL/iCTRL.xcodeproj, select your iPhone and Product > Test."
echo "Then run PocketAgent.xcodeproj on that same phone and pair in Screen Control."
