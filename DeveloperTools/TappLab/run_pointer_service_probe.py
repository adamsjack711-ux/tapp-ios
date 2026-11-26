#!/usr/bin/env python3
"""Build and validate finite pointer-assertion cleanup on the dedicated simulator."""
from datetime import datetime
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
from zoneinfo import ZoneInfo

from run_cross_app_probe import DEVICE, ROOT, simctl

BUNDLE = 'com.jackadamslovell.TappDeviceProbe'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-pointer-scene', action='store_true')
    args = parser.parse_args()
    devices = json.loads(simctl('list', 'devices', '--json').stdout)['devices']
    device = next((d for group in devices.values() for d in group if d['udid'] == DEVICE), None)
    if not device or device['state'] != 'Booted' or device['name'] != 'Tapp Lab — iPhone Air':
        raise SystemExit('Boot the dedicated Tapp Lab — iPhone Air simulator first.')
    mode = 'pointer-scene-cleanup' if args.prepare_pointer_scene else 'pointer-service-cleanup'
    output = ROOT / 'Evidence' / (datetime.now(ZoneInfo('America/Vancouver')).strftime('%Y%m%d-%H%M%S') + '-' + mode)
    output.mkdir(parents=True)
    with (output / 'build.txt').open('w') as log:
        subprocess.run(['xcodebuild', '-project', 'TappLab.xcodeproj', '-scheme', 'TappDeviceProbe',
                        '-sdk', 'iphonesimulator', '-destination', 'id=' + DEVICE,
                        '-derivedDataPath', 'DeviceSimulatorBuild', 'CODE_SIGNING_ALLOWED=NO',
                        'build', '-quiet'], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    app = ROOT / 'DeviceSimulatorBuild/Build/Products/Debug-iphonesimulator/TappDeviceProbe.app'
    simctl('install', DEVICE, str(app))
    container = Path(simctl('get_app_container', DEVICE, BUNDLE, 'data').stdout.strip())
    report = container / 'Documents/tapp-device-probe.json'
    report.unlink(missing_ok=True)
    started = time.monotonic()
    backgrounded = cleaned = False
    scene_lifecycle = None
    try:
        options = ['--pointer-service'] + (['--prepare-pointer-scene'] if args.prepare_pointer_scene else [])
        print(simctl('launch', DEVICE, BUNDLE, *options).stdout.strip(), flush=True)
        while time.monotonic() - started < 55:
            events = json.loads(report.read_text()) if report.exists() else []
            if any(e['event'] == 'pointer-service-request' for e in events) and not backgrounded:
                simctl('launch', DEVICE, 'com.apple.Preferences')
                backgrounded = True
                print('Backgrounded research app; observing explicit assertion cleanup.', flush=True)
            if any(e['event'] == 'cleanup' for e in events):
                cleaned = True
                break
            time.sleep(0.5)
    finally:
        termination = simctl('terminate', DEVICE, BUNDLE, check=False)
        if report.exists():
            (output / 'events.json').write_text(report.read_text())
            saved = json.loads(report.read_text())
            if args.prepare_pointer_scene:
                scene_lifecycle = (
                    any(e['event'] == 'pointer-scene-requested' and e['details']['clientCreated'] for e in saved)
                    and any(e['event'] == 'pointer-scene-invalidation-requested' for e in saved)
                    and not any('exception' in e['event'] for e in saved)
                )
        (output / 'result.json').write_text(json.dumps({
            'device': DEVICE, 'physicalPhoneContacted': False, 'inputDispatched': False,
            'requestedPointerScene': args.prepare_pointer_scene,
            'sceneRequestAndCleanupObserved': scene_lifecycle,
            'backgrounded': backgrounded, 'normalCleanupObserved': cleaned,
            'externalTerminationAccepted': termination.returncode == 0,
            'elapsedSeconds': round(time.monotonic() - started, 2),
            'debugCodeSHA256': hashlib.sha256((app / 'TappDeviceProbe.debug.dylib').read_bytes()).hexdigest(),
            'visibilitySuccess': 'Not established by this lifecycle test',
        }, indent=2) + '\n')
    print('Evidence:', output)
    if not (backgrounded and cleaned) or (args.prepare_pointer_scene and not scene_lifecycle):
        raise SystemExit('Assertion cleanup did not pass; inspect saved events.')


if __name__ == '__main__':
    main()
