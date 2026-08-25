#!/usr/bin/env python3
"""Capture F-Droid listing screenshots from the Flutter **web** build.

No emulator, no adb, no third-party Python packages: this drives a headless
Google Chrome over the DevTools Protocol (a tiny stdlib WebSocket client is
bundled below), the same way ``build_logo.py`` shells out to Inkscape. It:

  1. Serves ``build/web`` on a throwaway localhost port.
  2. Launches headless Chrome at a realistic device viewport (phone
     1080x1920, or tablet 1920x1200 with ``--tablet``).
  3. Walks a scripted SHOTS sequence -- navigate by tapping canvas
     coordinates, wait, capture -- writing each frame as a numbered PNG into
     ``metadata/en-US/images/{phoneScreenshots,tenInchScreenshots}/``.

Because Flutter renders to a single ``<canvas>`` there are no DOM handles to
click; navigation is therefore coordinate-based and tuned to the fixed
viewport. Edit the SHOTS table if the layout moves.

Prerequisites:
  * ``google-chrome`` on PATH.
  * A built web app: ``flutter build web --release`` (this script will build
    it for you if ``build/web`` is missing).

Run it::

    python3 tools/fdroid/capture_screenshots.py           # phone
    python3 tools/fdroid/capture_screenshots.py --tablet  # tablet
"""

import argparse
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

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
WEB_DIR = os.path.join(REPO, "build", "web")
# F-Droid store metadata lives at the repo root in the standard
# metadata/<locale>/ layout (scanned for the main F-Droid repo, and mapped into
# the self-hosted collection by the release workflow).
META = os.path.join(REPO, "metadata", "en-US", "images")


# --------------------------------------------------------------------------
# Minimal WebSocket client (RFC 6455, text frames, client-masked) -- just
# enough to speak the Chrome DevTools Protocol. Avoids a websocket-client dep.
# --------------------------------------------------------------------------
class _WebSocket:
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

    def close(self):
        with contextlib.suppress(Exception):
            self._sock.close()


class _CDP:
    """Thin request/response wrapper over a DevTools page WebSocket."""

    def __init__(self, ws_url):
        self._ws = _WebSocket(ws_url)
        self._id = 0

    def call(self, method, **params):
        self._id += 1
        mid = self._id
        self._ws.send(json.dumps({"id": mid, "method": method,
                                  "params": params}))
        # Skip protocol events until our matching id comes back.
        while True:
            msg = json.loads(self._ws.recv())
            if msg.get("id") == mid:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})

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
def _chrome_exe():
    for name in ("google-chrome", "google-chrome-stable", "chromium",
                 "chromium-browser"):
        exe = shutil.which(name)
        if exe:
            return exe
    sys.exit("error: Chrome/Chromium not found on PATH.")


@contextlib.contextmanager
def chrome(width, height):
    profile = tempfile.mkdtemp(prefix="op-shots-")
    port = _free_port()
    proc = subprocess.Popen(
        [_chrome_exe(), "--headless=new", f"--remote-debugging-port={port}",
         f"--user-data-dir={profile}", "--no-first-run",
         "--no-default-browser-check", "--disable-gpu",
         "--hide-scrollbars", f"--window-size={width},{height}", "about:blank"],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        page_ws = _wait_for_page_ws(port)
        yield _CDP(page_ws)
    finally:
        proc.terminate()
        with contextlib.suppress(Exception):
            proc.wait(timeout=5)
        shutil.rmtree(profile, ignore_errors=True)


def _free_port():
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


# --------------------------------------------------------------------------
# Scenario: three shots per form factor -- main menu, a just-started Klondike
# deal, a just-started FreeCell deal. Between games we reload the page (a clean
# reset to the menu) instead of tapping Back, which the pushed-route animation
# made unreliable. Each shot is a filename, a list of ("tap", x, y) /
# ("reload",) actions to run before capturing, and a note.
#
# Emulation uses a realistic *logical* viewport (device-independent pixels) at
# a phone/tablet devicePixelRatio, NOT a 1:1 giant canvas -- otherwise Flutter
# lays the UI out for a huge screen and the banner/cards look tiny. The PNG is
# rendered at logical size x dpr, giving the F-Droid target resolution while the
# layout matches a real device. Tap coordinates are therefore in LOGICAL pixels;
# retune the FORMATS coords below if the menus move.
# --------------------------------------------------------------------------
BOOT_SETTLE = 6.0    # Flutter first paint after a (re)load.
NAV_SETTLE = 1.5     # after a menu/options navigation tap.
DEAL_SETTLE = 3.0    # after Play, for the opening deal to settle.

# Per form factor: the emulated logical viewport, its devicePixelRatio (so the
# PNG lands on the F-Droid target size), the output subfolder, and the tap
# targets (in logical pixels) -- the two menu game tiles and the first variant's
# Play button on a game's options screen.
FORMATS = {
    "portrait": {  # 360x640 dp @3x -> 1080x1920 px (typical phone portrait)
        "logical": (360, 640),
        "dpr": 3,
        "sub": "phoneScreenshots",
        "coords": {
            "klondike": (180, 330),
            "freecell": (180, 383),
            "play": (83, 172),
        },
    },
    "landscape": {  # 960x600 dp @2x -> 1920x1200 px (typical tablet landscape)
        "logical": (960, 600),
        "dpr": 2,
        "sub": "tenInchScreenshots",
        "coords": {
            "klondike": (480, 213),
            "freecell": (480, 269),
            "play": (302, 172),
        },
    },
}


def scenario(coords):
    k, f, p = coords["klondike"], coords["freecell"], coords["play"]
    return [
        ("1.png", [], "Main menu"),
        ("2.png", [("tap", k), ("tap", p)], "Klondike — new deal"),
        ("3.png", [("reload",), ("tap", f), ("tap", p)], "FreeCell — new deal"),
    ]


def run_actions(cdp, url, actions):
    for action in actions:
        if action[0] == "reload":
            cdp.call("Page.navigate", url=url)
            time.sleep(BOOT_SETTLE)
        elif action[0] == "tap":
            x, y = action[1]
            tap(cdp, x, y)
            # A Play tap opens a deal (longer settle); a menu tap just pushes a
            # page. Heuristic: the Play target is the only one we follow with a
            # deal, so give every tap NAV_SETTLE and add the deal wait when the
            # next action is a capture.
            time.sleep(NAV_SETTLE)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tablet", action="store_true",
                        help="landscape 1920x1200 into tenInchScreenshots/")
    args = parser.parse_args()

    fmt = FORMATS["landscape" if args.tablet else "portrait"]
    log_w, log_h = fmt["logical"]
    dpr = fmt["dpr"]
    out_w, out_h = log_w * dpr, log_h * dpr
    out_dir = os.path.join(META, fmt["sub"])
    os.makedirs(out_dir, exist_ok=True)

    if not os.path.isfile(os.path.join(WEB_DIR, "index.html")):
        print("build/web not found — running flutter build web --release ...")
        subprocess.run(["flutter", "build", "web", "--release"],
                       cwd=REPO, check=True)

    with serve(WEB_DIR) as port, chrome(out_w, out_h) as cdp:
        url = f"http://127.0.0.1:{port}/"
        cdp.call("Page.enable")
        # Emulate a real device: logical viewport at a phone/tablet dpr, touch
        # input on. The screenshot is captured at logical x dpr = out_w x out_h.
        cdp.call("Emulation.setDeviceMetricsOverride", width=log_w,
                 height=log_h, deviceScaleFactor=dpr, mobile=True)
        cdp.call("Emulation.setTouchEmulationEnabled", enabled=True,
                 maxTouchPoints=1)
        cdp.call("Page.navigate", url=url)
        time.sleep(BOOT_SETTLE)

        for name, actions, note in scenario(fmt["coords"]):
            run_actions(cdp, url, actions)
            # If the last action started a deal, let it settle before capture.
            if actions and actions[-1][0] == "tap":
                time.sleep(DEAL_SETTLE)
            print(f"[{name}] {note}")
            screenshot(cdp, os.path.join(out_dir, name))

    print(f"\nDone. Screenshots in: {out_dir}")


if __name__ == "__main__":
    main()
