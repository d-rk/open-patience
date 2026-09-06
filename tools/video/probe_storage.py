#!/usr/bin/env python3
"""Dump what shared_preferences actually writes to localStorage on web.

The key prefix and value encoding are a plugin implementation detail, so the
video capture must not guess at them. This drives the real web build far
enough to create a save, then prints localStorage verbatim.

    flutter build web --release
    python3 tools/video/probe_storage.py

Dealing a fresh game is not enough to produce a save: GameBloc only calls
repository.saveGame() after an actual Move (draw/tap-move/undo/redo) or on
app pause/detach (see lib/presentation/bloc/game_bloc.dart), never merely on
deal. So after opening Klondike, this also taps the stock pile once to draw
a card -- a real Move -- which triggers the autosave.

Headless Chrome's synthetic touch dispatch is occasionally missed by
Flutter's gesture arena on the very first tap after a (re)load, independent
of coordinates -- a pre-existing quirk of tools/cdp.py's tap(), also visible
in tools/fdroid/capture_screenshots.py. This retries the whole capture in a
fresh browser a few times rather than trying to detect a bad tap mid-flow
(there is no DOM to inspect: the web build renders via CanvasKit).
"""

import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, os.pardir))
from cdp import chrome, screenshot, serve, tap  # noqa: E402
import storage  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
WEB_DIR = os.path.join(REPO, "build", "web")

# Logical-pixel tap targets, same convention and same values as the portrait
# format in tools/fdroid/capture_screenshots.py.
KLONDIKE = (180, 330)
PLAY = (83, 172)
STOCK = (30, 90)  # top-left stock pile once a Klondike game is dealt.

MAX_ATTEMPTS = 3


def _capture_once(cdp, port):
    cdp.call("Page.enable")
    cdp.call("Emulation.setDeviceMetricsOverride", width=360, height=640,
             deviceScaleFactor=2, mobile=True)
    cdp.call("Emulation.setTouchEmulationEnabled", enabled=True,
             maxTouchPoints=1)
    cdp.call("Page.navigate", url=f"http://127.0.0.1:{port}/")
    time.sleep(6.0)

    tap(cdp, *KLONDIKE)
    time.sleep(2.5)
    tap(cdp, *PLAY)
    time.sleep(4.0)
    # Draw a card: a real Move, so GameBloc._persist() actually writes.
    tap(cdp, *STOCK)
    time.sleep(1.5)

    result = cdp.call(
        "Runtime.evaluate",
        expression="JSON.stringify(Object.fromEntries("
                   "Object.entries(localStorage)))",
        returnByValue=True,
    )
    return json.loads(result["result"]["value"])


def main():
    if not os.path.isfile(os.path.join(WEB_DIR, "index.html")):
        sys.exit("error: build/web missing — run: flutter build web --release")

    if "--verify-injection" in sys.argv:
        verify_injection()
        return

    entries = {}
    for attempt in range(1, MAX_ATTEMPTS + 1):
        with serve(WEB_DIR) as port, chrome(720, 1280) as cdp:
            entries = _capture_once(cdp, port)
        if entries:
            break
        print(f"attempt {attempt}/{MAX_ATTEMPTS}: localStorage empty, "
              "retrying in a fresh browser...", file=sys.stderr)

    if not entries:
        sys.exit("error: localStorage empty after retries — the tap coords "
                 "may be stale; compare them with capture_screenshots.py "
                 "FORMATS.")

    for key, value in sorted(entries.items()):
        print(f"KEY   {key!r}")
        print(f"VALUE {value[:200]!r}{'...' if len(value) > 200 else ''}")
        print()


def verify_injection():
    fixture_path = os.path.join(HERE, "demo_save.json")
    fixture = storage.load_fixture(fixture_path)
    out = os.path.join(REPO, "build", "inject_check.png")
    with serve(WEB_DIR) as port, chrome(720, 1280) as cdp:
        url = f"http://127.0.0.1:{port}/"
        cdp.call("Page.enable")
        cdp.call("Emulation.setDeviceMetricsOverride", width=360, height=640,
                 deviceScaleFactor=2, mobile=True)
        cdp.call("Emulation.setTouchEmulationEnabled", enabled=True,
                 maxTouchPoints=1)
        cdp.call("Page.navigate", url=url)
        time.sleep(6.0)
        cdp.call("Runtime.evaluate",
                 expression=storage.injection_script(fixture))
        cdp.call("Page.navigate", url=url)
        time.sleep(6.0)
        screenshot(cdp, out)
    print("wrote", out, "— it MUST show a 'Continue playing' Klondike row.")


if __name__ == "__main__":
    main()
