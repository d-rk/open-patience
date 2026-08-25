#!/usr/bin/env python3
"""Generate the F-Droid listing **feature graphic** (1024x500) as SVG and
rasterise it into a PNG.

Layout mirrors the top of the app's main menu -- the fanned hero banner across
the top, the two-tone ``OPEN PATIENCE`` wordmark beneath it, and a gold rule +
suit-pip flourish (spade / heart / diamond / club) below that -- all on the
Emerald Felt gradient. Like ``build_logo.py`` this script is the single source
of truth for the asset: edit the palette / layout below, re-run, commit the
regenerated PNG. Never hand-edit the output.

It composes from two shared inputs so the graphic can never drift from the app:

  * ``assets/images/menu_banner.png`` -- the same Blender-rendered banner art
    the menu bundles (owned by ``tools/art/build_art.py``), embedded as a
    base64 data URI so the SVG is self-contained.
  * ``assets/fonts/LilitaOne-Regular.ttf`` -- the real display font. It is not
    a system font, so it is exposed to Inkscape via a throwaway fontconfig
    file (see ``_fontconfig``); the user's font setup is left untouched.

Output:
  * metadata/en-US/images/featureGraphic.png -- 1024x500, the F-Droid listing
    banner (fastlane ``featureGraphic`` name).

It also writes an inspectable ``feature_graphic.svg`` next to this script.

Run it::

    python3 tools/fdroid/build_feature_graphic.py

Needs Inkscape on PATH, plus Noto Sans Symbols installed for the suit glyphs
(same prerequisite as build_logo.py).
"""

import base64
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
BANNER = os.path.join(REPO, "assets", "images", "menu_banner.png")
FONT_DIR = os.path.join(REPO, "assets", "fonts")
OUT_PNG = os.path.join(
    REPO, "metadata", "en-US", "images", "featureGraphic.png")

# Canvas -- F-Droid's fixed feature-graphic size.
W, H = 1024, 500

# --- Emerald Felt palette (mirrors lib/ui/theme/game_palette.dart) ---
CREAM = "#FFF8EC"
GOLD = "#F6C65B"
FELT_L = "#2E8B57"
FELT_M = "#1C6B3C"
FELT_D = "#14532D"

# Fonts (mirrors lib/ui/theme/game_fonts.dart -- the real name-table family
# name, "Lilita One", not the Flutter family alias "LilitaOne").
DISPLAY_FONT = "Lilita One"
SUIT_FONT = "Noto Sans Symbols"

# Wordmark geometry (in canvas units). The main menu uses fontSize 42 at phone
# scale; the feature graphic is a larger canvas, so the lockup is scaled up.
WORDMARK_SIZE = 66
WORDMARK_TRACKING = 5   # letter-spacing, matches GameWordmark's letterSpacing.
WORD_GAP = 26           # extra space between OPEN and PATIENCE.
SUITS = "♠♥♦♣"  # spade heart diamond club, in menu order.


def _banner_href(embed):
    """The banner reference for the SVG. ``embed=True`` inlines it as a base64
    data URI (self-contained, used for rasterising regardless of CWD);
    ``embed=False`` uses a repo-relative path (kept small + diffable for the
    inspectable SVG committed next to this script)."""
    if not embed:
        return os.path.relpath(BANNER, HERE)
    with open(BANNER, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    return f"data:image/png;base64,{b64}"


def build_svg(embed_banner=True):
    """Compose the 1024x500 feature graphic as an SVG string. The banner is
    inlined when ``embed_banner`` (see ``_banner_href``)."""
    # Banner: preserve the art's 2:1 aspect, sized by height and centred near
    # the top so the wordmark + pips sit beneath it (layout "A", stacked).
    banner_h = 268
    banner_w = banner_h * 2
    banner_x = (W - banner_w) / 2
    banner_y = 48

    # Wordmark, centred under the banner.
    words_y = banner_y + banner_h + 76
    # Pip rule row, beneath the wordmark.
    pips_y = words_y + 52
    rule_gap = 96                     # half-gap from centre to each rule end.
    rule_len = 168
    cx = W / 2

    return f'''<svg viewBox="0 0 {W} {H}" width="{W}" height="{H}"
     xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <defs>
    <radialGradient id="felt" cx="50%" cy="8%" r="110%">
      <stop offset="0%" stop-color="{FELT_L}"/>
      <stop offset="55%" stop-color="{FELT_M}"/>
      <stop offset="100%" stop-color="{FELT_D}"/>
    </radialGradient>
    <filter id="soft" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="4"/>
      <feOffset dx="0" dy="4" result="off"/>
      <feFlood flood-color="#000000" flood-opacity="0.45"/>
      <feComposite in2="off" operator="in"/>
      <feMerge>
        <feMergeNode/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>

  <rect x="0" y="0" width="{W}" height="{H}" fill="url(#felt)"/>

  <image x="{banner_x}" y="{banner_y}" width="{banner_w}" height="{banner_h}"
         filter="url(#soft)" preserveAspectRatio="xMidYMid meet"
         xlink:href="{_banner_href(embed_banner)}"/>

  <text x="{cx}" y="{words_y}" text-anchor="middle" filter="url(#soft)"
        font-family="{DISPLAY_FONT}" font-size="{WORDMARK_SIZE}"
        letter-spacing="{WORDMARK_TRACKING}">
    <tspan fill="{CREAM}">OPEN</tspan><tspan fill="{GOLD}" dx="{WORD_GAP}">PATIENCE</tspan>
  </text>

  <g>
    <rect x="{cx - rule_gap - rule_len}" y="{pips_y - 2}" width="{rule_len}"
          height="3" rx="1.5" fill="{GOLD}" fill-opacity="0.7"/>
    <rect x="{cx + rule_gap}" y="{pips_y - 2}" width="{rule_len}"
          height="3" rx="1.5" fill="{GOLD}" fill-opacity="0.7"/>
    <text x="{cx}" y="{pips_y}" text-anchor="middle" dominant-baseline="middle"
          font-family="{SUIT_FONT}" font-size="30" letter-spacing="10"
          fill="{GOLD}">{SUITS}</text>
  </g>
</svg>'''


def _rasterizer():
    exe = shutil.which("inkscape")
    if not exe:
        sys.exit("error: Inkscape not found; install it to rasterise the graphic.")
    return exe


def _fontconfig(tmpdir):
    """Write a throwaway fontconfig file that adds the repo's bundled fonts
    (so "Lilita One" resolves) on top of the system config, and return a
    process env pointing Inkscape at it. Leaves the user's fonts untouched."""
    conf = os.path.join(tmpdir, "fonts.conf")
    cache = os.path.join(tmpdir, "cache")
    os.makedirs(cache, exist_ok=True)
    with open(conf, "w") as f:
        f.write(
            '<?xml version="1.0"?>\n'
            '<!DOCTYPE fontconfig SYSTEM "fonts.dtd">\n'
            "<fontconfig>\n"
            f"  <dir>{FONT_DIR}</dir>\n"
            '  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>\n'
            f"  <cachedir>{cache}</cachedir>\n"
            "</fontconfig>\n")
    env = dict(os.environ)
    env["FONTCONFIG_FILE"] = conf
    return env


def render_png(svg_text, out_path):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmpdir:
        svg_path = os.path.join(tmpdir, "graphic.svg")
        with open(svg_path, "w") as f:
            f.write(svg_text)
        subprocess.run(
            [_rasterizer(), svg_path, "--export-type=png",
             f"--export-filename={out_path}", "-w", str(W), "-h", str(H)],
            check=True, env=_fontconfig(tmpdir),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("wrote", out_path)


def main():
    with open(os.path.join(HERE, "feature_graphic.svg"), "w") as f:
        f.write(build_svg(embed_banner=False))
    render_png(build_svg(embed_banner=True), OUT_PNG)


if __name__ == "__main__":
    main()
