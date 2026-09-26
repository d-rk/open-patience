#!/usr/bin/env python3
"""Unit tests for the pure parts of tools/sfx/build_sfx.py (no ffmpeg, no
network) — run: python3 tools/test/sfx_test.py"""

import os
import re
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, os.pardir, "sfx"))

import build_sfx as sfx  # noqa: E402


def recipe(name):
    return next(r for r in sfx.RECIPES if r.output == name)


class RecipeTableTest(unittest.TestCase):
    def test_outputs_are_unique(self):
        names = [r.output for r in sfx.RECIPES]
        self.assertEqual(len(names), len(set(names)))

    def test_output_names_follow_the_board_convention(self):
        for r in sfx.RECIPES:
            self.assertRegex(r.output, r"^[a-z]+(_\d+)?$")

    def test_expected_outputs_exist(self):
        names = {r.output for r in sfx.RECIPES}
        expected = {"place_1", "place_2", "place_3", "place_4",
                    "foundation_1", "foundation_2",
                    "draw_1", "draw_2", "draw_3", "flip", "illegal",
                    "undo_1", "undo_2", "deal", "win"}
        self.assertEqual(names, expected)


class ChecksumTest(unittest.TestCase):
    def write(self, data):
        f = tempfile.NamedTemporaryFile(delete=False)
        f.write(data)
        f.close()
        self.addCleanup(os.unlink, f.name)
        return f.name

    def test_matching_checksum_passes(self):
        path = self.write(b"abc")
        sfx.verify_checksum(
            path,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

    def test_mismatch_raises(self):
        path = self.write(b"abc")
        with self.assertRaises(sfx.ChecksumError):
            sfx.verify_checksum(path, "0" * 64)


class FfmpegArgsTest(unittest.TestCase):
    def test_measure_pass_runs_volumedetect_and_writes_nothing(self):
        args = sfx.ffmpeg_args(recipe("place_1"), "/src", None)
        self.assertIn("volumedetect", sfx.filter_graph(recipe("place_1")))
        self.assertEqual(args[-3:], ["-f", "null", "-"])

    def test_encode_pass_is_bitexact_vorbis(self):
        args = sfx.ffmpeg_args(recipe("place_1"), "/src", "/out/p.ogg", 3.5)
        self.assertEqual(args[-1], "/out/p.ogg")
        self.assertIn("+bitexact", args)
        self.assertEqual(args[args.index("-fflags") + 1], "+bitexact")
        self.assertEqual(args[args.index("-flags:a") + 1], "+bitexact")
        self.assertEqual(args[args.index("-c:a") + 1], "libvorbis")
        self.assertEqual(args[args.index("-map_metadata") + 1], "-1")

    def test_gain_is_applied_last(self):
        graph = sfx.filter_graph(recipe("place_1"), 3.5)
        self.assertTrue(graph.endswith("volume=3.50dB:precision=fixed[out]"))
        self.assertLess(graph.index("afade"), graph.index("volume=3.50dB"))

    def test_layer_recipe_mixes_a_second_input(self):
        args = sfx.ffmpeg_args(recipe("foundation_1"), "/src", None)
        self.assertEqual(args.count("-i"), 2)
        self.assertIn("/src/chip-lay-1.ogg", args)
        graph = sfx.filter_graph(recipe("foundation_1"))
        self.assertIn("volume=-10.0dB", graph)
        self.assertIn("amix=inputs=2", graph)

    def test_trim_only_when_requested(self):
        self.assertIn("atrim=end=1.2", sfx.filter_graph(recipe("deal")))
        self.assertNotIn("atrim", sfx.filter_graph(recipe("place_1")))

    def test_fade_length_comes_from_the_recipe(self):
        self.assertIn("afade=t=in:d=0.15", sfx.filter_graph(recipe("win")))


class LoudnessTest(unittest.TestCase):
    def test_parses_max_volume(self):
        err = "[Parsed_volumedetect_0 @ 0x1] max_volume: -7.5 dB\n"
        self.assertEqual(sfx.parse_max_volume(err), -7.5)

    def test_missing_max_volume_raises(self):
        with self.assertRaises(ValueError):
            sfx.parse_max_volume("nothing here")

    def test_gain_lifts_peak_to_minus_one(self):
        self.assertAlmostEqual(sfx.normalising_gain(-7.5), 6.5)


if __name__ == "__main__":
    unittest.main()
