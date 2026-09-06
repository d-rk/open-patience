#!/usr/bin/env python3
"""Preload the demo save into the **Linux desktop** build's preferences.

The CDP screencast in ``capture_gameplay.py`` tops out around 10 fps because
Chrome gates each frame on an ack round trip, which reads as stutter. For a
high-quality recording, run the native Linux build and capture it with a real
screen recorder instead. This script puts the same near-finished Klondike deal
(``demo_save.json``) in front of that build, so "Resume" is waiting on the
main menu exactly as it is in the scripted video.

Encoding note -- this is *not* the same as the web path. ``shared_preferences``
on Linux stores each value as the app's own ``jsonEncode`` string, once. The
web implementation JSON-encodes that string a *second* time (see
``storage.py``). Using the web form here would leave the app unable to decode
the blob, and it would silently boot to an empty menu.

Run it with the app CLOSED (the running app rewrites this file on exit)::

    python3 tools/video/seed_linux_save.py
    flutter run -d linux --release

``--release`` matters: a debug run paints Flutter's DEBUG banner over the
corner of every frame you record.
"""

import argparse
import json
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import storage  # noqa: E402

FIXTURE = os.path.join(HERE, "demo_save.json")

# linux/CMakeLists.txt sets APPLICATION_ID; path_provider_linux derives the
# support directory from it, so these must stay in step.
APPLICATION_ID = "io.github.d_rk.openpatience"
PREFS = os.path.join(
    os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")),
    APPLICATION_ID,
    "shared_preferences.json",
)

# Same prefix the web build uses, and the same one already present in an
# existing Linux prefs file.
PREFIX = "flutter."


def linux_entries(fixture):
    """{prefs key: value} as the Linux implementation stores them.

    One level of JSON encoding, matching what the app itself wrote via
    ``jsonEncode`` -- deliberately not ``storage._encode``, which double-wraps
    for the web.
    """
    return {
        PREFIX + key: json.dumps(value, separators=(",", ":"))
        for key, value in fixture.items()
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--restore", action="store_true",
                        help="put the most recent backup back and exit")
    args = parser.parse_args()

    os.makedirs(os.path.dirname(PREFS), exist_ok=True)

    if args.restore:
        backups = sorted(
            f for f in os.listdir(os.path.dirname(PREFS))
            if f.startswith("shared_preferences.json.bak-")
        )
        if not backups:
            sys.exit(f"error: no backup found next to {PREFS}")
        newest = os.path.join(os.path.dirname(PREFS), backups[-1])
        shutil.copy2(newest, PREFS)
        print(f"restored {newest}\n      -> {PREFS}")
        return

    if os.path.exists(PREFS):
        backup = f"{PREFS}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
        shutil.copy2(PREFS, backup)
        print(f"backed up existing prefs -> {backup}")

    entries = linux_entries(storage.load_fixture(FIXTURE))
    with open(PREFS, "w", encoding="utf-8") as f:
        json.dump(entries, f, indent=2)

    print(f"wrote {len(entries)} keys -> {PREFS}")
    for key in sorted(entries):
        print(f"  {key}")
    print(
        "\nNow launch the desktop build (with the app not already running):\n"
        "  flutter run -d linux --release\n\n"
        "The main menu should show a 'Continue playing' row for Klondike\n"
        "(Draw 1) reading 03:34 / 111 moves. Tap Resume, then Solve.\n"
        "Undo the preload afterwards with --restore."
    )


if __name__ == "__main__":
    main()
