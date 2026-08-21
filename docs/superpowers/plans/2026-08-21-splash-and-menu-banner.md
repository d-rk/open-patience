# Splash Image & Animated Menu Banner — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Blender-rendered startup splash and an animated main-menu banner to Open Patience, both fully new imagery-only artwork bundled as offline assets.

**Architecture:** Blender scenes (built via the Blender MCP bridge, saved as `.blend` source-of-truth files under `tools/art/`) render transparent PNGs into `assets/images/`. The splash is delivered by `flutter_native_splash` (native, offline). The menu banner is a static PNG animated in Flutter with a subtle looping float, disabled under reduced-motion. Title text stays Flutter-drawn (Lilita One).

**Tech Stack:** Blender 4.x (Flatpak `org.blender.Blender`) via MCP, Flutter/Dart, `flutter_native_splash`, `flutter_bloc` (existing), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-21-splash-and-menu-banner-design.md`

---

## Constraints (read first)

- **Blender is a Flatpak** — sandboxed filesystem. All render outputs and
  `.blend` saves must use **absolute project paths** it can access.
- **Temporary prototype renders → `/home/dirk/projects/open-patience/build/art/`**
  (already covered by the existing `build/` entry in `.gitignore`). Never `/tmp`.
- **Palette** (Emerald Felt): felt `#1C6B3C`, felt-dark `#14532D`, gold
  `#F6C65B`, cream `#FFF8EC`, red `#C0392B`, ink `#1C2833`.
- Final renders are **transparent** (`film_transparent = True`).
- `lib/core` and `lib/persistence` are untouched (no Flutter-boundary impact).

Repo root is `/home/dirk/projects/open-patience` throughout — abbreviated
`<ROOT>` in prose, written out in full inside every code block.

---

## File Structure

- `tools/art/build_art.py` — render script (mirrors `tools/logo/build_logo.py`).
- `tools/art/splash_scene.blend` — source of truth for the splash art.
- `tools/art/banner_scene.blend` — source of truth for the banner art.
- `build/art/*.png` — temp prototype renders (gitignored).
- `assets/images/splash.png`, `assets/images/menu_banner.png` — final assets.
- `lib/ui/widgets/menu_banner.dart` — animated banner widget.
- `lib/ui/main_menu_screen.dart` — wires the banner in.
- `test/widget/menu_banner_test.dart` — banner tests.
- `test/widget/main_menu_test.dart` — updated to disable animations.
- `pubspec.yaml` — `flutter_native_splash` dev dep + config + `assets/images/`.

---

## Phase 0 — Feasibility

### Task 1: Confirm the Flatpak sandbox can write `build/art/` and read fonts

**Files:** none (MCP probe only).

- [ ] **Step 1: Run the probe via Blender MCP**

Use `blender-mcp_execute_blender_code` with:

```python
import os
base = "/home/dirk/projects/open-patience"
art = os.path.join(base, "build", "art")
os.makedirs(art, exist_ok=True)
probe = os.path.join(art, "_probe.txt")
with open(probe, "w") as fh:
    fh.write("ok")
print("write_ok:", os.path.exists(probe))
print("font_read:",
      os.path.exists(os.path.join(base, "assets/fonts/LilitaOne-Regular.ttf")))
print("tools_art_ok:", os.path.isdir(os.path.join(base, "tools")))
```

Expected output: `write_ok: True`, `font_read: True`, `tools_art_ok: True`.

- [ ] **Step 2: If `write_ok` is False**, stop and grant the Flatpak filesystem
  access to the project dir (e.g. `flatpak override --user
  --filesystem=/home/dirk/projects/open-patience org.blender.Blender`), then
  re-run Step 1 until it prints `write_ok: True`.

- [ ] **Step 3: Create the `tools/art/` directory**

Run: `mkdir -p /home/dirk/projects/open-patience/tools/art`

---

## Phase 1 — Prototype the three subjects

All three subjects share one setup helper. Each is built via
`blender-mcp_execute_blender_code`, rendered to `build/art/`, then reviewed by
reading the PNG back before deciding.

### Task 2: Shared scene-setup helper (render fanned card spread)

**Files:** none (MCP; produces `build/art/fanned.png`).

- [ ] **Step 1: Build the fanned-spread scene**

Run via `blender-mcp_execute_blender_code`:

```python
import bpy, math

ROOT = "/home/dirk/projects/open-patience"

# --- wipe scene + orphan data ---
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for coll in (bpy.data.meshes, bpy.data.materials,
             bpy.data.lights, bpy.data.cameras):
    for block in list(coll):
        coll.remove(block)

# --- palette (sRGB hex -> linear RGBA) ---
def rgba(hex6):
    def lin(c):
        c /= 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (lin(int(hex6[0:2], 16)), lin(int(hex6[2:4], 16)),
            lin(int(hex6[4:6], 16)), 1.0)

FELT = rgba("1C6B3C"); CREAM = rgba("FFF8EC")
GOLD = rgba("F6C65B"); RED = rgba("C0392B")

def make_mat(name, color, rough=0.5):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = color
    b.inputs["Roughness"].default_value = rough
    return m

def add_card(x, y, rot_deg, color, name):
    bpy.ops.mesh.primitive_cube_add(size=1, location=(x, y, 0.05))
    c = bpy.context.object; c.name = name
    c.scale = (0.63, 0.88, 0.02)
    c.rotation_euler = (0, 0, math.radians(rot_deg))
    c.data.materials.append(make_mat(name + "_mat", color, rough=0.35))
    bev = c.modifiers.new("Bevel", 'BEVEL'); bev.width = 0.03; bev.segments = 3
    return c

# --- felt ground ---
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
felt = bpy.context.object; felt.name = "Felt"
felt.data.materials.append(make_mat("Felt", FELT, rough=0.9))

# --- fanned arc of 7 cards ---
for i in range(7):
    t = i - 3                      # -3..3
    ang = t * -12                  # fan angle
    x = t * 0.55
    y = -abs(t) * 0.12             # slight arc dip
    color = RED if i % 2 else CREAM
    add_card(x, y, ang, color, f"Card{i}")

# --- camera ---
cam_data = bpy.data.cameras.new("Cam")
cam = bpy.data.objects.new("Cam", cam_data)
bpy.context.collection.objects.link(cam)
cam.location = (0, -3.4, 4.8); cam.rotation_euler = (math.radians(36), 0, 0)
bpy.context.scene.camera = cam

# --- key + gold rim lights ---
key = bpy.data.lights.new("Key", 'AREA'); key.energy = 900; key.size = 8
ko = bpy.data.objects.new("Key", key); bpy.context.collection.objects.link(ko)
ko.location = (3, -4, 8); ko.rotation_euler = (math.radians(30), 0, math.radians(25))

rim = bpy.data.lights.new("Rim", 'AREA'); rim.energy = 500; rim.size = 5
rim.color = (1.0, 0.78, 0.38)
ro = bpy.data.objects.new("Rim", rim); bpy.context.collection.objects.link(ro)
ro.location = (-3.5, 2.5, 3.5); ro.rotation_euler = (math.radians(115), 0, 0)

# --- render settings -> build/art (EEVEE Next for speed) ---
sc = bpy.context.scene
try:
    sc.render.engine = 'BLENDER_EEVEE_NEXT'
except TypeError:
    sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = 1024; sc.render.resolution_y = 1024
sc.render.film_transparent = True
sc.render.image_settings.file_format = 'PNG'
sc.render.image_settings.color_mode = 'RGBA'
sc.render.filepath = ROOT + "/build/art/fanned.png"
bpy.ops.render.render(write_still=True)
print("wrote", sc.render.filepath)
```

Expected: prints `wrote .../build/art/fanned.png`.

- [ ] **Step 2: Review the render**

Read `/home/dirk/projects/open-patience/build/art/fanned.png` with the Read
tool. Check: cards read as a fanned card spread, cream/red contrast, gold rim
light visible, transparent background, nothing clipped by the frame.

- [ ] **Step 3: Iterate if needed**

If the framing/lighting is off, re-run Step 1 with adjusted values
(`cam.location`/`rotation_euler` for framing, light `energy`/`color` for mood,
card `x`/`ang` spacing for the fan) and re-review. Repeat until clean. Do not
commit anything yet — these are throwaway prototypes.

### Task 3: Prototype the Klondike tableau subject

**Files:** none (MCP; produces `build/art/tableau.png`).

- [ ] **Step 1: Build the tableau scene**

Run via `blender-mcp_execute_blender_code`. This reuses the same helpers —
re-run the full setup block from Task 2 Step 1 **up to and including the felt
ground**, then replace the "fanned arc" section with:

```python
# --- 5 tableau columns of overlapping cards ---
for col in range(5):
    x = (col - 2) * 0.95
    for row in range(col + 1):
        y = 1.2 - row * 0.28
        face_up = (row == col)
        color = (RED if (col + row) % 2 else CREAM) if face_up else GOLD
        add_card(x, y, 0, color, f"T{col}_{row}")

# --- foundation row of 4 aces (cream) up top ---
for f in range(4):
    add_card((f - 1.5) * 0.95, 2.4, 0, CREAM, f"F{f}")
```

Keep the camera/lights/render block from Task 2 but change the output path:

```python
sc.render.filepath = ROOT + "/build/art/tableau.png"
```

and lift the camera to see the columns:

```python
cam.location = (0, -4.6, 6.2); cam.rotation_euler = (math.radians(40), 0, 0)
```

Expected: prints `wrote .../build/art/tableau.png`.

- [ ] **Step 2: Review** `/home/dirk/projects/open-patience/build/art/tableau.png`
  with Read. Check columns overlap cleanly, foundation row reads, framing holds.

- [ ] **Step 3: Iterate** camera/lights/spacing as in Task 2 Step 3 until clean.

### Task 4: Prototype the hero-ace subject

**Files:** none (MCP; produces `build/art/hero.png`).

- [ ] **Step 1: Build the hero-ace scene**

Run via `blender-mcp_execute_blender_code`. Re-run the Task 2 setup block up to
and including the felt ground, then:

```python
# --- one large hero card, slight tilt, floating ---
hero = add_card(0, 0, -8, CREAM, "Hero")
hero.scale = (1.15, 1.6, 0.03)
hero.location = (0, 0, 0.6)
hero.rotation_euler = (math.radians(-10), math.radians(6), math.radians(-8))

# --- a single red pip accent (small sphere) centered on the card ---
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.16, location=(0, 0, 0.66))
pip = bpy.context.object; pip.name = "Pip"
pip.data.materials.append(make_mat("Pip", RED, rough=0.3))

# --- soft gold under-glow (point light below/behind) ---
glow = bpy.data.lights.new("Glow", 'POINT'); glow.energy = 300
glow.color = (1.0, 0.8, 0.4)
go = bpy.data.objects.new("Glow", glow); bpy.context.collection.objects.link(go)
go.location = (0, 1.2, 1.6)
```

Camera closer, portrait-ish framing; change output path:

```python
cam.location = (0, -2.8, 2.6); cam.rotation_euler = (math.radians(52), 0, 0)
sc.render.filepath = ROOT + "/build/art/hero.png"
```

Expected: prints `wrote .../build/art/hero.png`.

- [ ] **Step 2: Review** `/home/dirk/projects/open-patience/build/art/hero.png`
  with Read. Check the hero card is centered with negative space, soft shadow,
  gold glow, transparent background.

- [ ] **Step 3: Iterate** until clean (Task 2 Step 3 method).

### Task 5: Present prototypes and get the pick

**Files:** none.

- [ ] **Step 1:** Show the user the three renders (`build/art/fanned.png`,
  `build/art/tableau.png`, `build/art/hero.png`) and ask which subject to
  finalize. **Wait for the choice** before continuing. The chosen subject's
  build code becomes the basis for both final scenes.

---

## Phase 2 — Finalize the chosen art

The chosen subject is built twice with different framing/resolution and saved as
two `.blend` files, then rendered into `assets/images/` by `build_art.py`.

### Task 6: Save the splash `.blend` (centered ~1152² framing)

**Files:** Create `tools/art/splash_scene.blend`.

- [ ] **Step 1: Build + save via MCP**

Run via `blender-mcp_execute_blender_code`: rebuild the **chosen** subject's
scene (from its Task 2/3/4 code), set a centered square framing and 1152²
resolution, then save the `.blend`:

```python
ROOT = "/home/dirk/projects/open-patience"
sc = bpy.context.scene
sc.render.resolution_x = 1152; sc.render.resolution_y = 1152
sc.render.film_transparent = True
# (adjust cam.location/rotation for a centered, well-margined composition)
bpy.ops.wm.save_as_mainfile(filepath=ROOT + "/tools/art/splash_scene.blend")
print("saved splash_scene.blend")
```

Expected: prints `saved splash_scene.blend`; file exists at
`tools/art/splash_scene.blend`.

### Task 7: Save the banner `.blend` (landscape ~1600×800 framing)

**Files:** Create `tools/art/banner_scene.blend`.

- [ ] **Step 1: Build + save via MCP**

Run via `blender-mcp_execute_blender_code`: rebuild the chosen subject, set a
wide framing and 1600×800 resolution, then save:

```python
ROOT = "/home/dirk/projects/open-patience"
sc = bpy.context.scene
sc.render.resolution_x = 1600; sc.render.resolution_y = 800
sc.render.film_transparent = True
# (widen the camera / spread the cards so the composition fills a 2:1 frame)
bpy.ops.wm.save_as_mainfile(filepath=ROOT + "/tools/art/banner_scene.blend")
print("saved banner_scene.blend")
```

Expected: prints `saved banner_scene.blend`; file exists.

### Task 8: Write the `build_art.py` render script

**Files:** Create `tools/art/build_art.py`.

- [ ] **Step 1: Create the script**

```python
#!/usr/bin/env python3
"""Render splash + menu-banner art from the editable Blender scenes.

The artwork lives in ``tools/art/splash_scene.blend`` and
``tools/art/banner_scene.blend`` -- open those in Blender to tweak cards,
camera, lighting or materials by hand. This script loads each .blend and
renders it into the two transparent PNGs the app bundles:

  * assets/images/splash.png      -- centered splash art (transparent).
  * assets/images/menu_banner.png -- wide menu banner (transparent).

Run it headless (Blender installed as a Flatpak here)::

    flatpak run org.blender.Blender --background \\
        --python tools/art/build_art.py

Or from a normal Blender install::

    blender --background --python tools/art/build_art.py

The .blend files are the single source of truth: edit them, re-run this
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


def render_to(scene, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("wrote", path)


def main():
    for blend, out in SCENES:
        bpy.ops.wm.open_mainfile(filepath=os.path.join(HERE, blend))
        render_to(bpy.context.scene, os.path.join(OUT_DIR, out))


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it to produce the final assets**

Run: `flatpak run org.blender.Blender --background --python /home/dirk/projects/open-patience/tools/art/build_art.py`
Expected: prints `wrote .../assets/images/splash.png` and
`wrote .../assets/images/menu_banner.png`; both files exist.

- [ ] **Step 3: Review both final PNGs** with the Read tool. Confirm resolution,
  transparency, and composition. Re-open/tweak the `.blend` + re-run if needed.

- [ ] **Step 4: Commit the art pipeline**

```bash
cd /home/dirk/projects/open-patience
git add tools/art/build_art.py tools/art/splash_scene.blend \
        tools/art/banner_scene.blend assets/images/splash.png \
        assets/images/menu_banner.png
git commit -m "feat: add Blender splash + menu-banner art and render script"
```

---

## Phase 3 — Menu banner widget (TDD)

### Task 9: `MenuBanner` widget

**Files:**
- Create: `lib/ui/widgets/menu_banner.dart`
- Test: `test/widget/menu_banner_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/widget/menu_banner_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/widgets/menu_banner.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('MenuBanner shows the banner asset', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_wrap(const MenuBanner()));
    final Image img = tester.widget<Image>(find.byType(Image));
    expect(img.image, isA<AssetImage>());
    expect(
      (img.image as AssetImage).assetName,
      'assets/images/menu_banner.png',
    );
  });

  testWidgets('MenuBanner settles (no pending timers) under reduced motion', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const MenuBanner(), disableAnimations: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MenuBanner), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/widget/menu_banner_test.dart`
Expected: FAIL — `menu_banner.dart` / `MenuBanner` does not exist.

- [ ] **Step 3: Implement the widget**

Create `lib/ui/widgets/menu_banner.dart`:

```dart
import 'package:flutter/material.dart';

/// The main-menu hero banner: a static Blender-rendered art asset with a
/// subtle, looping vertical float. The motion is disabled when the platform
/// requests reduced motion — that also keeps widget tests free of pending
/// animation timers.
class MenuBanner extends StatefulWidget {
  const MenuBanner({this.height = 168, super.key});

  final double height;

  @override
  State<MenuBanner> createState() => _MenuBannerState();
}

class _MenuBannerState extends State<MenuBanner>
    with SingleTickerProviderStateMixin {
  static const AssetImage _art = AssetImage('assets/images/menu_banner.png');

  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _controller?.dispose();
      _controller = null;
      return;
    }
    _controller ??= AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Widget image = Image(image: _art, fit: BoxFit.contain);
    final AnimationController? controller = _controller;
    if (controller == null) {
      return SizedBox(height: widget.height, child: image);
    }
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? child) {
          final double dy = (controller.value - 0.5) * 8; // ±4px float
          return Transform.translate(offset: Offset(0, dy), child: child);
        },
        child: image,
      ),
    );
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/widget/menu_banner_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
cd /home/dirk/projects/open-patience
git add lib/ui/widgets/menu_banner.dart test/widget/menu_banner_test.dart
git commit -m "feat: add animated MenuBanner widget"
```

### Task 10: Declare `assets/images/` and wire the banner into the menu

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/ui/main_menu_screen.dart:33` (the `FeltHeader` line)
- Modify: `test/widget/main_menu_test.dart:20-22`

- [ ] **Step 1: Add the assets declaration to `pubspec.yaml`**

Under `flutter:`, immediately below `uses-material-design: true`, add:

```yaml
  assets:
    - assets/images/
```

- [ ] **Step 2: Run `flutter pub get`**

Run: `cd /home/dirk/projects/open-patience && flutter pub get`
Expected: resolves with no errors.

- [ ] **Step 3: Insert the banner above the header**

In `lib/ui/main_menu_screen.dart`, add the import near the other `ui` imports:

```dart
import 'widgets/menu_banner.dart';
```

Then change the header line (currently
`const FeltHeader(title: '♠ Open Patience ♥'),`) to place the banner above it:

```dart
              const MenuBanner(),
              const FeltHeader(title: '♠ Open Patience ♥'),
```

- [ ] **Step 4: Update `main_menu_test.dart` to disable animations**

The menu now hosts a repeating animation; `pumpAndSettle` would otherwise hang.
Replace the `pumpWidget` call (lines 20-22) so the menu is wrapped with reduced
motion:

```dart
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: MainMenuScreen(repository: repo)),
      ),
    );
```

- [ ] **Step 5: Run the menu + banner tests**

Run: `flutter test test/widget/main_menu_test.dart test/widget/menu_banner_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd /home/dirk/projects/open-patience
git add pubspec.yaml lib/ui/main_menu_screen.dart test/widget/main_menu_test.dart
git commit -m "feat: show animated banner on the main menu"
```

---

## Phase 4 — Native splash

### Task 11: Configure `flutter_native_splash`

**Files:** Modify `pubspec.yaml`.

- [ ] **Step 1: Add the dev dependency**

Run: `cd /home/dirk/projects/open-patience && flutter pub add --dev flutter_native_splash`
Expected: adds `flutter_native_splash` under `dev_dependencies` and runs
`pub get`.

- [ ] **Step 2: Add the config block to `pubspec.yaml`**

At the top level (a sibling of `flutter:` / `flutter_launcher_icons:`), add:

```yaml
# Startup splash. Source art is rendered in Blender via
# `tools/art/build_art.py`. Regenerate native splash assets with:
#   dart run flutter_native_splash:create
flutter_native_splash:
  color: "#14532D"
  image: assets/images/splash.png
  android: true
  ios: true
  android_12:
    image: assets/images/splash.png
    color: "#14532D"
```

- [ ] **Step 3: Generate the native splash assets**

Run: `cd /home/dirk/projects/open-patience && dart run flutter_native_splash:create`
Expected: prints generation progress and finishes without error; modifies
`android/` (and `ios/`) resources.

- [ ] **Step 4: Commit**

```bash
cd /home/dirk/projects/open-patience
git add pubspec.yaml pubspec.lock android ios
git commit -m "feat: add native startup splash via flutter_native_splash"
```

---

## Phase 5 — Full verification

### Task 12: Gates green

**Files:** none.

- [ ] **Step 1: Format**

Run: `cd /home/dirk/projects/open-patience && dart format lib test tools 2>/dev/null; dart format --set-exit-if-changed lib test`
Expected: no formatting diffs (exit 0). (`tools/` holds Python; the second
command only enforces Dart.)

- [ ] **Step 2: Analyze**

Run: `cd /home/dirk/projects/open-patience && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: Core/persistence Flutter-boundary check**

Run: `cd /home/dirk/projects/open-patience && ! grep -rl "package:flutter" lib/core lib/persistence`
Expected: exit 0 (no matches).

- [ ] **Step 4: Full test suite**

Run: `cd /home/dirk/projects/open-patience && flutter test`
Expected: all tests PASS.

- [ ] **Step 5: Manual smoke (optional, if a device/emulator is available)**

Run: `cd /home/dirk/projects/open-patience && flutter run`
Confirm: splash paints on launch (felt bg + centered art); the main menu shows
the banner gently floating.

---

## Notes for the implementer

- Blender's Principled BSDF input names vary by version; if `make_mat` raises a
  `KeyError` on an input name, print `bpy.data.materials[...]` node inputs and
  adjust (Base Color / Roughness are stable across 4.x).
- If EEVEE Next is unavailable, the `try/except` falls back to legacy EEVEE.
  Cycles also works but is slower without a configured GPU.
- Keep prototype renders in `build/art/` only; never commit them.
- The banner motion is intentionally tiny (±4px). If it reads as too much,
  reduce the `* 8` multiplier in `menu_banner.dart`.
