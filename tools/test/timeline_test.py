#!/usr/bin/env python3
"""Unit tests for the concat-timeline builder in
tools/video/capture_gameplay.py — run: python3 tools/test/timeline_test.py"""

import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, os.pardir, "video"))

import capture_gameplay as cg  # noqa: E402


def durations(text):
    return [float(m) for m in re.findall(r"^duration (.+)$", text,
                                         re.MULTILINE)]


class BuildConcatTest(unittest.TestCase):
    def test_duration_is_the_gap_to_the_next_frame(self):
        text = cg.build_concat(
            [("a.jpg", 0.0), ("b.jpg", 0.5), ("c.jpg", 0.7)],
            tail_seconds=1.0,
        )
        self.assertEqual(durations(text)[:2], [0.5, 0.2])

    def test_last_frame_uses_the_tail_duration(self):
        text = cg.build_concat([("a.jpg", 0.0), ("b.jpg", 0.5)],
                               tail_seconds=1.25)
        self.assertEqual(durations(text)[-1], 1.25)

    def test_final_file_is_repeated_for_the_concat_demuxer(self):
        # ffmpeg's concat demuxer drops the last entry's duration unless the
        # file is listed once more after it.
        text = cg.build_concat([("a.jpg", 0.0), ("b.jpg", 0.5)],
                               tail_seconds=1.0)
        self.assertEqual(text.strip().splitlines()[-1], "file 'b.jpg'")

    def test_out_of_order_timestamps_never_yield_a_negative_duration(self):
        text = cg.build_concat([("a.jpg", 1.0), ("b.jpg", 0.4), ("c.jpg", 2.0)],
                               tail_seconds=1.0)
        self.assertTrue(all(d > 0 for d in durations(text)))

    def test_single_frame_still_produces_a_valid_list(self):
        text = cg.build_concat([("a.jpg", 0.0)], tail_seconds=2.0)
        self.assertEqual(durations(text), [2.0])
        self.assertEqual(text.count("file 'a.jpg'"), 2)

    def test_empty_input_raises(self):
        with self.assertRaises(ValueError):
            cg.build_concat([], tail_seconds=1.0)


if __name__ == "__main__":
    unittest.main()
