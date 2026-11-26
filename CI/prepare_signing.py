"""Prepare manual signing on an ephemeral GitHub-hosted Mac. Never print secrets."""
import base64
import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import subprocess
import sys

TEAM = "92X682GNVP"
PROFILES = {
    "com.jackadamslovell.PocketAgent": "IOS_APP_PROFILE_BASE64",
    "com.jackadamslovell.PocketAgent.LocalControl": "IOS_TUNNEL_PROFILE_BASE64",
    "com.jackadamslovell.PocketAgent.NativeActivity": "IOS_ACTIVITY_PROFILE_BASE64",
}
REQUIRED = ["IOS_DISTRIBUTION_P12_BASE64", "IOS_P12_PASSWORD", "ASC_API_PRIVATE_KEY",
            "ASC_KEY_ID", "ASC_ISSUER_ID", *PROFILES.values()]


def run(*args):
    result = subprocess.run(args, capture_output=True)
    if result.returncode:
        # Command arguments can contain passwords; do not emit them or stderr.
        raise RuntimeError(f"Signing command failed: {args[0]} {args[1]}")
    return result.stdout


def configure_project(text, mapping):
    counts = {bundle: 0 for bundle in mapping}

    def replace_block(match):
        block = match.group(1)
        found = re.search(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([^";\s]+)"?;', block)
        if not found or found[1] not in mapping:
            return match[0]
        bundle = found[1]
        counts[bundle] += 1
        for key in ("CODE_SIGN_STYLE", "CODE_SIGN_IDENTITY", "DEVELOPMENT_TEAM", "PROVISIONING_PROFILE_SPECIFIER"):
            block = re.sub(rf'\b{key}\s*=\s*[^;]+;', '', block)
        block += (f'\nCODE_SIGN_STYLE = Manual;\nCODE_SIGN_IDENTITY = "Apple Distribution";'
                  f'\nDEVELOPMENT_TEAM = {TEAM};\nPROVISIONING_PROFILE_SPECIFIER = "{mapping[bundle]}";\n')
        return 'buildSettings = {' + block + '};'

    result = re.sub(r'buildSettings\s*=\s*\{(.*?)\};', replace_block, text, flags=re.S)
    if any(count != 2 for count in counts.values()):
        raise ValueError("Expected Debug and Release signing settings for all three app targets.")
    return result


def main():
    temp = Path(os.environ["RUNNER_TEMP"])
    work = temp / "tapp-signing"
    manifest = work / "installed-profiles.json"
    if "--cleanup" in sys.argv:
        if manifest.exists():
            for name in json.loads(manifest.read_text()):
                Path(name).unlink(missing_ok=True)
        shutil.rmtree(work, ignore_errors=True)
        return

    missing = [name for name in REQUIRED if not os.environ.get(name)]
    if missing:
        raise ValueError("Missing GitHub secrets: " + ", ".join(missing))
    if not re.fullmatch(r"[A-Z0-9]{10}", os.environ["ASC_KEY_ID"]):
        raise ValueError("ASC_KEY_ID must be Apple's ten-character Key ID.")
    os.umask(0o077)
    work.mkdir(mode=0o700)
    p12 = work / "distribution.p12"
    p12.write_bytes(base64.b64decode(os.environ["IOS_DISTRIBUTION_P12_BASE64"], validate=True))
    keychain = str(temp / "tapp-signing.keychain-db")
    password = secrets.token_urlsafe(32)
    print(f"::add-mask::{password}")
    run("security", "create-keychain", "-p", password, keychain)
    run("security", "set-keychain-settings", "-lut", "21600", keychain)
    run("security", "unlock-keychain", "-p", password, keychain)
    run("security", "import", str(p12), "-P", os.environ["IOS_P12_PASSWORD"],
        "-k", keychain, "-T", "/usr/bin/codesign", "-T", "/usr/bin/security")
    run("security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", password, keychain)
    existing = re.findall(r'"([^"]+)"', run("security", "list-keychains", "-d", "user").decode())
    run("security", "list-keychains", "-d", "user", "-s", keychain, *existing)
    identities = run("security", "find-identity", "-v", "-p", "codesigning", keychain).decode()
    if "Apple Distribution" not in identities:
        raise ValueError("P12 does not contain a valid Apple Distribution identity with its private key.")

    locations = [Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
                 Path.home() / "Library/MobileDevice/Provisioning Profiles"]
    installed = []
    mapping = {}
    now = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
    for bundle, env in PROFILES.items():
        raw = base64.b64decode(os.environ[env], validate=True)
        profile_file = work / (env + ".mobileprovision")
        profile_file.write_bytes(raw)
        profile = plistlib.loads(run("security", "cms", "-D", "-i", str(profile_file)))
        entitlements = profile["Entitlements"]
        if profile.get("TeamIdentifier") != [TEAM] or entitlements.get("application-identifier") != TEAM + "." + bundle:
            raise ValueError("Profile does not match the expected team and bundle: " + bundle)
        if profile["ExpirationDate"] <= now:
            raise ValueError("Expired profile: " + bundle)
        if profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices") or entitlements.get("get-task-allow"):
            raise ValueError("Expected an App Store Connect distribution profile: " + bundle)
        uuid = profile["UUID"]
        if not re.fullmatch(r"[A-Fa-f0-9-]{36}", uuid):
            raise ValueError("Invalid provisioning profile UUID")
        mapping[bundle] = uuid
        for location in locations:
            location.mkdir(parents=True, exist_ok=True)
            target = location / (uuid + ".mobileprovision")
            target.write_bytes(raw)
            installed.append(str(target))
            manifest.write_text(json.dumps(installed))

    project = Path("PocketAgent.xcodeproj/project.pbxproj")
    project.write_text(configure_project(project.read_text(), mapping))
    api_key = work / ("AuthKey_" + os.environ["ASC_KEY_ID"] + ".p8")
    api_key.write_text(os.environ["ASC_API_PRIVATE_KEY"])
    options = {
        "method": "app-store-connect", "destination": "upload", "signingStyle": "manual",
        "teamID": TEAM, "signingCertificate": "Apple Distribution", "provisioningProfiles": mapping,
        "uploadSymbols": True, "manageAppVersionAndBuildNumber": False,
    }
    (work / "ExportOptions.plist").write_bytes(plistlib.dumps(options))
    print("Manual signing configured for the app and both extensions.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
