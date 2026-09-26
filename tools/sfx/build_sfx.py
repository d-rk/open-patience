#!/usr/bin/env python3
"""Build the game's sound effects — run: python3 tools/sfx/build_sfx.py

The single source of truth for everything in assets/sounds/. Downloads
Kenney's CC0 "Casino Audio" pack (pinned URL + SHA-256, cached in
tools/sfx/.cache/), then renders each RECIPES entry with ffmpeg: strip
leading silence, optionally trim, optionally mix in a quiet second layer,
fade out, downmix to mono 44.1 kHz, peak-normalise to -1 dBFS and encode
Vorbis. Encoding is bit-exact, so re-running on the same inputs rewrites
byte-identical files. Everything is rendered into a staging directory first
and swapped into place with a rename (see swap_into_place); on any failure
assets/sounds/ is left untouched.

Needs ffmpeg (with libvorbis) on PATH.
"""

import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile
from dataclasses import dataclass
from typing import Optional

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, os.pardir, os.pardir))
OUT_DIR = os.path.join(ROOT, "assets", "sounds")
CACHE_DIR = os.path.join(HERE, ".cache")

PACK_URL = ("https://kenney.nl/media/pages/assets/casino-audio/"
            "2472606a04-1721639069/kenney_casino-audio.zip")
PACK_SHA256 = ("f36250766ac5bc378c13708ddf12a23a8e54a3251f8d482c7536e51b5"
               "dbafa18")
LICENSE_OUT = "LICENSE-kenney-casino-audio.txt"

PEAK_TARGET_DB = -1.0
SILENCE_THRESHOLD_DB = -50


class ChecksumError(Exception):
    pass


@dataclass(frozen=True)
class Recipe:
    output: str                      # file stem in assets/sounds/
    source: str                      # file stem in the pack's Audio/
    layer: Optional[str] = None      # optional second source mixed in
    layer_gain_db: float = -10.0
    layer_delay_ms: int = 30
    trim_s: Optional[float] = None
    fade_ms: int = 40


RECIPES = (
    *(Recipe(f"place_{i}", f"card-place-{i}") for i in range(1, 5)),
    Recipe("foundation_1", "card-place-1", layer="chip-lay-1"),
    Recipe("foundation_2", "card-place-3", layer="chip-lay-2"),
    *(Recipe(f"draw_{i}", f"card-slide-{i}") for i in range(1, 4)),
    Recipe("flip", "card-slide-4", trim_s=0.25, fade_ms=60),
    Recipe("illegal", "card-shove-1", fade_ms=60),
    Recipe("undo_1", "card-slide-5"),
    Recipe("undo_2", "card-slide-6"),
    Recipe("deal", "card-shuffle", trim_s=1.2, fade_ms=150),
    Recipe("win", "card-fan-2", fade_ms=150),
)


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def verify_checksum(path, expected):
    actual = sha256_of(path)
    if actual != expected:
        raise ChecksumError(
            f"{path}: sha256 {actual}, expected {expected} "
            "(delete the cached file to re-download)")


def filter_graph(recipe, gain_db=None):
    """The -filter_complex graph for [recipe], ending in [out]. Without
    [gain_db] it ends in volumedetect (the measuring pass); with it, in the
    normalising volume filter."""
    strip = ("silenceremove=start_periods=1:"
             f"start_threshold={SILENCE_THRESHOLD_DB}dB")
    parts = [f"[0:a]{strip}[main]"]
    mixed = "[main]"
    if recipe.layer:
        parts.append(
            f"[1:a]{strip},volume={recipe.layer_gain_db}dB,"
            f"adelay=delays={recipe.layer_delay_ms}:all=1[layer]")
        parts.append(
            "[main][layer]amix=inputs=2:duration=first:normalize=0[mixed]")
        mixed = "[mixed]"
    chain = []
    if recipe.trim_s is not None:
        chain.append(f"atrim=end={recipe.trim_s}")
    fade_s = recipe.fade_ms / 1000
    chain += [
        "aformat=sample_rates=44100:channel_layouts=mono",
        # Fade-out without knowing the duration: fade in the reversed clip.
        f"areverse,afade=t=in:d={fade_s},areverse",
        # volumedetect measures in its own (effectively 16-bit) domain, which
        # reads several dB quieter than the true float-sample peak this
        # graph can otherwise produce (from the mono downmix and the
        # reversed-afade trick). volume's default float precision would
        # apply the gain in that louder domain and overshoot the target, so
        # pin it to the same fixed precision volumedetect measured in.
        "volumedetect" if gain_db is None
        else f"volume={gain_db:.2f}dB:precision=fixed",
    ]
    parts.append(f"{mixed}{','.join(chain)}[out]")
    return ";".join(parts)


def ffmpeg_args(recipe, src_dir, out_path, gain_db=None):
    args = ["ffmpeg", "-hide_banner", "-nostdin", "-y",
            "-i", os.path.join(src_dir, recipe.source + ".ogg")]
    if recipe.layer:
        args += ["-i", os.path.join(src_dir, recipe.layer + ".ogg")]
    args += ["-filter_complex", filter_graph(recipe, gain_db),
             "-map", "[out]"]
    if gain_db is None:
        return args + ["-f", "null", "-"]
    return args + ["-map_metadata", "-1",
                   "-fflags", "+bitexact", "-flags:a", "+bitexact",
                   "-c:a", "libvorbis", "-q:a", "4", out_path]


def parse_max_volume(stderr):
    m = re.search(r"max_volume:\s*(-?[\d.]+) dB", stderr)
    if not m:
        raise ValueError("volumedetect printed no max_volume")
    return float(m.group(1))


def normalising_gain(max_volume_db):
    return PEAK_TARGET_DB - max_volume_db


def fetch_pack():
    os.makedirs(CACHE_DIR, exist_ok=True)
    path = os.path.join(CACHE_DIR, "kenney_casino-audio.zip")
    if not os.path.exists(path):
        print(f"downloading {PACK_URL}")
        urllib.request.urlretrieve(PACK_URL, path)
    verify_checksum(path, PACK_SHA256)
    return path


def extract(zip_path, dest):
    needed = ({r.source for r in RECIPES}
              | {r.layer for r in RECIPES if r.layer})
    with zipfile.ZipFile(zip_path) as z:
        names = set(z.namelist())
        for stem in sorted(needed):
            member = f"Audio/{stem}.ogg"
            if member not in names:
                raise SystemExit(f"recipe source {member} is not in the pack")
            with z.open(member) as src, \
                    open(os.path.join(dest, stem + ".ogg"), "wb") as out:
                shutil.copyfileobj(src, out)
        with z.open("License.txt") as src, \
                open(os.path.join(dest, LICENSE_OUT), "wb") as out:
            shutil.copyfileobj(src, out)


def render(recipe, src_dir, out_dir):
    probe = subprocess.run(ffmpeg_args(recipe, src_dir, None),
                           capture_output=True, text=True, check=True)
    gain = normalising_gain(parse_max_volume(probe.stderr))
    out_path = os.path.join(out_dir, recipe.output + ".ogg")
    subprocess.run(ffmpeg_args(recipe, src_dir, out_path, gain),
                   capture_output=True, check=True)


def swap_into_place(staged, target):
    """Replace the [target] directory with [staged] (must be on the same
    filesystem, so the swap is a rename, not a copy). On success [staged] no
    longer exists and [target] holds its former contents. On any failure
    [target] is left exactly as it was and nothing is left behind under its
    name — not even a half-renamed backup."""
    if not os.path.isdir(staged):
        raise FileNotFoundError(f"staged directory not found: {staged}")
    backup = target + ".bak"
    if os.path.exists(backup):
        shutil.rmtree(backup)
    had_target = os.path.exists(target)
    if had_target:
        os.rename(target, backup)
    try:
        os.replace(staged, target)
    except OSError:
        if had_target:
            if os.path.exists(target):
                shutil.rmtree(target)
            os.rename(backup, target)
        raise
    else:
        if had_target and os.path.exists(backup):
            shutil.rmtree(backup)


def main():
    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg not found on PATH")
    zip_path = fetch_pack()
    with tempfile.TemporaryDirectory() as tmp:
        src_dir = os.path.join(tmp, "src")
        os.makedirs(src_dir)
        extract(zip_path, src_dir)

        # Staged on the same filesystem as OUT_DIR (not the /tmp above,
        # which may be a different filesystem) so the final swap is a rename,
        # never a partial copy.
        staged = tempfile.mkdtemp(prefix="sounds-", dir=os.path.dirname(OUT_DIR))
        try:
            for r in RECIPES:
                render(r, src_dir, staged)
                print(f"  {r.output}.ogg")
            shutil.copy(os.path.join(src_dir, LICENSE_OUT), staged)
            swap_into_place(staged, OUT_DIR)
        finally:
            if os.path.isdir(staged):
                shutil.rmtree(staged)
    print(f"wrote {len(RECIPES)} sounds to {os.path.relpath(OUT_DIR, ROOT)}")


if __name__ == "__main__":
    main()
