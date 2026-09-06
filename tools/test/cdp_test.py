#!/usr/bin/env python3
"""Unit tests for tools/cdp.py — run: python3 tools/test/cdp_test.py"""

import json
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                os.pardir))

import cdp  # noqa: E402


class FakeWebSocket:
    """A scripted websocket: every send() pops the next canned reply batch."""

    def __init__(self, batches):
        # batches: list of lists of dicts, one list per expected send().
        self._batches = list(batches)
        self._pending = []
        self.sent = []
        self.timeouts = []
        self._timeout = None

    def send(self, text):
        self.sent.append(json.loads(text))
        self._pending.extend(self._batches.pop(0) if self._batches else [])

    def recv(self):
        if self._timeout is not None:
            # Model the worst case behind the pump()-leaves-socket-timed-out
            # bug: while a non-None timeout is armed, treat every read as
            # arriving too slowly and time out -- even if a message is
            # already queued. This is what lets a test prove a later call()
            # only works again once settimeout(None) has restored blocking
            # mode.
            raise TimeoutError("timed out")
        if not self._pending:
            raise ConnectionError("no more scripted messages")
        return json.dumps(self._pending.pop(0))

    def settimeout(self, seconds):
        self.timeouts.append(seconds)
        self._timeout = seconds

    def close(self):
        pass


class CallTest(unittest.TestCase):
    def test_call_returns_matching_result(self):
        ws = FakeWebSocket([[{"id": 1, "result": {"ok": True}}]])
        client = cdp.CDP(ws)
        self.assertEqual(client.call("Page.enable"), {"ok": True})
        self.assertEqual(ws.sent[0]["method"], "Page.enable")

    def test_call_raises_on_protocol_error(self):
        ws = FakeWebSocket([[{"id": 1, "error": {"message": "boom"}}]])
        client = cdp.CDP(ws)
        with self.assertRaises(RuntimeError):
            client.call("Page.bad")


class EventTest(unittest.TestCase):
    def test_events_arriving_before_a_response_are_buffered_not_dropped(self):
        # This is the regression the old _CDP.call had: it discarded every
        # message that was not its own response id.
        ws = FakeWebSocket([[
            {"method": "Page.screencastFrame", "params": {"sessionId": 1}},
            {"method": "Page.screencastFrame", "params": {"sessionId": 2}},
            {"id": 1, "result": {}},
        ]])
        client = cdp.CDP(ws)
        client.call("Page.startScreencast")
        frames = list(client.events("Page.screencastFrame"))
        self.assertEqual([f["sessionId"] for f in frames], [1, 2])

    def test_events_drains_the_buffer(self):
        ws = FakeWebSocket([[
            {"method": "Page.screencastFrame", "params": {"sessionId": 1}},
            {"id": 1, "result": {}},
        ]])
        client = cdp.CDP(ws)
        client.call("Page.startScreencast")
        self.assertEqual(len(list(client.events("Page.screencastFrame"))), 1)
        self.assertEqual(list(client.events("Page.screencastFrame")), [])

    def test_events_ignores_other_event_methods(self):
        ws = FakeWebSocket([[
            {"method": "Page.loadEventFired", "params": {}},
            {"method": "Page.screencastFrame", "params": {"sessionId": 7}},
            {"id": 1, "result": {}},
        ]])
        client = cdp.CDP(ws)
        client.call("Page.startScreencast")
        frames = list(client.events("Page.screencastFrame"))
        self.assertEqual([f["sessionId"] for f in frames], [7])


class PumpTest(unittest.TestCase):
    def test_pump_restores_blocking_mode_when_done(self):
        # A later call() must not inherit the pump's short read timeout.
        ws = FakeWebSocket([])
        client = cdp.CDP(ws)
        client.pump(0.01)
        self.assertIsNone(ws.timeouts[-1])

    def test_call_after_pump_still_returns_result(self):
        # Regression test: pump() used to leave the socket pinned to its
        # 0.2s timeout, so a call() issued afterwards could see a spurious
        # socket.timeout mid-read instead of its real response.
        ws = FakeWebSocket([[{"id": 1, "result": {"ok": True}}]])
        client = cdp.CDP(ws)
        client.pump(0.01)
        self.assertEqual(client.call("Page.enable"), {"ok": True})


class NotifyTest(unittest.TestCase):
    def test_notify_sends_expected_payload(self):
        ws = FakeWebSocket([[]])
        client = cdp.CDP(ws)
        client.notify("Page.screencastFrameAck", sessionId="abc")
        self.assertEqual(ws.sent[0]["method"], "Page.screencastFrameAck")
        self.assertEqual(ws.sent[0]["params"], {"sessionId": "abc"})
        self.assertIn("id", ws.sent[0])

    def test_notify_does_not_read_a_response(self):
        # No messages queued for recv() -- if notify() tried to read one, the
        # fake would raise ConnectionError. A fire-and-forget send must not
        # block waiting for an ack it doesn't need.
        ws = FakeWebSocket([[]])
        client = cdp.CDP(ws)
        client.notify("Page.screencastFrameAck", sessionId="abc")  # no raise

    def test_notify_increments_the_id_counter(self):
        # The safety invariant the whole fire-and-forget approach rests on:
        # ids must stay strictly monotonic and never be reused, or a stale
        # response could be mistaken for a later call()'s response.
        ws = FakeWebSocket([[], []])
        client = cdp.CDP(ws)
        client.notify("Page.screencastFrameAck", sessionId="x")
        self.assertEqual(ws.sent[0]["id"], 1)
        client.notify("Page.screencastFrameAck", sessionId="y")
        self.assertEqual(ws.sent[1]["id"], 2)

    def test_call_after_unread_notify_still_returns_its_own_result(self):
        # The notify's own ack response arrives later, unread, and sits in
        # front of the subsequent call()'s real response. call()'s existing
        # wait loop must discard it silently (it carries an id but no
        # method) and keep waiting for the id it actually sent.
        ws = FakeWebSocket([
            [{"id": 1, "result": {}}],  # stale ack, never read by notify()
            [{"id": 2, "result": {"ok": True}}],
        ])
        client = cdp.CDP(ws)
        client.notify("Page.screencastFrameAck", sessionId="abc")
        self.assertEqual(client.call("Page.enable"), {"ok": True})


if __name__ == "__main__":
    unittest.main()
