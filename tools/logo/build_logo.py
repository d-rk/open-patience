#!/usr/bin/env python3
"""Generate the app-logo SVG and rasterise it into the launcher-icon PNGs.

The logo is three overlapping playing cards -- Q of clubs and K of hearts
fanned behind a hero Ace of spades -- in the game's "Emerald Felt" palette
(cream cards, gold edges, dark-green felt). It shares the menu-banner card
look: a big centre suit pip plus corner rank+suit indices, with the fully
visible Ace also carrying the mirrored bottom-right index of a real card.

This script is the single source of truth for the icon: edit the palette or
the ``CARDS`` layout below, then re-run it. It writes two inspectable SVGs
next to itself and rasterises them (via Inkscape) into the PNGs the icon
tooling consumes:

  * assets/icon/icon.png            -- opaque full-bleed felt tile (1024px),
                                       the legacy / iOS launcher icon and the
                                       source for flutter_launcher_icons.
  * assets/icon/icon_foreground.png -- cards only on transparency (1024px),
                                       padded into the Android adaptive-icon
                                       safe zone.
  * metadata/en-US/images/icon.png -- 512px opaque tile for the F-Droid
                                        listing (same art).
  * web/icons/Icon-192.png          -- 192px opaque tile for the PWA
  * web/icons/Icon-512.png          -- 512px opaque tile for the PWA
  * web/icons/Icon-maskable-192.png -- 192px maskable PWA icon (cards
                                        scaled to 80 % safe zone on felt).
  * web/icons/Icon-maskable-512.png -- 512px maskable PWA icon (same).

Run it (no Blender needed anymore -- pure SVG)::

    python3 tools/logo/build_logo.py

Then rebuild the platform launcher icons::

    dart run flutter_launcher_icons

Rasterising needs a serif font (Liberation Serif) and a suit-glyph font
(Noto Sans Symbols / Symbols 2) installed for the rank letters and pips.
"""

import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
ICON_DIR = os.path.join(REPO, "assets", "icon")
FDROID_ICON = os.path.join(
    REPO, "metadata", "en-US", "images", "icon.png")
WEB_ICON_DIR = os.path.join(REPO, "web", "icons")

# --- Emerald Felt palette (mirrors lib/ui/theme/game_palette.dart) ---
CREAM = "#FFF8EC"
GOLD = "#F6C65B"
RED = "#C0392B"
INK = "#1C2833"
FELT_L = "#2E8B57"
FELT_D = "#14532D"

SUITS = {"S": ("♠", INK), "H": ("♥", RED),
         "C": ("♣", INK), "D": ("♦", RED)}

CW, CH, CR = 84, 118, 11  # card width, height, corner radius (in a 240 canvas)

# Card layout: (centre-x, centre-y, rotation-deg, rank, suit[, br]).
# br=True adds the mirrored bottom-right index (only the hero Ace has it).
CARDS = [
    (96, 120, -13, "Q", "C"),
    (126, 114, 3, "K", "H"),
    (150, 132, 19, "A", "S", True),
]


def _index(ix, iy, rank, glyph, color, flip=False):
    rot = " rotate(180)" if flip else ""
    return f'''<g transform="translate({ix},{iy}){rot}">
      <text x="0" y="0" text-anchor="middle" font-family="Georgia, serif"
            font-size="19" font-weight="700" fill="{color}">{rank}</text>
      <text x="0" y="17" text-anchor="middle" font-family="Georgia, serif"
            font-size="16" fill="{color}">{glyph}</text>
    </g>'''


def _card(cx, cy, rot, rank, suit, br=False, big=54):
    glyph, color = SUITS[suit]
    x, y = -CW / 2, -CH / 2
    ix, iy = x + 13, y + 22
    tl = _index(ix, iy, rank, glyph, color)
    brc = _index(-ix, -iy, rank, glyph, color, flip=True) if br else ""
    return f'''
    <g transform="translate({cx},{cy}) rotate({rot})" filter="url(#sh)">
      <rect x="{x}" y="{y}" width="{CW}" height="{CH}" rx="{CR}"
            fill="{CREAM}" stroke="{GOLD}" stroke-width="3"/>
      <text x="0" y="0" dy="0.35em" text-anchor="middle" font-family="Georgia, serif"
            font-size="{big}" font-weight="700" fill="{color}">{glyph}</text>
      {tl}{brc}
    </g>'''


def build_svg(felt, scale=1.0):
    """felt=True -> opaque full-bleed tile; felt=False + scale<1 -> padded
    transparent adaptive foreground."""
    bg = (f'<rect x="0" y="0" width="240" height="240" fill="url(#felt)"/>'
          if felt else '')
    body = "".join(_card(*c) for c in CARDS)
    if scale != 1.0:
        body = (f'<g transform="translate(120,120) scale({scale}) '
                f'translate(-120,-120)">{body}</g>')
    return f'''<svg viewBox="0 0 240 240" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <radialGradient id="felt" cx="50%" cy="42%" r="72%">
      <stop offset="0%" stop-color="{FELT_L}"/>
      <stop offset="100%" stop-color="{FELT_D}"/>
    </radialGradient>
    <filter id="sh" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="5"/>
      <feOffset dx="0" dy="5" result="off"/>
      <feFlood flood-color="#0a2a18" flood-opacity="0.45"/>
      <feComposite in2="off" operator="in"/>
      <feMerge>
        <feMergeNode/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>
  {bg}
  {body}
</svg>'''


def _rasterizer():
    exe = shutil.which("inkscape")
    if not exe:
        sys.exit("error: Inkscape not found; install it to rasterise the logo.")
    return exe


def render_png(svg_text, out_path, size):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as tmp:
        tmp.write(svg_text)
        svg_path = tmp.name
    try:
        subprocess.run(
            [_rasterizer(), svg_path, "--export-type=png",
             f"--export-filename={out_path}", "-w", str(size), "-h", str(size)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    finally:
        os.unlink(svg_path)
    print("wrote", out_path)


def main():
    icon_svg = build_svg(felt=True)
    fg_svg = build_svg(felt=False, scale=0.95)
    maskable_svg = build_svg(felt=True, scale=0.8)

    # Inspectable SVG sources next to this script.
    with open(os.path.join(HERE, "logo.svg"), "w") as f:
        f.write(icon_svg)
    with open(os.path.join(HERE, "logo_foreground.svg"), "w") as f:
        f.write(fg_svg)
    with open(os.path.join(HERE, "logo_maskable.svg"), "w") as f:
        f.write(maskable_svg)

    render_png(icon_svg, os.path.join(ICON_DIR, "icon.png"), 1024)
    render_png(fg_svg, os.path.join(ICON_DIR, "icon_foreground.png"), 1024)
    render_png(icon_svg, FDROID_ICON, 512)

    render_png(icon_svg, os.path.join(WEB_ICON_DIR, "Icon-192.png"), 192)
    render_png(icon_svg, os.path.join(WEB_ICON_DIR, "Icon-512.png"), 512)
    render_png(maskable_svg, os.path.join(WEB_ICON_DIR, "Icon-maskable-192.png"), 192)
    render_png(maskable_svg, os.path.join(WEB_ICON_DIR, "Icon-maskable-512.png"), 512)


if __name__ == "__main__":
    main()
