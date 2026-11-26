#!/usr/bin/env python3
"""Paired-Mac rendering companion for the Tapp controls inside hitapp.

Only reads/writes Tapp's named state files in hitapp's container. No input,
screenshots, network listener, accessibility toggles, or model credentials.
Run while using Tapp; Control-C closes the inspector presentation.
"""
import asyncio
import contextlib
import fcntl
import json
import time
from pathlib import Path
from collections import deque

from pymobiledevice3.remote.native_tunnel import NativeRemotedTunnel
from pymobiledevice3.remote.core_device.app_service import AppServiceService
from pymobiledevice3.remote.core_device.file_service import FileServiceService, Domain
from pymobiledevice3.services.accessibilityaudit import AccessibilityAudit, Direction, deserialize_object

ROOT = Path(__file__).parent
BUNDLE = 'com.jackadamslovell.PocketAgent'
REFRESH_HZ = 120
CONNECT_TIMEOUT = 12
CLOSE_TIMEOUT = 2
RETRY_MAX = 8

def log(event, **details):
    print(json.dumps(dict(event=event,time=time.time(),**details)),flush=True)

@contextlib.asynccontextmanager
async def connected_resource(resource):
    """Bound connection and teardown, including a partially opened service."""
    try:
        async with asyncio.timeout(CONNECT_TIMEOUT):
            connected = await resource.__aenter__()
        yield connected
    finally:
        try:
            async with asyncio.timeout(CLOSE_TIMEOUT):
                await resource.__aexit__(None, None, None)
        except Exception as error:
            log('connection-close-error', error=type(error).__name__)

async def invoke(audit, name, *args, reply=False):
    return await asyncio.wait_for(audit._invoke(name,*args,expects_reply=reply),5)

async def read_state(files):
    raw = await asyncio.wait_for(files.get_file_contents('Documents/tapp-session.json'),4)
    if len(raw)>4096:
        raise ValueError('Oversized Tapp state')
    value = json.loads(raw)
    if not isinstance(value,dict) or not isinstance(value.get('session'),str):
        raise ValueError('Invalid Tapp session')
    return value

def serialize(element):
    return {'ObjectType':'AXAuditElement_v1','Value':{'ObjectType':'passthrough','Value':{
        'PlatformElementValue_v1':{'ObjectType':'passthrough','Value':element.element.identifier}}}}

async def write_heartbeat(files, session, active, sequence, **extra):
    data=json.dumps(dict(session=session,active=active,sequence=sequence,time=time.time(),**extra)).encode()
    await asyncio.wait_for(files.set_file_contents('Documents/tapp-host.tmp',data),4)
    await asyncio.wait_for(files.rename('Documents/tapp-host.tmp','Documents/tapp-host.json'),4)

async def render_session(rsd, files, first):
    session=first['session']
    state=dict(first)
    stopping=False
    sent=0
    acknowledged=0
    acknowledged_sequence=-1
    renderer_ready=False
    renderer_hidden=False
    async with connected_resource(AppServiceService(rsd)) as apps, connected_resource(AccessibilityAudit(rsd)) as audit:
        initial=await invoke(audit,'deviceCurrentState',reply=True)
        if initial != 0:
            raise RuntimeError('Another accessibility inspector session is active')
        processes=await asyncio.wait_for(apps.list_processes(),5)
        own=[p for p in processes if str(p.get('executableURL',{}).get('relative','')).endswith('/PocketAgent.app/PocketAgent')]
        if len(own)!=1:
            raise RuntimeError('Could not identify the running hitapp process')
        pid=int(own[0]['processIdentifier'])
        monitor=None
        try:
            await invoke(audit,'deviceInspectorEnable:',True)
            await asyncio.wait_for(audit.set_app_monitoring_enabled(True),5)
            await invoke(audit,'deviceSetAuditTargetPid:',pid)
            await asyncio.wait_for(audit.set_show_visuals(True),5)
            await invoke(audit,'deviceEnableHighlight:',True)
            found={}
            # Our cursor elements are the final siblings outside the scrolling
            # Form. Do not traverse every control: focus traversal scrolls UI.
            await asyncio.wait_for(audit.set_monitored_event_type(),5)
            while not audit._event_queue.empty():
                audit._event_queue.get_nowait()
            direction=Direction.Next
            for _ in range(12):
                await asyncio.wait_for(audit.move_focus(direction),5)
                async with asyncio.timeout(4):
                    while True:
                        name,args=await audit._event_queue.get()
                        if name!='hostInspectorCurrentElementChanged:':
                            continue
                        value=deserialize_object(audit._extract_event_payload(args))
                        candidates=value if isinstance(value,list) else [value]
                        for element in candidates:
                            caption=getattr(element,'caption','')
                            log('tapp-discovery-focus',caption=caption)
                            if not caption or not caption.startswith(tuple(f'Tapp cursor {n}' for n in 'ABCD')):
                                continue
                            if int.from_bytes(element.element.identifier[:4],'little')!=pid:
                                continue
                            found[caption]=serialize(element)
                            log('tapp-cursor-found',caption=caption)
                            # Aura can expose A first rather than D. Walk
                            # inward from either end instead of leaving the
                            # cursor group and traversing the composer.
                            if caption.startswith('Tapp cursor A'):
                                direction=Direction.Next
                            elif caption.startswith('Tapp cursor D'):
                                direction=Direction.Previous
                        if not any(getattr(e,'caption','').startswith('Tapp cursor ') for e in candidates if getattr(e,'caption','')):
                            direction=Direction.Previous
                        break
                if len(found)==4:
                    break
            if len(found)<2:
                raise RuntimeError('Tapp accessibility elements were not found; enable Tapp in hitapp')
            elements=list(found.values())
            log('tapp-connected',session=session,pid=pid,requestedRate=REFRESH_HZ,refreshWindow=len(elements))

            async def monitor_state():
                nonlocal state,stopping
                try:
                    last_heartbeat=0
                    last_presentation=None
                    while True:
                        incoming=await read_state(files)
                        if not incoming.get('enabled') or incoming['session']!=session:
                            stopping=True
                            return
                        state=incoming
                        presentation=(acknowledged_sequence,renderer_ready,renderer_hidden,bool(state.get('idle')))
                        if presentation!=last_presentation or time.monotonic()-last_heartbeat>=0.5:
                            await write_heartbeat(files,session,True,acknowledged_sequence,
                                                  sent=sent,acknowledged=acknowledged,idle=bool(state.get('idle')),
                                                  rendererReady=renderer_ready,rendererHidden=renderer_hidden)
                            last_heartbeat=time.monotonic()
                            last_presentation=presentation
                        await asyncio.sleep(0.05)
                except BaseException:
                    stopping=True
                    raise

            monitor=asyncio.create_task(monitor_state())
            last_sequence=-1
            acknowledge_after=0
            frames_after_arrival=0
            was_idle=False
            next_frame=time.monotonic()
            pending=deque()
            stats_at=time.monotonic()
            stats_acks=acknowledged
            async def receive_refresh():
                nonlocal acknowledged,renderer_ready,frames_after_arrival,acknowledged_sequence
                async with asyncio.timeout(2):
                    while True:
                        name,args=await audit._event_queue.get()
                        if name!='hostInspectorCurrentElementChanged:':
                            continue
                        value=deserialize_object(audit._extract_event_payload(args))
                        identifiers=[getattr(getattr(item,'element',None),'identifier',None)
                                     for item in (value if isinstance(value,list) else [value])]
                        if pending and pending[0][0] in identifiers:
                            _,requested_at,requested_sequence=pending.popleft()
                            break
                acknowledged+=1
                renderer_ready=True
                if requested_sequence==last_sequence and requested_at>=acknowledge_after:
                    frames_after_arrival+=1
                if frames_after_arrival>=2 and acknowledged_sequence!=last_sequence:
                    acknowledged_sequence=last_sequence
                    log('tapp-motion-ack',sequence=last_sequence,sent=sent,acknowledged=acknowledged,
                        inFlight=len(pending),refreshMS=(time.monotonic()-requested_at)*1000)

            while not stopping:
                while pending and not audit._event_queue.empty():
                    await receive_refresh()
                suppress=bool(state.get('captureSuppressed'))
                if suppress != renderer_hidden:
                    while pending:
                        await receive_refresh()
                    # The inspector's hide flags leave its cached outline in
                    # captures. The app publishes an off-screen path instead.
                    # Fetch both identities and wait for fresh focus replies.
                    while not audit._event_queue.empty():
                        audit._event_queue.get_nowait()
                    refreshed=set()
                    for element in elements+elements[:1]:
                        await invoke(audit,'deviceInspectorFocusOnElement:',element)
                        await asyncio.sleep(1/REFRESH_HZ)
                    async with asyncio.timeout(3):
                        while len(refreshed)<len(elements):
                            name,args=await audit._event_queue.get()
                            if name!='hostInspectorCurrentElementChanged:':
                                continue
                            value=deserialize_object(audit._extract_event_payload(args))
                            for item in value if isinstance(value,list) else [value]:
                                caption=getattr(item,'caption','')
                                if caption and caption.startswith('Tapp cursor '):
                                    refreshed.add(caption)
                    renderer_hidden=suppress
                    renderer_ready=not suppress
                    was_idle=False
                    log('tapp-capture-visibility',hidden=suppress)
                if suppress:
                    await asyncio.sleep(0.02)
                    continue
                sequence=int(state.get('sequence',0))
                if sequence!=last_sequence:
                    last_sequence=sequence
                    log('tapp-motion',sequence=sequence,x=state.get('x'),y=state.get('y'),
                        duration=state.get('duration'),assistiveTouchRunning=state.get('assistiveTouchRunning'))
                    acknowledge_after=time.monotonic()+min(1,max(0,float(state.get('duration',0.25))))+0.05
                    frames_after_arrival=0
                idle=bool(state.get('idle'))
                if idle and acknowledged_sequence>=sequence:
                    while pending:
                        await receive_refresh()
                    renderer_ready=False
                    if not was_idle:
                        await invoke(audit,'deviceInspectorPreviewOnElement:',elements[sent%len(elements)])
                        log('tapp-idle',sequence=sequence,opacityChangeVerified=False)
                    was_idle=True
                    await asyncio.sleep(0.1)
                    continue
                if was_idle:
                    stats_at=time.monotonic(); stats_acks=acknowledged
                    log('tapp-awake',sequence=sequence)
                was_idle=False
                # One outstanding request per unique identity overlaps latency.
                # Each request fetches the app's current path, not old positions.
                if len(pending)>=len(elements):
                    await receive_refresh()
                element=elements[sent%len(elements)]
                expected=element['Value']['Value']['PlatformElementValue_v1']['Value']
                requested_at=time.monotonic()
                pending.append((expected,requested_at,sequence))
                await invoke(audit,'deviceInspectorFocusOnElement:',element)
                sent+=1
                if time.monotonic()-stats_at>=2:
                    elapsed=time.monotonic()-stats_at
                    log('tapp-render-timing',acknowledgementsPerSecond=(acknowledged-stats_acks)/elapsed,
                        inFlight=len(pending))
                    stats_at=time.monotonic(); stats_acks=acknowledged
                next_frame=max(next_frame+1/REFRESH_HZ,time.monotonic())
                await asyncio.sleep(max(0,next_frame-time.monotonic()))
            if monitor.done():
                await monitor
        finally:
            if monitor:
                monitor.cancel()
                with contextlib.suppress(Exception,asyncio.CancelledError):
                    await monitor
            # A dead peer must not add five separate five-second cleanup waits.
            with contextlib.suppress(Exception):
                async with asyncio.timeout(CLOSE_TIMEOUT):
                    for name,args in [('deviceInspectorShowVisuals:',(0,)),('deviceEnableHighlight:',(False,)),
                                      ('deviceSetAppMonitoringEnabled:',(False,)),('deviceInspectorEnable:',(False,)),
                                      ('devicePerformFinalCleanup',())]:
                        with contextlib.suppress(Exception):
                            await invoke(audit,name,*args)
            with contextlib.suppress(Exception):
                async with asyncio.timeout(CLOSE_TIMEOUT):
                    await write_heartbeat(files,session,False,acknowledged_sequence)
            log('tapp-session-ended',session=session,sent=sent,acknowledged=acknowledged)

def state_not_created(error):
    return any(part in str(error) for part in [
        'No such file', 'doesn’t exist',
        'Failed to open file at path: Documents/tapp-session.json'])

async def serve_connection(rsd):
    while True:
        # Resolve the container again after a session ends or an install.
        async with connected_resource(FileServiceService(rsd,Domain.APP_DATA_CONTAINER,BUNDLE)) as files:
            try:
                state=await read_state(files)
            except Exception as error:
                if not state_not_created(error):
                    raise
            else:
                if state.get('enabled'):
                    # A failed session can recover with exactly the same UUID.
                    # This only restores rendering; input is never replayed.
                    await render_session(rsd,files,state)
        await asyncio.sleep(0.75)

async def main():
    retry=1
    generation=0
    while True:
        began=time.monotonic()
        try:
            # Re-discover the address and ports instead of reusing stale RSD.
            async with connected_resource(NativeRemotedTunnel(serial='00008150-000A20360212401C')) as rsd:
                generation+=1
                log('companion-ready',generation=generation,instruction='Enable Tapp in hitapp Screen Control')
                await serve_connection(rsd)
        except Exception as error:
            if time.monotonic()-began>=20:
                retry=1
            log('companion-reconnecting',error=type(error).__name__+': '+str(error),retrySeconds=retry)
            await asyncio.sleep(retry)
            retry=min(RETRY_MAX,retry*2)

if __name__=='__main__':
    with (ROOT/'Evidence/.audit-probe.lock').open('w') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            asyncio.run(main())
        except KeyboardInterrupt:
            pass
