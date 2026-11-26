#!/usr/bin/env python3
"""Finite, simulator-only Tapp system-pointer experiment. Never targets a phone."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

DEVICE = '07758927-591E-4941-8DED-C9ADD1369A99'
BUNDLE = 'com.hitapp.research.TappOverlayProbe'
ROOT = Path(__file__).resolve().parent


def simctl(*args, check=True):
    return subprocess.run(['xcrun', 'simctl', *args], check=check, text=True, capture_output=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['native', 'pointer-control', 'interfaces', 'layer', 'layer-idle', 'native-scene'], default='native')
    args = parser.parse_args()
    devices = json.loads(simctl('list', 'devices', '--json').stdout)['devices']
    device = next((d for group in devices.values() for d in group if d['udid'] == DEVICE), None)
    if not device or device['state'] != 'Booted' or device['name'] != 'Tapp Lab — iPhone Air':
        raise SystemExit('Boot the dedicated Tapp Lab — iPhone Air simulator first.')
    with (ROOT / 'Evidence/overlay-build.txt').open('w') as log:
        subprocess.run(['xcodebuild', '-project', 'TappLab.xcodeproj', '-scheme', 'TappOverlayProbe', '-sdk', 'iphonesimulator', '-destination', 'id=' + DEVICE, '-derivedDataPath', 'Build', 'build', '-quiet'], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    app = ROOT / 'Build/Build/Products/Debug-iphonesimulator/TappOverlayProbe.app'
    if not app.exists():
        raise SystemExit('Build the TappOverlayProbe scheme first.')
    simctl('install', DEVICE, str(app))
    container = Path(simctl('get_app_container', DEVICE, BUNDLE, 'data').stdout.strip())
    report = container / 'Documents/overlay-probe.json'
    report.unlink(missing_ok=True)
    output = ROOT / 'Evidence' / (time.strftime('%Y%m%d-%H%M%S') + '-' + args.mode)
    output.mkdir(parents=True)
    arguments = [] if args.mode == 'interfaces' else ['--native-pointer']
    if args.mode in ('layer', 'layer-idle'):
        arguments = ['--global-layer']
        if args.mode == 'layer-idle':
            arguments.append('--idle-persistence')
    if args.mode == 'native-scene':
        arguments.append('--prepare-pointer-scene')
    if args.mode == 'pointer-control':
        arguments.append('--pointer-control')
    switched_at = None
    app_stage = 0
    switched = False
    captured = False
    cleaned = False
    started = time.monotonic()
    try:
        print(simctl('launch', DEVICE, BUNDLE, *arguments).stdout.strip(), flush=True)
        while time.monotonic() - started < (85 if args.mode == 'layer-idle' else 55):
            events = json.loads(report.read_text()) if report.exists() else []
            if any(e['event'] in ('native-request', 'host-interface', 'global-layer-request', 'global-context-missing') for e in events) and not switched:
                simctl('io', DEVICE, 'screenshot', str(output / 'foreground.png'))
                simctl('launch', DEVICE, 'com.apple.Preferences')
                switched = True
                switched_at = time.monotonic()
                print('Switched to Settings; checking for a visible cross-app cursor.', flush=True)
            observations = [e for e in events if e['event'] == 'native-observation']
            elapsed = time.monotonic() - switched_at if switched_at else 0
            if switched and not captured and (len(observations) >= 4 or (elapsed >= 4 and args.mode in ('interfaces', 'layer', 'layer-idle'))):
                simctl('io', DEVICE, 'screenshot', str(output / 'settings.png'))
                captured = True
            if args.mode in ('layer', 'layer-idle') and switched:
                if elapsed >= 8 and app_stage == 0:
                    simctl('launch', DEVICE, 'com.hitapp.research.TappLab')
                    app_stage = 1
                elif elapsed >= 12 and app_stage == 1:
                    simctl('io', DEVICE, 'screenshot', str(output / 'second-app.png'))
                    simctl('terminate', DEVICE, 'com.hitapp.research.TappLab')
                    app_stage = 2
                elif elapsed >= 16 and app_stage == 2:
                    simctl('io', DEVICE, 'screenshot', str(output / 'home.png'))
                    app_stage = 3
                elif elapsed >= 70 and app_stage == 3 and args.mode == 'layer-idle':
                    simctl('io', DEVICE, 'screenshot', str(output / 'home-after-70-seconds.png'))
                    app_stage = 4
                    break
            if any(e['event'] in ('deadline-cleanup', 'background-expiration-cleanup') for e in events):
                cleaned = True
                break
            time.sleep(0.5)
    finally:
        # Idle mode deliberately needs external termination after its bounded observation.
        termination = simctl('terminate', DEVICE, BUNDLE, check=False)
        (output / 'termination.txt').write_text(termination.stdout + termination.stderr)
        if report.exists():
            (output / 'events.json').write_text(report.read_text())
        simctl('io', DEVICE, 'screenshot', str(output / 'after-termination.png'), check=False)
        # Startup recovers any journaled Pointer Control value before returning.
        recovery = simctl('launch', DEVICE, BUNDLE, '--restore-state', check=False)
        (output / 'recovery-launch.txt').write_text(recovery.stdout + recovery.stderr)
        recovered = False
        for _ in range(20):
            recovery_events = json.loads(report.read_text()) if report.exists() else []
            if any(e['event'] == 'recovery-finished' for e in recovery_events):
                recovered = not (container / 'Documents/pointer-control-original.json').exists()
                (output / 'recovery-events.json').write_text(json.dumps(recovery_events, indent=2))
                break
            time.sleep(0.1)
        (output / 'result.json').write_text(json.dumps({
            'device': DEVICE, 'mode': args.mode, 'switchedToSettings': switched,
            'settingsScreenshotCaptured': captured, 'normalCleanupObserved': cleaned,
            'externalTerminationAccepted': termination.returncode == 0,
            'recoveryFinishedWithoutJournal': recovered,
            'elapsedSeconds': round(time.monotonic() - started, 2),
            'binarySHA256': hashlib.sha256((app / 'TappOverlayProbe').read_bytes()).hexdigest(),
            'debugCodeSHA256': hashlib.sha256((app / 'TappOverlayProbe.debug.dylib').read_bytes()).hexdigest(),
            'visualSuccess': 'requires screenshot review; request/assertion existence is not success',
        }, indent=2))
    print(f'Evidence: {output}', flush=True)
    if not cleaned and args.mode != 'layer-idle':
        raise SystemExit('Probe did not report normal cleanup; recovery requested, inspect evidence.')
    if not recovered:
        raise SystemExit('Recovery did not finish without a pending journal; inspect evidence.')
    if args.mode == 'layer-idle' and (app_stage != 4 or termination.returncode != 0):
        raise SystemExit('Idle observation or external termination failed; inspect evidence.')


if __name__ == '__main__':
    main()
