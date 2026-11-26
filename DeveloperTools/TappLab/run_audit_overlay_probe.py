#!/usr/bin/env python3
"""Finite physical-device audit-highlight experiment, never a Tapp success test.

Uses an existing trusted developer connection. No accessibility setting writes,
element activation, XCTest session, or reset-to-default-settings operation.
"""
import asyncio
import fcntl
import json
import os
import time
from pathlib import Path

from pymobiledevice3.remote.native_tunnel import NativeRemotedTunnel
from pymobiledevice3.remote.core_device.app_service import AppServiceService
from pymobiledevice3.services.accessibilityaudit import AccessibilityAudit, Direction, deserialize_object

OUTPUT = Path(__file__).parent / ('Evidence/device-audit-overlay-' + time.strftime('%Y%m%d-%H%M%S') + '-events.json')
events = []

def record(event, **details):
    events.append(dict(event=event, time=time.time(), details=details))
    OUTPUT.write_text(json.dumps(events, indent=2) + '\n')
    print(event, details, flush=True)

async def invoke(audit, selector, *args, reply=False):
    return await asyncio.wait_for(audit._invoke(selector, *args, expects_reply=reply), 5)

async def focus(audit, stage):
    await audit._ensure_ready()
    while not audit._event_queue.empty():
        audit._event_queue.get_nowait()
    iterator = audit.iter_elements()
    found = []
    try:
        async with asyncio.timeout(10):
            async for element in iterator:
                record('focus-acknowledged', stage=stage, caption=element.caption,
                       identifier=element.platform_identifier)
                if element.caption and ('Tapp audit geometry' in element.caption or 'Tapp alternate geometry' in element.caption):
                    found.append(element)
                    if len(found) == (2 if os.environ.get('TAPP_AUDIT_TWO') else 1):
                        return found
    except Exception as error:
        record('focus-unconfirmed', stage=stage, error=type(error).__name__ + ': ' + str(error))
    finally:
        await iterator.aclose()
    return found

def serialized_element(element):
    return {'ObjectType':'AXAuditElement_v1','Value':{
        'ObjectType':'passthrough','Value':{'PlatformElementValue_v1':{
            'ObjectType':'passthrough','Value':element.element.identifier}}}}

def drain_focus(audit, stage):
    captions = []
    while not audit._event_queue.empty():
        name, args = audit._event_queue.get_nowait()
        if name == 'hostInspectorCurrentElementChanged:':
            value = deserialize_object(audit._extract_event_payload(args))
            for item in value if isinstance(value,list) else [value]:
                captions.append(getattr(item,'caption',None))
    if captions:
        record('refresh-focus-events', stage=stage, count=len(captions), captions=sorted(set(c for c in captions if c)))

async def probe():
    async with NativeRemotedTunnel(serial='00008150-000A20360212401C') as rsd:
        async with AppServiceService(rsd) as apps, AccessibilityAudit(rsd) as audit:
            initial = await invoke(audit, 'deviceCurrentState', reply=True)
            record('initial-state', value=initial)
            if initial != 0:
                record('skipped-existing-audit-session')
                return
            try:
                result = await asyncio.wait_for(apps.launch_application(
                    'com.jackadamslovell.TappDeviceProbe', arguments=['--audit-path'] +
                    (['--audit-two-elements'] if os.environ.get('TAPP_AUDIT_TWO') else []) +
                    (['--audit-smooth'] if os.environ.get('TAPP_AUDIT_SMOOTH') else [])), 8)
                record('research-app-launched', result=result)
                await asyncio.sleep(2)
                await invoke(audit, 'deviceInspectorEnable:', True)
                await audit.set_app_monitoring_enabled(True)
                pid = int(result['processToken']['processIdentifier'])
                await invoke(audit, 'deviceSetAuditTargetPid:', pid)
                record('research-target-selected', pid=pid)
                await audit.set_show_visuals(True)
                await invoke(audit, 'deviceEnableHighlight:', True)
                elements = await focus(audit, 'research')
                record('research-highlight-requested', visibilityVerified=False)
                await asyncio.sleep(5)
                await asyncio.wait_for(apps.launch_application(
                    'com.jackadamslovell.PocketAgent', kill_existing=False), 8)
                await asyncio.sleep(2)
                if elements:
                    serialized = serialized_element(elements[0])
                    await invoke(audit, 'deviceInspectorFocusOnElement:', serialized)
                    record('background-own-element-focus-requested', identifier=elements[0].platform_identifier)
                record('hitapp-highlight-requested', visibilityVerified=False)
                if elements:
                    for stage, bundle in [('hitapp', None), ('settings', 'com.apple.Preferences')]:
                        if bundle:
                            await asyncio.wait_for(apps.launch_application(bundle, kill_existing=False), 8)
                            await asyncio.sleep(2)
                        record('refresh-stage', stage=stage)
                        rate = 30 if os.environ.get('TAPP_AUDIT_SMOOTH') else 1
                        started = asyncio.get_running_loop().time()
                        for step in range(10 * rate):
                            if os.environ.get('TAPP_AUDIT_REFRESH') == 'next':
                                await audit.move_focus_next()
                            else:
                                serialized = serialized_element(elements[step % len(elements)])
                                await invoke(audit, 'deviceInspectorFocusOnElement:', serialized)
                            if step % rate == 0:
                                record('background-refocus', stage=stage, step=step,
                                       elapsed=asyncio.get_running_loop().time()-started, requestedRate=rate)
                            await asyncio.sleep(max(0, started+(step+1)/rate-asyncio.get_running_loop().time()))
                            if rate == 1 or step % rate == 0:
                                drain_focus(audit, stage)
            finally:
                # Only undo inspector presentation/monitoring from this session.
                for selector, args in [
                    ('deviceInspectorShowVisuals:', (0,)),
                    ('deviceEnableHighlight:', (False,)),
                    ('deviceSetAppMonitoringEnabled:', (False,)),
                    ('deviceInspectorEnable:', (False,)),
                    ('devicePerformFinalCleanup', ()),
                ]:
                    try:
                        await invoke(audit, selector, *args)
                        record('cleanup-request', selector=selector)
                    except Exception as error:
                        record('cleanup-request-failed', selector=selector, error=str(error))
                record('final-state', value=await invoke(audit, 'deviceCurrentState', reply=True))
    record('connections-closed')

async def main():
    try:
        await asyncio.wait_for(probe(), 55)
    except Exception as error:
        record('probe-error', type=type(error).__name__, error=str(error))
        raise

if __name__ == '__main__':
    with (Path(__file__).parent / 'Evidence/.audit-probe.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        asyncio.run(main())
