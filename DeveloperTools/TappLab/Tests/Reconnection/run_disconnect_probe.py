"""Explicit live diagnostic: close only our file connection three times.

No phone inputs, setting changes, process restarts or action replay. After the
three drops this remains the normal companion, allowing a chat acceptance test.
"""
import asyncio
import fcntl
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import run_tapp_app_companion as companion

original_read = companion.read_state
drops = 0
next_drop = time.monotonic() + 12


async def read_with_drop(files):
    global drops, next_drop
    if drops < 3 and time.monotonic() >= next_drop:
        drops += 1
        next_drop = time.monotonic() + 12
        companion.log('diagnostic-connection-drop', number=drops)
        await files.close()
        raise ConnectionResetError('Diagnostic closed only the companion file transport')
    return await original_read(files)


companion.read_state = read_with_drop
with (companion.ROOT / 'Evidence/.audit-probe.lock').open('w') as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    try:
        asyncio.run(companion.main())
    except KeyboardInterrupt:
        pass
