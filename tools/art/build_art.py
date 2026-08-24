#!/usr/bin/env python3
"""Render the splash + menu-banner art from the editable Blender scenes.

The artwork lives in ``tools/art/splash_scene.blend`` and
``tools/art/banner_scene.blend`` -- open those in Blender to tweak the cards,
camera, lighting or materials by hand. Both scenes share the same fanned-hand
composition (cream cards with gold edges, rank + suit corner indices and a soft
drop shadow), framed square for the splash and 2:1 for the banner. The suit
glyph font (Noto Sans Symbols2) and rank font (Fredoka) are *packed into* each
.blend, so rendering needs no external font files.

This script loads each .blend and renders it into the transparent PNGs the
app bundles:

  * assets/images/splash.png          -- centered splash art (transparent).
  * assets/images/splash_android12.png -- same scene, camera pulled back so
                                          the card fan clears the circular
                                          safe zone the Android 12+
                                          SplashScreen API clips its icon to
                                          (768px-diameter circle on the
                                          1152px canvas -- see the
                                          flutter_native_splash README).
  * assets/images/menu_banner.png     -- wide menu banner (transparent).

Each scene already stores its own render engine (Cycles), resolution and
transparent-film setting, so this script just opens and renders it.

Run it headless (Blender is installed as a Flatpak here)::

    flatpak run org.blender.Blender --background \\
        --python tools/art/build_art.py

Or from a normal Blender install::

    blender --background --python tools/art/build_art.py

The .blend files are the single source of truth: edit them, then re-run this
script to regenerate the PNGs.
"""

import os

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))
OUT_DIR = os.path.join(REPO_ROOT, "assets", "images")

SCENES = (
    ("splash_scene.blend", "splash.png"),
    ("banner_scene.blend", "menu_banner.png"),
)

# Camera pull-back factor for the Android 12+ splash render: scales the
# camera's position away from the origin (rotation unchanged) so the fanned
# cards fit inside the 768px-diameter safe circle Android clips its
# SplashScreen icon to, on the same 1152px canvas. Picked empirically by
# rendering prototypes to build/art/ and checking the alpha bounding box
# against the safe-circle radius.
ANDROID12_CAMERA_PULLBACK = 1.7
ANDROID12_SCENE = "splash_scene.blend"
ANDROID12_OUT = "splash_android12.png"


def render_to(scene, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("wrote", path)


def render_android12_variant():
    bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, ANDROID12_SCENE))
    scene = bpy.context.scene
    scene.camera.location = scene.camera.location * ANDROID12_CAMERA_PULLBACK
    render_to(scene, os.path.join(OUT_DIR, ANDROID12_OUT))


def main():
    for blend, out in SCENES:
        bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, blend))
        render_to(bpy.context.scene, os.path.join(OUT_DIR, out))
    render_android12_variant()


if __name__ == "__main__":
    main()
