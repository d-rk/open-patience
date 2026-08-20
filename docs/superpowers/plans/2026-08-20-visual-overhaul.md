# Visual Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reskin the whole app into a playful "Emerald Felt" game aesthetic and introduce a shared `lib/ui/theme/` design system, while relaying out the play screen (no AppBar, stats at bottom, actions behind a menu dialog).

**Architecture:** Presentation-only change. A new `lib/ui/theme/` subsystem holds design tokens (`game_palette.dart`), a `ThemeData` wired into the root `MaterialApp` (`app_theme.dart`), and shared widgets (`widgets.dart`). Every screen (play, main menu, records) is restyled to compose from these. `lib/core/` and `lib/persistence/` are untouched and stay Flutter-free.

**Tech Stack:** Flutter 3.38.5 / Dart 3.10, `flutter_bloc`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-08-20-visual-overhaul-design.md`

## Global Constraints

- No `package:flutter` imports in `lib/core/` or `lib/persistence/` (CI grep enforced).
- Dart style: 2-space indent, single quotes, trailing commas on multi-line, lines < 100 chars, explicit static types on public APIs, `const` widget constructors where possible.
- All colors/shapes come from `lib/ui/theme/`; no new `Color(0x…)` literals outside `lib/ui/theme/`.
- Preserve exact user-facing strings the widget suite matches: `'$moveCount moves'`, `mm:ss` (via `formatDuration`), and the `Undo` / `Redo` button tooltips. Preserve `CardFace` `Semantics` labels.
- After each task: `flutter analyze` clean, `flutter test` green, `dart format .` no diffs.
- Every commit message ends with the repo's `Co-Authored-By` / `Claude-Session` trailer lines.

---

### Task 1: Design tokens + `formatDuration` (`game_palette.dart`)

**Files:**
- Create: `lib/ui/theme/game_palette.dart`
- Test: `test/unit/game_palette_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class GamePalette` with `static const` color tokens: `feltGreenLight`, `feltGreenDark`, `feltGreenMid`, `gold`, `cardFace`, `cardRed`, `cardInk`, `pileSlotOutline`, `actionRestartBg`, `actionRestartFg`, `actionShuffleBg`, `actionShuffleFg`, `actionExitBg`, `actionExitFg`; and `static const RadialGradient feltGradient`.
  - Top-level `String formatDuration(int seconds)` → `'mm:ss'`.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/game_palette_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/ui/theme/game_palette.dart';

void main() {
  group('formatDuration', () {
    test('pads minutes and seconds to mm:ss', () {
      expect(formatDuration(0), '00:00');
      expect(formatDuration(9), '00:09');
      expect(formatDuration(75), '01:15');
      expect(formatDuration(600), '10:00');
    });
  });

  test('palette exposes the felt gradient and gold accent', () {
    expect(GamePalette.feltGradient.colors, isNotEmpty);
    expect(GamePalette.gold, const Color(0xFFF6C65B));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/game_palette_test.dart`
Expected: FAIL — `game_palette.dart` / `GamePalette` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/theme/game_palette.dart
import 'package:flutter/material.dart';

/// Emerald Felt design tokens — the single source of truth for the game's
/// palette. Widgets reference these instead of hardcoding colors.
class GamePalette {
  GamePalette._();

  // Felt table.
  static const Color feltGreenLight = Color(0xFF2E8B57);
  static const Color feltGreenMid = Color(0xFF1C6B3C);
  static const Color feltGreenDark = Color(0xFF14532D);
  static const RadialGradient feltGradient = RadialGradient(
    center: Alignment(0, -0.8),
    radius: 1.2,
    colors: <Color>[feltGreenLight, feltGreenDark],
  );

  // Accent + cards.
  static const Color gold = Color(0xFFF6C65B);
  static const Color cardFace = Color(0xFFFFF8EC);
  static const Color cardRed = Color(0xFFC0392B);
  static const Color cardInk = Color(0xFF1C2833);

  // Empty pile slot outline (gold at ~50%).
  static const Color pileSlotOutline = Color(0x80F6C65B);

  // Menu action tiles.
  static const Color actionRestartBg = Color(0xFFD6F0DD);
  static const Color actionRestartFg = Color(0xFF14532D);
  static const Color actionShuffleBg = Color(0xFFFFE6A8);
  static const Color actionShuffleFg = Color(0xFF7A5A00);
  static const Color actionExitBg = Color(0xFFF6D2CE);
  static const Color actionExitFg = Color(0xFF8A2B22);
}

/// Formats a whole number of [seconds] as `mm:ss`.
String formatDuration(int seconds) {
  final int minutes = seconds ~/ 60;
  final int secs = seconds % 60;
  final String mm = minutes.toString().padLeft(2, '0');
  final String ss = secs.toString().padLeft(2, '0');
  return '$mm:$ss';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/game_palette_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/theme/game_palette.dart test/unit/game_palette_test.dart
git commit -m "Add Emerald Felt design tokens and formatDuration"
```

---

### Task 2: App-wide `ThemeData` (`app_theme.dart`) wired into `main.dart`

**Files:**
- Create: `lib/ui/theme/app_theme.dart`
- Modify: `lib/main.dart:25-33` (replace the inline `ThemeData`)
- Test: `test/unit/app_theme_test.dart`

**Interfaces:**
- Consumes: `GamePalette` (Task 1).
- Produces: `class AppTheme` with `static ThemeData get themeData`.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/app_theme_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/ui/theme/app_theme.dart';
import 'package:solitaire/ui/theme/game_palette.dart';

void main() {
  test('themeData uses Material 3 and the gold secondary', () {
    final ThemeData theme = AppTheme.themeData;
    expect(theme.useMaterial3, isTrue);
    expect(theme.colorScheme.secondary, GamePalette.gold);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/app_theme_test.dart`
Expected: FAIL — `AppTheme` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/theme/app_theme.dart
import 'package:flutter/material.dart';

import 'game_palette.dart';

/// The app-wide [ThemeData]. Wired into the root `MaterialApp` so standard
/// Material widgets inherit the Emerald Felt look with no per-widget styling.
class AppTheme {
  AppTheme._();

  static ThemeData get themeData {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: GamePalette.feltGreenLight,
      primary: GamePalette.feltGreenMid,
      secondary: GamePalette.gold,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: GamePalette.feltGreenDark,
      cardTheme: CardThemeData(
        color: GamePalette.cardFace,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: GamePalette.cardFace,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          backgroundColor: GamePalette.feltGreenMid,
          foregroundColor: GamePalette.cardFace,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          foregroundColor: GamePalette.feltGreenMid,
          side: const BorderSide(color: GamePalette.feltGreenMid, width: 2),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: GamePalette.feltGreenMid,
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Wire it into `main.dart`**

In `lib/main.dart`, add the import and replace the `theme:` argument:

```dart
import 'ui/theme/app_theme.dart';
```

```dart
    return MaterialApp(
      title: 'Solitaire',
      theme: AppTheme.themeData,
      home: MainMenuScreen(
        repository: repository,
        autoTick: const Duration(seconds: 1),
      ),
    );
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/unit/app_theme_test.dart && flutter analyze`
Expected: PASS, no analyzer issues.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/theme/app_theme.dart lib/main.dart test/unit/app_theme_test.dart
git commit -m "Add app-wide Emerald Felt ThemeData"
```

---

### Task 3: Shared themed widgets (`widgets.dart`)

**Files:**
- Create: `lib/ui/theme/widgets.dart`
- Test: `test/widget/theme_widgets_test.dart`

**Interfaces:**
- Consumes: `GamePalette` (Task 1).
- Produces:
  - `FeltBackground({required Widget child})`
  - `FeltHeader({required String title, VoidCallback? onBack})`
  - `GamePill({required IconData icon, required String label})`
  - `GameActionTile({required IconData icon, required String label, required Color background, required Color foreground, required VoidCallback onPressed, bool fullWidth = false})`

- [ ] **Step 1: Write the failing test**

```dart
// test/widget/theme_widgets_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/ui/theme/widgets.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('GamePill renders its label', (WidgetTester tester) async {
    await _pump(tester, const GamePill(icon: Icons.timer, label: '01:15'));
    expect(find.text('01:15'), findsOneWidget);
  });

  testWidgets('FeltHeader shows the title and fires onBack', (
    WidgetTester tester,
  ) async {
    int backs = 0;
    await _pump(
      tester,
      FeltHeader(title: 'Records', onBack: () => backs++),
    );
    expect(find.text('Records'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    expect(backs, 1);
  });

  testWidgets('GameActionTile fires onPressed', (WidgetTester tester) async {
    int taps = 0;
    await _pump(
      tester,
      GameActionTile(
        icon: Icons.replay,
        label: 'Restart',
        background: const Color(0xFFD6F0DD),
        foreground: const Color(0xFF14532D),
        onPressed: () => taps++,
      ),
    );
    await tester.tap(find.text('Restart'));
    expect(taps, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/theme_widgets_test.dart`
Expected: FAIL — `widgets.dart` / these classes not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/theme/widgets.dart
import 'package:flutter/material.dart';

import 'game_palette.dart';

/// Paints the Emerald Felt gradient behind [child]. Wrap a screen body in it.
class FeltBackground extends StatelessWidget {
  const FeltBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: GamePalette.feltGradient),
      child: child,
    );
  }
}

/// A themed screen header: gold [title] with an optional leading back button.
/// Replaces the Material `AppBar` on themed screens.
class FeltHeader extends StatelessWidget {
  const FeltHeader({required this.title, this.onBack, super.key});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: <Widget>[
          if (onBack != null)
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back, color: GamePalette.gold),
              onPressed: onBack,
            ),
          Text(
            title,
            style: const TextStyle(
              color: GamePalette.gold,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded stat pill (icon + label) used for timer / moves.
class GamePill extends StatelessWidget {
  const GamePill({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: GamePalette.gold),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: GamePalette.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A menu action tile (icon + label on a colored, rounded background).
class GameActionTile extends StatelessWidget {
  const GameActionTile({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
    this.fullWidth = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: foreground, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/widget/theme_widgets_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/theme/widgets.dart test/widget/theme_widgets_test.dart
git commit -m "Add shared themed widgets: FeltBackground, FeltHeader, GamePill, GameActionTile"
```

---

### Task 4: Relayout the play screen (TopBar + StatBar, remove AppBar, retire Hud)

**Files:**
- Create: `lib/ui/top_bar.dart`, `lib/ui/stat_bar.dart`
- Modify: `lib/ui/game_screen.dart` (remove AppBar; new Column layout; add `onMenu` stub)
- Modify: `lib/ui/records_screen.dart:5,45` (drop `import 'hud.dart'`; use `formatDuration`)
- Delete: `lib/ui/hud.dart`
- Modify: `test/widget/game_widget_test.dart` (only if needed — expected to pass unchanged)

**Interfaces:**
- Consumes: `GamePalette`, `GamePill`, `formatDuration` (Tasks 1, 3); `GameBloc`, `GameBlocState`, `UndoRequested`, `RedoRequested`.
- Produces:
  - `TopBar({required VoidCallback onMenu})` — a Row: ☰ button (tooltip `'Menu'`) left; Undo/Redo IconButtons right (tooltips `'Undo'`/`'Redo'`, disabled when `!canUndo`/`!canRedo`).
  - `StatBar()` — a centered Row of two `GamePill`s: timer (`formatDuration(elapsedSeconds)`) and `'$moveCount moves'`.

> Note: this task deletes `Hud`. `records_screen.dart` currently calls `Hud.formatDuration`; switch it to the top-level `formatDuration` from `game_palette.dart` here so the app keeps compiling. The full records restyle is Task 9.

- [ ] **Step 1: Write the failing test (menu button + stats survive relayout)**

Add to `test/widget/game_widget_test.dart` (imports already present for GameBloc etc.):

```dart
  testWidgets('play screen shows a menu button and no AppBar', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    final GameBloc bloc = _bloc(
      repo,
      GameState.newGame(KlondikeRules(), seed: 42),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('Menu'), findsOneWidget);
    expect(find.text('0 moves'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/game_widget_test.dart -n 'menu button'`
Expected: FAIL — AppBar still present / no `Menu` tooltip.

- [ ] **Step 3: Create `StatBar`**

```dart
// lib/ui/stat_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../presentation/bloc/game_bloc.dart';
import '../presentation/bloc/game_bloc_state.dart';
import 'theme/game_palette.dart';
import 'theme/widgets.dart';

/// Bottom-of-screen play stats: elapsed time and move count as pills. Rebuilds
/// only when the shown values change.
class StatBar extends StatelessWidget {
  const StatBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GameBloc, GameBlocState>(
      buildWhen: (GameBlocState previous, GameBlocState current) =>
          previous.state.elapsedSeconds != current.state.elapsedSeconds ||
          previous.state.moveCount != current.state.moveCount,
      builder: (BuildContext context, GameBlocState state) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              GamePill(
                icon: Icons.timer_outlined,
                label: formatDuration(state.state.elapsedSeconds),
              ),
              const SizedBox(width: 12),
              GamePill(
                icon: Icons.swap_vert,
                label: '${state.state.moveCount} moves',
              ),
            ],
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Create `TopBar`**

```dart
// lib/ui/top_bar.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../presentation/bloc/game_bloc.dart';
import '../presentation/bloc/game_bloc_state.dart';
import '../presentation/bloc/game_event.dart';
import 'theme/game_palette.dart';

/// The slim play-screen top bar: a menu button on the left, undo/redo on the
/// right. Undo/redo enablement rebuilds only when it changes.
class TopBar extends StatelessWidget {
  const TopBar({required this.onMenu, super.key});

  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final GameBloc bloc = context.read<GameBloc>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: <Widget>[
          _MenuButton(onMenu: onMenu),
          const Spacer(),
          BlocBuilder<GameBloc, GameBlocState>(
            buildWhen: (GameBlocState p, GameBlocState c) =>
                p.state.canUndo != c.state.canUndo ||
                p.state.canRedo != c.state.canRedo,
            builder: (BuildContext context, GameBlocState state) {
              return Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Undo',
                    color: GamePalette.gold,
                    icon: const Icon(Icons.undo),
                    onPressed: state.state.canUndo
                        ? () => bloc.add(const UndoRequested())
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Redo',
                    color: GamePalette.gold,
                    icon: const Icon(Icons.redo),
                    onPressed: state.state.canRedo
                        ? () => bloc.add(const RedoRequested())
                        : null,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onMenu});

  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GamePalette.gold,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onMenu,
        child: Tooltip(
          message: 'Menu',
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.menu, color: GamePalette.feltGreenDark),
          ),
        ),
      ),
    );
  }
}
```

> The `Tooltip` gives `find.byTooltip('Menu')` a match without an `IconButton`.

- [ ] **Step 5: Rebuild `game_screen.dart` body**

Replace the `build` method's `Scaffold` and remove the `import 'hud.dart';`. Add imports for `top_bar.dart`, `stat_bar.dart`, and `theme/widgets.dart`. Leave `_showWin` unchanged.

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FeltBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              TopBar(onMenu: () {}),
              Expanded(
                child: BlocListener<GameBloc, GameBlocState>(
                  listenWhen:
                      (GameBlocState previous, GameBlocState current) =>
                          current is GameWon && previous is! GameWon,
                  listener: (BuildContext context, GameBlocState state) {
                    final GameBloc bloc = context.read<GameBloc>();
                    _showWin(context, bloc, state as GameWon);
                  },
                  child: const Board(),
                ),
              ),
              const StatBar(),
            ],
          ),
        ),
      ),
    );
  }
```

> `onMenu: () {}` is a temporary stub; Task 5 wires the dialog. The `variantTitle` helper and `_showWin` stay in this file.

- [ ] **Step 6: Update `records_screen.dart` to drop the Hud dependency**

- Remove `import 'hud.dart';`, add `import 'theme/game_palette.dart';`.
- Change `Hud.formatDuration(stats.bestTimeSeconds!)` to `formatDuration(stats.bestTimeSeconds!)`.

- [ ] **Step 7: Delete `lib/ui/hud.dart`**

```bash
git rm lib/ui/hud.dart
```

- [ ] **Step 8: Run the full suite**

Run: `flutter test && flutter analyze`
Expected: PASS. The existing `new deal…`, undo/redo, tap, drag, win, and resume tests still pass (strings/tooltips preserved); the new `menu button` test passes.

- [ ] **Step 9: Format + commit**

```bash
dart format .
git add -A
git commit -m "Relayout play screen: top bar + bottom stats, retire Hud"
```

---

### Task 5: Game menu dialog (`game_menu.dart`) wired to ☰

**Files:**
- Create: `lib/ui/game_menu.dart`
- Modify: `lib/ui/game_screen.dart` (replace `onMenu: () {}` with `showGameMenu`)
- Test: `test/widget/game_menu_test.dart`

**Interfaces:**
- Consumes: `GameBloc`, `variantTitle` (from `game_screen.dart`), `RestartDealRequested`, `NewDealRequested`, `GameActionTile`, `formatDuration`, `GamePalette`.
- Produces: `Future<void> showGameMenu(BuildContext context, GameBloc bloc)`.

- [ ] **Step 1: Write the failing test**

```dart
// test/widget/game_menu_test.dart
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solitaire/core/card.dart';
import 'package:solitaire/core/game_state.dart';
import 'package:solitaire/core/pile.dart';
import 'package:solitaire/persistence/records_repository.dart';
import 'package:solitaire/persistence/shared_prefs_records_repository.dart';
import 'package:solitaire/presentation/bloc/game_bloc.dart';
import 'package:solitaire/presentation/bloc/game_event.dart';
import 'package:solitaire/ui/game_screen.dart';

class _RecordingBloc extends GameBloc {
  _RecordingBloc(RecordsRepository repo, GameState state)
      : super(
          variant: 'klondike-draw1',
          repository: repo,
          seed: 5,
          state: state,
        );

  final List<GameEvent> recorded = <GameEvent>[];

  @override
  void add(GameEvent event) {
    recorded.add(event);
    super.add(event);
  }
}

GameState _oneCard() => GameState(
      piles: <Pile>[
        Pile(kind: PileKind.stock),
        Pile(kind: PileKind.waste),
        Pile(kind: PileKind.foundation),
        Pile(kind: PileKind.foundation),
        Pile(kind: PileKind.foundation),
        Pile(kind: PileKind.foundation),
        Pile(
          kind: PileKind.tableau,
          cards: <Card>[Card(suit: Suit.spades, rank: 7, faceUp: true)],
        ),
        Pile(kind: PileKind.tableau),
        Pile(kind: PileKind.tableau),
        Pile(kind: PileKind.tableau),
        Pile(kind: PileKind.tableau),
        Pile(kind: PileKind.tableau),
        Pile(kind: PileKind.tableau),
      ],
    );

Future<_RecordingBloc> _repoBloc() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return _RecordingBloc(SharedPrefsRecordsRepository(prefs), _oneCard());
}

Future<void> _pump(WidgetTester tester, GameBloc bloc) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<GameBloc>.value(value: bloc, child: const GameScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menu'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menu opens and shows the variant title', (
    WidgetTester tester,
  ) async {
    final _RecordingBloc bloc = await _repoBloc();
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await _openMenu(tester);
    expect(find.text('Klondike (Draw 1)'), findsOneWidget);
  });

  testWidgets('Restart tile dispatches RestartDealRequested and closes', (
    WidgetTester tester,
  ) async {
    final _RecordingBloc bloc = await _repoBloc();
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await _openMenu(tester);
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();
    expect(bloc.recorded.whereType<RestartDealRequested>(), isNotEmpty);
    expect(find.text('Restart'), findsNothing); // dialog closed
  });

  testWidgets('Shuffle tile dispatches NewDealRequested and closes', (
    WidgetTester tester,
  ) async {
    final _RecordingBloc bloc = await _repoBloc();
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await _openMenu(tester);
    await tester.tap(find.text('Shuffle'));
    await tester.pumpAndSettle();
    expect(bloc.recorded.whereType<NewDealRequested>(), isNotEmpty);
    expect(find.text('Shuffle'), findsNothing);
  });

  testWidgets('Exit closes the dialog and pops back to the previous screen', (
    WidgetTester tester,
  ) async {
    final _RecordingBloc bloc = await _repoBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BlocProvider<GameBloc>.value(
                      value: bloc,
                      child: const GameScreen(),
                    ),
                  ),
                ),
                child: const Text('play'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    await tester.tap(find.text('Exit to menu'));
    await tester.pumpAndSettle();
    expect(find.text('play'), findsOneWidget); // back on the launcher screen
    expect(find.byType(GameScreen), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/game_menu_test.dart`
Expected: FAIL — `find.text('Klondike (Draw 1)')` not found (no menu wired).

- [ ] **Step 3: Implement `showGameMenu`**

```dart
// lib/ui/game_menu.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../presentation/bloc/game_bloc.dart';
import '../presentation/bloc/game_bloc_state.dart';
import '../presentation/bloc/game_event.dart';
import 'game_screen.dart' show variantTitle;
import 'theme/game_palette.dart';
import 'theme/widgets.dart';

/// Opens the in-game menu: variant title + live stats banner over Restart,
/// Shuffle and Exit actions. Each action dismisses the dialog first.
Future<void> showGameMenu(BuildContext context, GameBloc bloc) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: GamePalette.gold, width: 3),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _Banner(bloc: bloc),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: GameActionTile(
                          icon: Icons.replay,
                          label: 'Restart',
                          background: GamePalette.actionRestartBg,
                          foreground: GamePalette.actionRestartFg,
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            bloc.add(const RestartDealRequested());
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GameActionTile(
                          icon: Icons.shuffle,
                          label: 'Shuffle',
                          background: GamePalette.actionShuffleBg,
                          foreground: GamePalette.actionShuffleFg,
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            bloc.add(const NewDealRequested());
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: GameActionTile(
                      icon: Icons.logout,
                      label: 'Exit to menu',
                      background: GamePalette.actionExitBg,
                      foreground: GamePalette.actionExitFg,
                      onPressed: () {
                        Navigator.of(dialogContext).pop(); // close dialog
                        Navigator.of(context).pop(); // leave the play screen
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.bloc});

  final GameBloc bloc;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[GamePalette.feltGreenMid, GamePalette.feltGreenLight],
        ),
      ),
      child: Column(
        children: <Widget>[
          Text(
            variantTitle(bloc.variant),
            style: const TextStyle(
              color: GamePalette.gold,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          BlocBuilder<GameBloc, GameBlocState>(
            bloc: bloc,
            builder: (BuildContext context, GameBlocState state) {
              return Text(
                '${formatDuration(state.state.elapsedSeconds)} · '
                '${state.state.moveCount} moves',
                style: TextStyle(
                  color: GamePalette.cardFace.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Wire ☰ in `game_screen.dart`**

Add `import 'game_menu.dart';` and replace the stub:

```dart
              TopBar(
                onMenu: () => showGameMenu(context, context.read<GameBloc>()),
              ),
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/widget/game_menu_test.dart && flutter test`
Expected: PASS (all four menu tests; full suite still green).

- [ ] **Step 6: Format + commit**

```bash
dart format .
git add -A
git commit -m "Add in-game menu dialog: Restart, Shuffle, Exit"
```

---

### Task 6: Restyle the card face (Classic Crisp)

**Files:**
- Modify: `lib/presentation/card_view.dart:134-200` (`CardFace.build`)
- Test: existing `test/widget/game_widget_test.dart` finders must keep passing.

**Interfaces:**
- Consumes: `GamePalette`.
- Produces: no API change. `CardFace` keeps the same constructor and `Semantics` labels.

- [ ] **Step 1: Confirm the guard test passes today**

Run: `flutter test test/widget/game_widget_test.dart -n 'new deal'`
Expected: PASS — this test (via `find.byType(CardFace)` and `_cardFace`) is the regression guard for the restyle.

- [ ] **Step 2: Restyle `CardFace.build`**

Add `import 'theme/game_palette.dart';` (path: `../ui/theme/game_palette.dart` from `lib/presentation/`, i.e. `import '../ui/theme/game_palette.dart';`). Replace the face-up/face-down `Container`s:

```dart
  @override
  Widget build(BuildContext context) {
    final double radius = size.width * 0.12;
    if (!card.faceUp) {
      return Semantics(
        label: _semanticLabel,
        child: Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: GamePalette.gold, width: 2),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                GamePalette.feltGreenDark,
                GamePalette.feltGreenMid,
              ],
            ),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 2)),
            ],
          ),
        ),
      );
    }

    final Color color = card.isRed ? GamePalette.cardRed : GamePalette.cardInk;
    final String label = _rankLabels[card.rank];
    final String glyph = _suitGlyphs[card.suit]!;

    final Widget index = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: size.width * 0.28,
            fontWeight: FontWeight.w800,
            height: 0.9,
          ),
        ),
        Text(
          glyph,
          style: TextStyle(color: color, fontSize: size.width * 0.22, height: 0.9),
        ),
      ],
    );

    return Semantics(
      label: _semanticLabel,
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          color: GamePalette.cardFace,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 2)),
          ],
        ),
        child: Stack(
          children: <Widget>[
            // Faint center pip.
            Center(
              child: Text(
                glyph,
                style: TextStyle(
                  color: color.withValues(alpha: 0.14),
                  fontSize: size.width * 0.7,
                ),
              ),
            ),
            Positioned(top: size.width * 0.08, left: size.width * 0.1, child: index),
            // Mirrored bottom-right index.
            Positioned(
              bottom: size.width * 0.08,
              right: size.width * 0.1,
              child: Transform.rotate(angle: 3.14159, child: index),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 3: Run the guard tests**

Run: `flutter test test/widget/game_widget_test.dart && flutter analyze`
Expected: PASS — all board/drag/tap/win tests still green (semantics + geometry unchanged).

- [ ] **Step 4: Format + commit**

```bash
dart format .
git add lib/presentation/card_view.dart
git commit -m "Restyle card faces to Classic Crisp (cream, mirrored index, center pip)"
```

---

### Task 7: Restyle empty pile placeholders

**Files:**
- Modify: `lib/presentation/pile_view.dart:74-85` (`_placeholder`)

**Interfaces:**
- Consumes: `GamePalette`. No API change.

- [ ] **Step 1: Update `_placeholder`**

Add `import '../ui/theme/game_palette.dart';` and change the slot decoration to the gold-tinted outline:

```dart
    final Widget slot = Container(
      width: cardSize.width,
      height: cardSize.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cardSize.width * 0.12),
        border: Border.all(color: GamePalette.pileSlotOutline, width: 1.5),
      ),
      child: pile.kind == PileKind.stock
          ? const Center(child: Icon(Icons.refresh, color: GamePalette.gold))
          : null,
    );
```

- [ ] **Step 2: Run the suite**

Run: `flutter test && flutter analyze`
Expected: PASS.

- [ ] **Step 3: Format + commit**

```bash
dart format .
git add lib/presentation/pile_view.dart
git commit -m "Restyle empty pile slots with gold-tinted outline"
```

---

### Task 8: Restyle the main menu

**Files:**
- Modify: `lib/ui/main_menu_screen.dart` (replace AppBar with FeltHeader + FeltBackground; keep button labels/actions)
- Test: existing `test/widget/main_menu_test.dart` must keep passing.

**Interfaces:**
- Consumes: `FeltBackground`, `FeltHeader`, `GamePalette`. No navigation-logic change.

- [ ] **Step 1: Confirm current main-menu test passes**

Run: `flutter test test/widget/main_menu_test.dart`
Expected: PASS (regression guard). Note the strings it asserts (variant titles, `New game`, `Resume`, `Records`) — keep them.

- [ ] **Step 2: Replace the Scaffold shell**

Add imports for `theme/widgets.dart` and `theme/game_palette.dart`. Change `MainMenuScreen.build`:

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FeltBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const FeltHeader(title: '♠ Solitaire ♥'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    for (final String id in GameRegistry.ids)
                      _VariantCard(
                        variant: id,
                        repository: repository,
                        autoTick: autoTick,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
```

> `_VariantCard` already uses `Card` + `FilledButton`/`OutlinedButton`/`TextButton`, which now inherit the themed rounded/gold styles from `AppTheme` automatically. Only wrap the title in cream/ink if the analyzer/contrast needs it; otherwise leave `_VariantCard`'s internals as-is. Do not change its button labels or `onPressed` handlers.

- [ ] **Step 3: Run tests**

Run: `flutter test test/widget/main_menu_test.dart && flutter analyze`
Expected: PASS.

- [ ] **Step 4: Format + commit**

```bash
dart format .
git add lib/ui/main_menu_screen.dart
git commit -m "Restyle main menu onto the Emerald Felt theme"
```

---

### Task 9: Restyle the records screen

**Files:**
- Modify: `lib/ui/records_screen.dart` (replace AppBar with FeltHeader + FeltBackground; restyle `_RecordTile`)
- Test: existing `test/widget/game_widget_test.dart` win-flow assertions (`find.text('Games won')`) must keep passing.

**Interfaces:**
- Consumes: `FeltBackground`, `FeltHeader`, `GamePalette`. `formatDuration` already imported (Task 4). No data change; labels/values unchanged.

- [ ] **Step 1: Replace the Scaffold shell**

Add imports for `theme/widgets.dart` and `theme/game_palette.dart`. Change `build` to use a header with a back button:

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FeltBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FeltHeader(
                title: '$title — Records',
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    return FutureBuilder<Stats>(
      future: repository.statsFor(variant),
      builder: (BuildContext context, AsyncSnapshot<Stats> snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final Stats stats = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _RecordTile(label: 'Games played', value: '${stats.gamesPlayed}'),
            _RecordTile(label: 'Games won', value: '${stats.gamesWon}'),
            _RecordTile(
              label: 'Win rate',
              value: '${stats.winPercentage.toStringAsFixed(1)}%',
            ),
            _RecordTile(
              label: 'Best time',
              value: stats.bestTimeSeconds == null
                  ? '—'
                  : formatDuration(stats.bestTimeSeconds!),
            ),
            _RecordTile(
              label: 'Fewest moves',
              value: stats.fewestMoves?.toString() ?? '—',
            ),
            _RecordTile(label: 'Current streak', value: '${stats.currentStreak}'),
            _RecordTile(label: 'Longest streak', value: '${stats.longestStreak}'),
          ],
        );
      },
    );
  }
```

- [ ] **Step 2: Restyle `_RecordTile`**

```dart
class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          label,
          style: const TextStyle(
            color: GamePalette.feltGreenDark,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Text(
          value,
          style: const TextStyle(
            color: GamePalette.cardRed,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Run tests**

Run: `flutter test && flutter analyze`
Expected: PASS — the win flow still finds `Games won`; all suites green.

- [ ] **Step 4: Format + commit**

```bash
dart format .
git add lib/ui/records_screen.dart
git commit -m "Restyle records screen onto the Emerald Felt theme"
```

---

### Task 10: Document the design language in `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md` (add a "Design language" section)

**Interfaces:** none (docs only).

- [ ] **Step 1: Add the section**

Insert after the "Dart/Flutter style" section:

```markdown
## Design language

This is a **game, not an enterprise app** — the UI is playful, colorful and
rounded (the "Emerald Felt" look: green felt table, cream cards, gold
accents).

- All colors and shared shapes come from `lib/ui/theme/`:
  `game_palette.dart` (tokens + `formatDuration`), `app_theme.dart`
  (the `ThemeData` on the root `MaterialApp`), `widgets.dart`
  (`FeltBackground`, `FeltHeader`, `GamePill`, `GameActionTile`).
- Widgets never hardcode `Color(0x…)` or ad-hoc style colors — reference a
  token. New screens compose from the shared widgets and inherit `AppTheme`.
- Prefer rounded, tactile controls (stadium buttons, pill stats, tiles).
  Avoid stock enterprise-flat Material chrome (bare `AppBar` titles, plain
  list rows) on player-facing screens.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "Document the Emerald Felt design language in CLAUDE.md"
```

---

## Self-Review

**Spec coverage:**
- Emerald Felt / tokens → Task 1. ✅
- App-wide ThemeData + main.dart → Task 2. ✅
- Shared widgets → Task 3. ✅
- Play-screen relayout (no AppBar, top bar, bottom stats), Hud split, records `formatDuration` fix → Task 4. ✅
- Menu dialog (Restart/Shuffle/Exit, live banner) → Task 5. ✅
- Classic Crisp cards → Task 6. ✅
- Pile slot restyle → Task 7. ✅
- Main menu restyle → Task 8. ✅
- Records restyle → Task 9. ✅
- CLAUDE.md design-language rule → Task 10. ✅
- Out-of-scope (animations, CI color grep) correctly omitted. ✅

**Placeholder scan:** No TBD/TODO; every code step has concrete code. ✅

**Type consistency:** `formatDuration(int)` used identically in Tasks 1/4/5/9. `GamePalette.*` token names consistent across tasks. `GameActionTile`/`GamePill`/`FeltHeader`/`FeltBackground` signatures defined in Task 3 match their use in Tasks 4/5/8/9. `showGameMenu(BuildContext, GameBloc)` defined and called consistently (Task 5). `TopBar({onMenu})` / `StatBar()` defined in Task 4, wired in Tasks 4/5. ✅
