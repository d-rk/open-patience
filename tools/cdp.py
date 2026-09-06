"""Shared stdlib Chrome DevTools Protocol client.

Pure stdlib (a tiny bundled WebSocket + CDP client -- like ``build_logo.py``
shelling out to Inkscape, this needs only the ``google-chrome`` binary), so
both ``fdroid/capture_screenshots.py`` and the video capture scripts can drive
headless Chrome without a third-party dependency.
"""

import base64
import contextlib
import functools
import http.server
import json
import os
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request


# --------------------------------------------------------------------------
# Minimal WebSocket client (RFC 6455, text frames, client-masked) -- just
# enough to speak the Chrome DevTools Protocol. Avoids a websocket-client dep.
# --------------------------------------------------------------------------
class WebSocket:
    def __init__(self, url):
        # url like ws://host:port/devtools/page/<id>
        assert url.startswith("ws://")
        hostport, _, path = url[len("ws://"):].partition("/")
        host, _, port = hostport.partition(":")
        self._sock = socket.create_connection((host, int(port or 80)))
        key = base64.b64encode(os.urandom(16)).decode()
        req = (
            f"GET /{path} HTTP/1.1\r\n"
            f"Host: {hostport}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        self._sock.sendall(req.encode())
        self._buf = b""
        # Read past the handshake response headers.
        while b"\r\n\r\n" not in self._buf:
            self._buf += self._sock.recv(4096)
        _, _, self._buf = self._buf.partition(b"\r\n\r\n")

    def _recv_exact(self, n):
        while len(self._buf) < n:
            chunk = self._sock.recv(65536)
            if not chunk:
                raise ConnectionError("websocket closed")
            self._buf += chunk
        out, self._buf = self._buf[:n], self._buf[n:]
        return out

    def send(self, text):
        payload = text.encode()
        header = bytearray([0x81])  # FIN + text opcode
        n = len(payload)
        mask_bit = 0x80
        if n < 126:
            header.append(mask_bit | n)
        elif n < (1 << 16):
            header.append(mask_bit | 126)
            header += struct.pack(">H", n)
        else:
            header.append(mask_bit | 127)
            header += struct.pack(">Q", n)
        mask = os.urandom(4)
        header += mask
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self._sock.sendall(bytes(header) + masked)

    def recv(self):
        # Reassemble one message (handles fragmentation + 64-bit lengths).
        data = b""
        while True:
            b0, b1 = self._recv_exact(2)
            fin = b0 & 0x80
            length = b1 & 0x7F
            if length == 126:
                length = struct.unpack(">H", self._recv_exact(2))[0]
            elif length == 127:
                length = struct.unpack(">Q", self._recv_exact(8))[0]
            data += self._recv_exact(length)
            if fin:
                return data.decode()

    def settimeout(self, seconds):
        """Set the socket read timeout; `None` restores blocking mode."""
        self._sock.settimeout(seconds)

    def close(self):
        with contextlib.suppress(Exception):
            self._sock.close()


class CDP:
    """Thin request/response wrapper over a DevTools page WebSocket.

    Unlike a naive implementation, this one does not *discard* protocol
    events while waiting for a response id — screencast frames arrive as
    events, and dropping them is how a recorder silently produces an empty
    video. Anything that is not our response is buffered for events().
    """

    def __init__(self, ws):
        self._ws = ws
        self._id = 0
        self._events = []

    @classmethod
    def connect(cls, ws_url):
        return cls(WebSocket(ws_url))

    def call(self, method, **params):
        self._id += 1
        mid = self._id
        self._ws.send(json.dumps({"id": mid, "method": method,
                                  "params": params}))
        while True:
            msg = json.loads(self._ws.recv())
            if msg.get("id") == mid:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})
            if "method" in msg:
                self._events.append(msg)

    def notify(self, method, **params):
        """Send a command without waiting for its response.

        For fire-and-forget commands whose response is never needed --
        `Page.screencastFrameAck` is the motivating case: `call()` blocks
        until a matching response id arrives, and Chrome will not send the
        next screencast frame until the previous one is acked, so acking via
        `call()` adds a full round trip per frame.

        This is safe only because it still consumes a fresh id from the same
        monotonic `self._id` counter `call()` uses -- never skip that
        increment or reuse an id. An ack response carries `id`/`result` but
        never `method`, so `call()`'s wait loop (and `pump()`) silently
        discard it when it turns up unread ahead of a later response: they
        only buffer messages that have a `method` key, and only `call()`'s
        own matching id short-circuits the wait. Because ids are strictly
        monotonic and never reused, and the WebSocket delivers messages in
        order, a stale response to a `notify()` call can never be mistaken
        for the response to a later `call()`.
        """
        self._id += 1
        mid = self._id
        self._ws.send(json.dumps({"id": mid, "method": method,
                                  "params": params}))

    def events(self, method):
        """Yield the params of each buffered event named `method`, draining
        them. Events of other methods stay buffered."""
        keep = []
        for msg in self._events:
            if msg.get("method") == method:
                yield msg.get("params", {})
            else:
                keep.append(msg)
        self._events = keep

    def pump(self, seconds):
        """Read messages for `seconds`, buffering every event. Use while an
        animation plays and no call() is being made — without this, frames
        pile up unread in the socket buffer."""
        deadline = time.time() + seconds
        self._ws.settimeout(0.2)
        try:
            while time.time() < deadline:
                try:
                    msg = json.loads(self._ws.recv())
                except (socket.timeout, TimeoutError):
                    continue
                if "method" in msg:
                    self._events.append(msg)
        finally:
            # A later call() must not inherit the pump's short read timeout
            # — restore blocking mode, even on an early exit, so a slow
            # in-flight response doesn't surface as a spurious socket.timeout.
            self._ws.settimeout(None)

    def close(self):
        self._ws.close()


# --------------------------------------------------------------------------
# Local static server for build/web.
# --------------------------------------------------------------------------
@contextlib.contextmanager
def serve(directory):
    class _QuietHandler(http.server.SimpleHTTPRequestHandler):
        def log_message(self, *a, **k):  # silence per-request logging
            pass

    handler = functools.partial(_QuietHandler, directory=directory)
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    port = httpd.server_address[1]
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    try:
        yield port
    finally:
        httpd.shutdown()


# --------------------------------------------------------------------------
# Headless Chrome lifecycle.
# --------------------------------------------------------------------------
def chrome_exe():
    for name in ("google-chrome", "google-chrome-stable", "chromium",
                 "chromium-browser"):
        exe = shutil.which(name)
        if exe:
            return exe
    sys.exit("error: Chrome/Chromium not found on PATH.")


@contextlib.contextmanager
def chrome(width, height, device_scale_factor=1):
    """Launch headless Chrome at a `width`x`height` (physical pixel) window.

    `device_scale_factor` only needs to be passed by a caller that records a
    `Page.startScreencast`. `Page.captureScreenshot` honours a DPR set later
    via `Emulation.setDeviceMetricsOverride` on its own, but
    `Page.startScreencast` does not: verified empirically (see
    tools/video/capture_gameplay.py's history) that its frames come out at
    the CSS/logical size regardless of the emulated deviceScaleFactor, and
    regardless of `startScreencast`'s own maxWidth/maxHeight params, unless
    the scale factor is *also* forced at the browser-launch level via
    `--force-device-scale-factor`. Screenshot-only callers (e.g.
    fdroid/capture_screenshots.py) don't need this and can omit it.
    """
    profile = tempfile.mkdtemp(prefix="op-shots-")
    port = free_port()
    args = [chrome_exe(), "--headless=new", f"--remote-debugging-port={port}",
            f"--user-data-dir={profile}", "--no-first-run",
            "--no-default-browser-check", "--disable-gpu",
            "--hide-scrollbars", f"--window-size={width},{height}"]
    if device_scale_factor != 1:
        args.append(f"--force-device-scale-factor={device_scale_factor}")
    args.append("about:blank")
    proc = subprocess.Popen(
        args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        page_ws = _wait_for_page_ws(port)
        yield CDP.connect(page_ws)
    finally:
        proc.terminate()
        with contextlib.suppress(Exception):
            proc.wait(timeout=5)
        shutil.rmtree(profile, ignore_errors=True)


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _wait_for_page_ws(port, timeout=15):
    deadline = time.time() + timeout
    url = f"http://127.0.0.1:{port}/json"
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1) as resp:
                targets = json.loads(resp.read())
            for t in targets:
                if t.get("type") == "page" and t.get("webSocketDebuggerUrl"):
                    return t["webSocketDebuggerUrl"]
        except Exception:
            pass
        time.sleep(0.3)
    sys.exit("error: Chrome DevTools endpoint never came up.")


# --------------------------------------------------------------------------
# High-level capture actions.
# --------------------------------------------------------------------------
def tap(cdp, x, y):
    """A synthetic touch tap at CSS pixel (x, y) on the Flutter canvas.

    The viewport emulates a touch device (``mobile=True``), so Flutter web
    listens for pointer/touch events. We send a stable-id touchStart, hold
    briefly, then touchEnd -- a deliberate tap that Material buttons
    (FilledButton) register, where a too-quick tap was dropped.
    """
    point = {"x": x, "y": y, "id": 0}
    cdp.call("Input.dispatchTouchEvent", type="touchStart",
             touchPoints=[point])
    time.sleep(0.12)
    cdp.call("Input.dispatchTouchEvent", type="touchEnd", touchPoints=[])
    time.sleep(0.05)


def screenshot(cdp, out_path):
    result = cdp.call("Page.captureScreenshot", format="png",
                      captureBeyondViewport=False)
    with open(out_path, "wb") as f:
        f.write(base64.b64decode(result["data"]))
    print("wrote", out_path)
