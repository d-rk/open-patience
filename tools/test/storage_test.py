#!/usr/bin/env python3
"""Unit tests for tools/video/storage.py — run:
python3 tools/test/storage_test.py"""

import json
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, os.pardir, "video"))

import storage  # noqa: E402

FIXTURE = {
    "save:klondike-draw1": {"variant": "klondike-draw1", "seed": 42,
                            "state": {"moveCount": 3}},
    "stats:klondike-draw1": {"totalWins": 7, "bestWins": []},
}


class EntriesTest(unittest.TestCase):
    def test_every_fixture_key_is_prefixed(self):
        entries = storage.local_storage_entries(FIXTURE)
        self.assertEqual(
            sorted(entries),
            sorted(storage.PREFIX + k for k in FIXTURE),
        )

    def test_values_are_double_json_encoded_strings(self):
        # Observed via probe_storage.py: shared_preferences_web JSON-encodes
        # every preference value -- including Strings -- so it can recover
        # types on read. The app writes a String (jsonEncode(blob)), so the
        # on-disk localStorage value is that JSON text encoded a SECOND time
        # as a JSON string literal. One json.loads() peels off the plugin's
        # layer and yields a string; a second peels off the app's own layer
        # and yields the original object.
        entries = storage.local_storage_entries(FIXTURE)
        raw = entries[storage.PREFIX + "save:klondike-draw1"]
        self.assertIsInstance(raw, str)
        inner = json.loads(raw)
        self.assertIsInstance(inner, str)
        self.assertEqual(json.loads(inner), FIXTURE["save:klondike-draw1"])

    def test_real_fixture_maps_without_error(self):
        path = os.path.join(HERE, os.pardir, "video", "demo_save.json")
        entries = storage.local_storage_entries(storage.load_fixture(path))
        self.assertEqual(len(entries), 2)

    def test_encode_matches_the_observed_wire_format(self):
        # Anchored to the byte-for-byte shape probe_storage.py observed
        # (see storage.py's module docstring), NOT to
        # _encode's own output undone by json.loads: shared_preferences_web
        # stores the app's already-jsonEncode'd String, JSON-encoded a
        # second time, so the wire value is the inner JSON text wrapped in
        # one more layer of JSON-string quoting/escaping.
        #
        # Case 1 exercises the nested-quote escaping that every entry hits
        # (every inner JSON object starts with `{"`, which the outer layer
        # must escape to `{\"`):
        #   inner = {"a":1}
        #   outer = "{\"a\":1}"   <- a literal quote, then {, then a
        #                            backslash-escaped quote, then a\":1},
        #                            then a closing quote.
        self.assertEqual(storage._encode({'a': 1}), '"{\\"a\\":1}"')
        # Case 2 exercises a literal backslash inside a value (e.g. a
        # Windows-style path or escaped character some save data could
        # contain). The value's own backslash must survive the first
        # json.dumps as `\\`, then each of those two backslash characters
        # is itself escaped again by the second json.dumps, doubling to
        # `\\\\`, alongside the same nested-quote escaping as case 1:
        #   value = {"p": 'a\b'}       (a, backslash, b)
        #   inner = {"p":"a\\b"}       (JSON text: a, \\, b between quotes)
        #   outer = "{\"p\":\"a\\\\b\"}"
        self.assertEqual(
            storage._encode({'p': 'a\\b'}),
            '"{\\"p\\":\\"a\\\\\\\\b\\"}"',
        )

    def test_real_fixture_value_has_the_double_wrap_signature(self):
        # The property that breaks if shared_preferences_web ever stops
        # double-encoding: every entry's wire value starts with a literal
        # quote immediately followed by an escaped-quote brace, `"{\"` —
        # the signature recorded in storage.py's module docstring and in
        # probe_storage.py's real captured output (`'"{\\"variant\\":...`).
        # A single-encoded value would instead start with a bare `{`.
        path = os.path.join(HERE, os.pardir, "video", "demo_save.json")
        entries = storage.local_storage_entries(storage.load_fixture(path))
        for key, raw in entries.items():
            self.assertTrue(
                raw.startswith('"{\\"'),
                f"{key!r} value {raw[:20]!r}... is missing the "
                "double-wrap signature",
            )


class InjectionScriptTest(unittest.TestCase):
    def test_script_clears_then_writes_every_entry(self):
        js = storage.injection_script(FIXTURE)
        self.assertIn("localStorage.clear()", js)
        for key in FIXTURE:
            self.assertIn(storage.PREFIX + key, js)

    def test_script_escapes_values_safely(self):
        # A value containing quotes and backslashes must not break out of the
        # generated JS string literal.
        js = storage.injection_script({"k": {"s": 'a"b\\c</script>'}})
        self.assertNotIn('"a"b', js)


if __name__ == "__main__":
    unittest.main()
