import asyncio
import sys
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import run_tapp_app_companion as companion


class Resource:
    def __init__(self, enter=None, exit=None):
        self.enter = enter or AsyncMock(return_value=self)
        self.exit = exit or AsyncMock()

    async def __aenter__(self):
        return await self.enter()

    async def __aexit__(self, *args):
        await self.exit(*args)


class ReconnectionTests(unittest.IsolatedAsyncioTestCase):
    async def test_recreates_discovery_and_caps_retry_delay(self):
        resources = []
        def factory(**kwargs):
            resource = Resource()
            resources.append(resource)
            return resource
        serve = AsyncMock(side_effect=[ConnectionResetError()] * 5 + [asyncio.CancelledError()])
        sleep = AsyncMock()
        with patch.object(companion, 'NativeRemotedTunnel', factory), patch.object(companion, 'serve_connection', serve), patch.object(companion.asyncio, 'sleep', sleep), patch.object(companion, 'log'):
            with self.assertRaises(asyncio.CancelledError):
                await companion.main()
        self.assertEqual(len(resources), 6)
        self.assertEqual([c.args[0] for c in sleep.call_args_list], [1, 2, 4, 8, 8])
        for resource in resources:
            resource.exit.assert_awaited_once()

    async def test_same_session_is_retried_after_failure(self):
        state = {'enabled': True, 'session': 'unchanged-session'}
        renderer = AsyncMock(side_effect=[ConnectionResetError(), asyncio.CancelledError()])
        with patch.object(companion, 'FileServiceService', side_effect=lambda *a: Resource()), patch.object(companion, 'read_state', AsyncMock(return_value=state)), patch.object(companion, 'render_session', renderer):
            with self.assertRaises(ConnectionResetError):
                await companion.serve_connection(object())
            with self.assertRaises(asyncio.CancelledError):
                await companion.serve_connection(object())
        self.assertEqual([c.args[2]['session'] for c in renderer.call_args_list], ['unchanged-session'] * 2)

    async def test_partial_connection_is_closed_on_timeout(self):
        resource = Resource(enter=AsyncMock(side_effect=lambda: None))
        async def hang():
            await asyncio.Event().wait()
        resource.enter = AsyncMock(side_effect=hang)
        with patch.object(companion, 'CONNECT_TIMEOUT', 0.01):
            with self.assertRaises(TimeoutError):
                async with companion.connected_resource(resource):
                    self.fail('Timed out connection must not be used')
        resource.exit.assert_awaited_once()

    async def test_dead_peer_cleanup_is_bounded(self):
        async def hang(*args):
            await asyncio.Event().wait()
        resource = Resource(exit=AsyncMock(side_effect=hang))
        with patch.object(companion, 'CLOSE_TIMEOUT', 0.01), patch.object(companion, 'log'):
            async with asyncio.timeout(0.2):
                async with companion.connected_resource(resource):
                    pass

    async def test_missing_state_waits_without_rendering(self):
        renderer = AsyncMock()
        with patch.object(companion, 'FileServiceService', return_value=Resource()), patch.object(companion, 'read_state', AsyncMock(side_effect=RuntimeError('Failed to open file at path: Documents/tapp-session.json'))), patch.object(companion, 'render_session', renderer), patch.object(companion.asyncio, 'sleep', AsyncMock(side_effect=asyncio.CancelledError())):
            with self.assertRaises(asyncio.CancelledError):
                await companion.serve_connection(object())
        renderer.assert_not_awaited()

    async def test_disabled_state_does_not_restart_renderer(self):
        renderer = AsyncMock()
        with patch.object(companion, 'FileServiceService', return_value=Resource()), patch.object(companion, 'read_state', AsyncMock(return_value={'enabled': False, 'session': 'off'})), patch.object(companion, 'render_session', renderer), patch.object(companion.asyncio, 'sleep', AsyncMock(side_effect=asyncio.CancelledError())):
            with self.assertRaises(asyncio.CancelledError):
                await companion.serve_connection(object())
        renderer.assert_not_awaited()


if __name__ == '__main__':
    unittest.main()
