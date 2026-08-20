#!/usr/bin/env python3
"""Render the solitaire app-logo from the editable Blender scene.

The artwork lives in ``tools/logo/solitaire_logo.blend`` -- open that file in
Blender to tweak the cards, suit emblems, camera, lighting or the felt
background by hand. This script just loads that .blend and renders it into the
two PNGs the launcher-icon tooling consumes:

  * assets/icon/icon.png            -- opaque app-icon tile (felt backdrop +
                                       drop shadow), used for the legacy icon.
  * assets/icon/icon_foreground.png -- cards + emblems only on transparency
                                       (backdrop hidden), the Android adaptive
                                       foreground layer.

Run it headless (Blender is installed as a Flatpak here)::

    flatpak run org.blender.Blender --background \
        --python tools/logo/build_logo.py

Or, from a normal Blender install::

    blender --background --python tools/logo/build_logo.py

Then rebuild the platform launcher icons::

    dart run flutter_launcher_icons

The .blend is the single source of truth: edit it, re-run this script, then
regenerate the launcher icons.
"""

import os

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
BLEND = os.path.join(HERE, "solitaire_logo.blend")
OUT_DIR = os.path.join(REPO_ROOT, "assets", "icon")

# Name of the felt background object in the .blend (hidden for the foreground).
BACKDROP = "Backdrop"


def render_to(scene, path, transparent):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.film_transparent = transparent
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("wrote", path)


def main():
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    scene = bpy.context.scene

    backdrop = bpy.data.objects.get(BACKDROP)

    # Opaque app-icon tile (with felt backdrop + drop shadow).
    if backdrop:
        backdrop.hide_render = False
    render_to(scene, os.path.join(OUT_DIR, "icon.png"), transparent=False)

    # Android adaptive foreground: cards + emblems only, transparent.
    if backdrop:
        backdrop.hide_render = True
    render_to(scene, os.path.join(OUT_DIR, "icon_foreground.png"), transparent=True)


if __name__ == "__main__":
    main()
