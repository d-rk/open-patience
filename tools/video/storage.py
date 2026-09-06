"""Mapping between the committed demo fixture and the web build's
localStorage.

The prefix and value encoding below were not guessed: they are what
tools/video/probe_storage.py observed the real shared_preferences web
implementation writing after a genuine draw move in a running app. Re-run
that probe after any shared_preferences upgrade -- if it changes, the video
capture silently boots to an empty menu instead of a resumable game.

What was observed (shared_preferences ^2.5.3, web/CanvasKit build):

  KEY   'flutter.save:klondike-draw1'
  VALUE '"{\\"variant\\":\\"klondike-draw1\\",\\"seed\\":...}"'

Two things follow from that:

* The key prefix is the plain literal ``flutter.`` -- no surprises there.
* The value is JSON-encoded TWICE, not once. shared_preferences_web encodes
  every preference value with jsonEncode (even Strings), so it can recover
  the original type on read (a bool round-trips as the JSON literal
  true/false, a String round-trips as a JSON string). This app's
  SharedPrefsRecordsRepository already calls jsonEncode(blob) itself before
  handing the plugin a String -- so what lands in localStorage is the JSON
  text of the fixture object, itself encoded again as a JSON string literal.
  Recovering the original therefore takes two json.loads() calls, not one.
"""

import json

# Observed via tools/video/probe_storage.py against shared_preferences ^2.5.3.
PREFIX = "flutter."


def load_fixture(path):
    """The committed demo fixture, keyed by unprefixed preference key."""
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def _encode(value):
    """A preference value as the web implementation stores it.

    The app's own persistence layer JSON-encodes the fixture object into a
    Dart String (mirroring SharedPrefsRecordsRepository.saveGame/recordWin);
    shared_preferences_web then JSON-encodes that String again before it
    reaches localStorage. Both layers go through json.dumps, so the result
    is safe to embed as a JS string literal without further escaping.
    """
    inner = json.dumps(value, separators=(",", ":"))
    return json.dumps(inner, separators=(",", ":"))


def local_storage_entries(fixture):
    """{localStorage key: localStorage value} for every fixture entry."""
    return {PREFIX + key: _encode(value) for key, value in fixture.items()}


def injection_script(fixture):
    """JavaScript that resets storage and writes the fixture.

    Every key and value goes through json.dumps, so quotes, backslashes and
    </script> sequences inside the blob cannot break the literal.
    """
    lines = ["localStorage.clear();"]
    for key, value in local_storage_entries(fixture).items():
        lines.append(
            f"localStorage.setItem({json.dumps(key)}, {json.dumps(value)});"
        )
    lines.append("true;")
    return "\n".join(lines)
