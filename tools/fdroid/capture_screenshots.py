#!/usr/bin/env python3
"""Capture F-Droid listing screenshots from the Flutter **web** build.

No emulator, no adb, no third-party Python packages: this drives a headless
Google Chrome over the DevTools Protocol (the stdlib client lives in
``tools/cdp.py``), the same way ``build_logo.py`` shells out to Inkscape. It:

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
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                os.pardir))
from cdp import chrome, screenshot, serve, tap  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
WEB_DIR = os.path.join(REPO, "build", "web")
# F-Droid store metadata lives at the repo root in the standard
# metadata/<locale>/ layout (scanned for the main F-Droid repo, and mapped into
# the self-hosted collection by the release workflow).
META = os.path.join(REPO, "metadata", "en-US", "images")


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
