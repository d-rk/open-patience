# Main Menu Restructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the flat variant menu into a two-level games→variants flow, surface all in-progress games for one-tap resume, cap menu width on tablets, and add two param-only FreeCell cell-count variants.

**Architecture:** Introduce a game→variants grouping (`GameCatalog`) above the existing flat variant ids without changing what a variant id means or the records schema. FreeCell gains a `freecellCount` param (Classic keeps id `freecell`). The title screen lists games plus a Continue section from a new `loadAllSaves()`; a new options screen lists a game's variants.

**Tech Stack:** Flutter, Dart, flutter_bloc, shared_preferences, flutter_test.

**Spec:** `docs/superpowers/specs/2026-08-22-main-menu-restructure-design.md` (read it alongside this plan).

## Global Constraints

- **TDD is mandatory**: RED → GREEN → REFACTOR. No production code without a failing test first.
- **`lib/core/` and `lib/persistence/` import zero `package:flutter`.** `game_catalog.dart` imports only other `core/` files. Enforced by: `! grep -rl "package:flutter" lib/core lib/persistence`.
- **Explicit static types on all public APIs.** Single quotes; lines under 100 chars; 2-space indent; trailing commas on multi-line collections.
- **`dart format` clean; `flutter analyze` and `flutter test` green** before every commit.
- **Every commit message ends with the trailer:**
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`
- Work happens on branch `feat/main-menu-restructure` (already created).
- **Model guidance:** Tasks 1–6 are mechanical (Sonnet). Tasks 7–8 are UI-composition tasks (default/Opus).
- Variant ids (verbatim): `klondike-draw1`, `klondike-draw3`, `freecell`, `freecell-cells2`, `freecell-cells6`. Game ids: `klondike`, `freecell`.

---

### Task 1: FreeCell cell-count param (`freecellCount`)

**Model:** Sonnet (mechanical).

**Files:**
- Modify: `lib/core/games/freecell.dart`
- Test: `test/unit/freecell_test.dart` (add a group; update 3 static references)

**Interfaces:**
- Consumes: `GameState`, `Pile`, `PileKind`, `Card`, `Suit` (existing core).
- Produces: `FreecellRules({int freecellCount = 4})` with instance getters `int get firstFoundation` and `int get firstTableau`; `String get id` returns `'freecell'` for 4 cells else `'freecell-cells$freecellCount'`. `static const int firstFreecell = 0`, `static const int foundationCount = 4`, `static const int tableauCount = 8` remain.

- [ ] **Step 1: Write the failing tests**

Add this group to `test/unit/freecell_test.dart` (the `_c` helper and `Card`/`Suit`/`Pile` imports already exist in that file):

```dart
group('FreeCell cell-count variants', () {
  test('2-cell variant shifts offsets and deals 14 piles', () {
    final FreecellRules hard = FreecellRules(freecellCount: 2);
    expect(hard.id, 'freecell-cells2');
    expect(FreecellRules.firstFreecell, 0);
    expect(hard.firstFoundation, 2);
    expect(hard.firstTableau, 6);
    final GameState state = GameState.newGame(hard, seed: 5);
    expect(state.piles.length, 2 + 4 + 8);
    int total = 0;
    for (int i = 0; i < 8; i++) {
      total += state.pileAt(hard.firstTableau + i).length;
    }
    expect(total, 52);
  });

  test('6-cell variant has id freecell-cells6 and 18 piles', () {
    final FreecellRules easy = FreecellRules(freecellCount: 6);
    expect(easy.id, 'freecell-cells6');
    final GameState state = GameState.newGame(easy, seed: 8);
    expect(state.piles.length, 6 + 4 + 8);
  });

  test('classic 4-cell keeps id freecell for records backward-compat', () {
    expect(FreecellRules().id, 'freecell');
    expect(FreecellRules(freecellCount: 4).id, 'freecell');
  });

  test('maxMovable scales with the free-cell count', () {
    final FreecellRules hard = FreecellRules(freecellCount: 2);
    final List<Pile> piles = <Pile>[
      for (int i = 0; i < 2; i++) Pile(kind: PileKind.freecell),
      for (int i = 0; i < 4; i++) Pile(kind: PileKind.foundation),
      for (int i = 0; i < 8; i++) Pile(kind: PileKind.tableau),
    ];
    piles[6] = Pile(kind: PileKind.tableau, cards: <Card>[_c(Suit.spades, 5)]);
    final GameState state = GameState(piles: piles);
    // freeCells = 2, emptyColumns = 7 -> (2+1) * 2^7.
    expect(hard.maxMovable(state), (2 + 1) * (1 << 7));
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/freecell_test.dart`
Expected: FAIL — `FreecellRules` has no `freecellCount` named parameter / no `firstFoundation` instance getter.

- [ ] **Step 3: Make `freecellCount` a param and derive offsets**

In `lib/core/games/freecell.dart` replace the class header and offset constants:

```dart
class FreecellRules implements GameRules {
  FreecellRules({this.freecellCount = 4})
    : assert(
        freecellCount >= 1 && freecellCount <= 8,
        'freecellCount must be between 1 and 8',
      );

  static const int firstFreecell = 0;
  static const int foundationCount = 4;
  static const int tableauCount = 8;

  final int freecellCount;

  int get firstFoundation => freecellCount;
  int get firstTableau => freecellCount + foundationCount;

  @override
  String get id =>
      freecellCount == 4 ? 'freecell' : 'freecell-cells$freecellCount';
```

Delete the old `static const int firstFreecell = 0; static const int freecellCount = 4; static const int firstFoundation = 4; static const int firstTableau = 8;` block and the old `String get id => 'freecell';`. Leave `deal`, `isLegalMove`, `isWon`, `autoTargets`, and `maxMovable` bodies unchanged — they already reference `freecellCount`, `firstFoundation`, `firstTableau`, `foundationCount`, `tableauCount`, which now resolve to the field/getters.

- [ ] **Step 4: Update the 3 static references in the existing test**

In `test/unit/freecell_test.dart`, the `FreeCell deal` group uses a shared `final FreecellRules rules = FreecellRules();`. Change:
- line ~33: `FreecellRules.firstTableau + i` → `rules.firstTableau + i`
- line ~39: `FreecellRules.firstTableau + i` → `rules.firstTableau + i`
- line ~45: `FreecellRules.firstFoundation + i` → `rules.firstFoundation + i`

Leave line ~44 (`FreecellRules.firstFreecell + i`) unchanged — `firstFreecell` is still static.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/unit/freecell_test.dart`
Expected: PASS (old and new groups).

- [ ] **Step 6: Commit**

```bash
git add lib/core/games/freecell.dart test/unit/freecell_test.dart
git commit -m "feat: add FreeCell cell-count param (2/6-cell variants)"
```

---

### Task 2: Register the two new FreeCell variants

**Model:** Sonnet (mechanical).

**Files:**
- Modify: `lib/core/game_registry.dart`
- Test: `test/unit/game_registry_test.dart`

**Interfaces:**
- Consumes: `FreecellRules({int freecellCount})` from Task 1.
- Produces: `GameRegistry.freecellCells2 = 'freecell-cells2'`, `GameRegistry.freecellCells6 = 'freecell-cells6'`; `GameRegistry.ids` = the five ids in order; `rulesFor` maps the two new ids to `FreecellRules(freecellCount: 2 | 6)`.

- [ ] **Step 1: Write the failing tests**

In `test/unit/game_registry_test.dart`, replace the `lists exactly the three v1 variants` test body and add a mapping test:

```dart
test('lists exactly the five variants in menu order', () {
  expect(GameRegistry.ids, <String>[
    'klondike-draw1',
    'klondike-draw3',
    'freecell',
    'freecell-cells2',
    'freecell-cells6',
  ]);
});

test('maps the FreeCell cell-count variants', () {
  expect(
    (GameRegistry.rulesFor('freecell-cells2') as FreecellRules).freecellCount,
    2,
  );
  expect(
    (GameRegistry.rulesFor('freecell-cells6') as FreecellRules).freecellCount,
    6,
  );
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/game_registry_test.dart`
Expected: FAIL — list has 3 entries; `rulesFor('freecell-cells2')` throws ArgumentError.

- [ ] **Step 3: Add constants, ids, and rules cases**

In `lib/core/game_registry.dart` add the constants after `freecell`:

```dart
static const String freecellCells2 = 'freecell-cells2';
static const String freecellCells6 = 'freecell-cells6';
```

Extend `ids`:

```dart
static const List<String> ids = <String>[
  klondikeDraw1,
  klondikeDraw3,
  freecell,
  freecellCells2,
  freecellCells6,
];
```

Add cases in `rulesFor` before `default`:

```dart
case freecellCells2:
  return FreecellRules(freecellCount: 2);
case freecellCells6:
  return FreecellRules(freecellCount: 6);
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/game_registry_test.dart`
Expected: PASS. (The existing `rules.id == registry id` loop passes because Task 1 makes the ids match.)

- [ ] **Step 5: Commit**

```bash
git add lib/core/game_registry.dart test/unit/game_registry_test.dart
git commit -m "feat: register freecell-cells2 and freecell-cells6 variants"
```

---

### Task 3: `GameCatalog` — group variants under games

**Model:** Sonnet (mechanical).

**Files:**
- Create: `lib/core/game_catalog.dart`
- Test: `test/unit/game_catalog_test.dart`

**Interfaces:**
- Consumes: `GameRegistry` constants and `ids` from Task 2.
- Produces: `class Game { const Game({required String id, required List<String> variantIds}); final String id; final List<String> variantIds; }`; `GameCatalog.klondike = 'klondike'`, `GameCatalog.freecell = 'freecell'`; `static const List<Game> games`; `static Game gameForVariant(String variantId)` (throws ArgumentError on unknown).

- [ ] **Step 1: Write the failing tests**

Create `test/unit/game_catalog_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/game_catalog.dart';
import 'package:open_patience/core/game_registry.dart';

void main() {
  group('GameCatalog', () {
    test('groups variants under two games in menu order', () {
      expect(
        GameCatalog.games.map((Game g) => g.id).toList(),
        <String>['klondike', 'freecell'],
      );
      final Game klondike =
          GameCatalog.games.firstWhere((Game g) => g.id == 'klondike');
      expect(klondike.variantIds, <String>['klondike-draw1', 'klondike-draw3']);
      final Game freecell =
          GameCatalog.games.firstWhere((Game g) => g.id == 'freecell');
      expect(
        freecell.variantIds,
        <String>['freecell', 'freecell-cells2', 'freecell-cells6'],
      );
    });

    test('gameForVariant returns the owning game', () {
      expect(GameCatalog.gameForVariant('klondike-draw3').id, 'klondike');
      expect(GameCatalog.gameForVariant('freecell-cells2').id, 'freecell');
    });

    test('gameForVariant throws for an unknown variant', () {
      expect(() => GameCatalog.gameForVariant('spider'), throwsArgumentError);
    });

    test('catalog and registry cover exactly the same variant ids', () {
      final Set<String> catalogIds = <String>{
        for (final Game g in GameCatalog.games) ...g.variantIds,
      };
      expect(catalogIds, GameRegistry.ids.toSet());
      for (final String id in catalogIds) {
        expect(GameRegistry.rulesFor(id).id, id);
      }
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/game_catalog_test.dart`
Expected: FAIL — `game_catalog.dart` / `Game` / `GameCatalog` do not exist.

- [ ] **Step 3: Create the catalog (pure Dart, no Flutter import)**

Create `lib/core/game_catalog.dart`:

```dart
import 'game_registry.dart';

/// A game and the ordered list of variant ids it offers. The grouping layer
/// above the flat variant ids: the menu shows games, each game a list of
/// variants. Labels live in the UI; this file holds structure only.
class Game {
  const Game({required this.id, required this.variantIds});

  final String id;
  final List<String> variantIds;
}

/// Maps each game to its variants (menu order) and back. Every variant id here
/// must resolve in [GameRegistry]; a drift guard test enforces the two agree.
class GameCatalog {
  const GameCatalog._();

  static const String klondike = 'klondike';
  static const String freecell = 'freecell';

  static const List<Game> games = <Game>[
    Game(
      id: klondike,
      variantIds: <String>[
        GameRegistry.klondikeDraw1,
        GameRegistry.klondikeDraw3,
      ],
    ),
    Game(
      id: freecell,
      variantIds: <String>[
        GameRegistry.freecell,
        GameRegistry.freecellCells2,
        GameRegistry.freecellCells6,
      ],
    ),
  ];

  /// The game that offers [variantId]. Throws [ArgumentError] for an unknown id.
  static Game gameForVariant(String variantId) {
    for (final Game game in games) {
      if (game.variantIds.contains(variantId)) {
        return game;
      }
    }
    throw ArgumentError.value(variantId, 'variantId', 'Unknown variant');
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/game_catalog_test.dart`
Expected: PASS.

- [ ] **Step 5: Verify the import boundary holds**

Run: `! grep -rl "package:flutter" lib/core lib/persistence`
Expected: exit status 0 (no matches — command prints nothing).

- [ ] **Step 6: Commit**

```bash
git add lib/core/game_catalog.dart test/unit/game_catalog_test.dart
git commit -m "feat: add GameCatalog grouping variants under games"
```

---

### Task 4: `loadAllSaves()` — enumerate in-progress games

**Model:** Sonnet (mechanical).

**Files:**
- Modify: `lib/persistence/records_repository.dart` (interface)
- Modify: `lib/persistence/shared_prefs_records_repository.dart` (impl)
- Test: `test/unit/persistence_test.dart`

**Interfaces:**
- Consumes: existing `SavedGame`, `GameState.fromJson`, `savePrefix`.
- Produces: `Future<List<SavedGame>> loadAllSaves();` on `RecordsRepository`, implemented in `SharedPrefsRecordsRepository`.

- [ ] **Step 1: Write the failing tests**

Add to `test/unit/persistence_test.dart` (imports for `GameRegistry`, `GameState`, `SavedGame` already present):

```dart
group('SharedPrefsRecordsRepository loadAllSaves', () {
  test('returns every saved game and skips corrupt blobs', () async {
    final GameState k =
        GameState.newGame(GameRegistry.rulesFor('klondike-draw1'), seed: 11);
    final GameState f =
        GameState.newGame(GameRegistry.rulesFor('freecell'), seed: 22);
    await repo.saveGame(variant: 'klondike-draw1', seed: 11, state: k);
    await repo.saveGame(variant: 'freecell', seed: 22, state: f);
    await prefs.setString('save:corrupt', 'not json');

    final List<SavedGame> all = await repo.loadAllSaves();
    final Map<String, SavedGame> byVariant = <String, SavedGame>{
      for (final SavedGame s in all) s.variant: s,
    };
    expect(byVariant.keys.toSet(), <String>{'klondike-draw1', 'freecell'});
    expect(byVariant['klondike-draw1']!.seed, 11);
    expect(byVariant['freecell']!.seed, 22);
  });

  test('returns empty when there are no saves', () async {
    expect(await repo.loadAllSaves(), isEmpty);
  });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/persistence_test.dart`
Expected: FAIL — `loadAllSaves` is not defined.

- [ ] **Step 3: Add the interface method**

In `lib/persistence/records_repository.dart`, add to the `RecordsRepository` abstract class:

```dart
/// Every in-progress save across all variants. Corrupt entries are skipped.
Future<List<SavedGame>> loadAllSaves();
```

- [ ] **Step 4: Implement it in the shared-prefs repository**

In `lib/persistence/shared_prefs_records_repository.dart`, add:

```dart
@override
Future<List<SavedGame>> loadAllSaves() async {
  final List<SavedGame> saves = <SavedGame>[];
  for (final String key in _prefs.getKeys()) {
    if (!key.startsWith(savePrefix)) {
      continue;
    }
    final String? raw = _prefs.getString(key);
    if (raw == null) {
      continue;
    }
    try {
      final Map<String, dynamic> blob = jsonDecode(raw) as Map<String, dynamic>;
      saves.add(
        SavedGame(
          variant: blob['variant'] as String,
          seed: blob['seed'] as int,
          state: GameState.fromJson(blob['state'] as Map<String, dynamic>),
        ),
      );
    } on Object {
      continue;
    }
  }
  return saves;
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/unit/persistence_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/persistence/records_repository.dart lib/persistence/shared_prefs_records_repository.dart test/unit/persistence_test.dart
git commit -m "feat: add RecordsRepository.loadAllSaves for the resume list"
```

---

### Task 5: UI labels for games and variants

**Model:** Sonnet (mechanical).

**Files:**
- Modify: `lib/ui/variant_labels.dart`
- Test: `test/unit/variant_labels_test.dart` (create)

**Interfaces:**
- Consumes: `GameRegistry` constants, `GameCatalog` game-id constants.
- Produces: `String variantTitle(String id)` (extended); `String gameTitle(String gameId)`; `String variantShortLabel(String id)`; `String variantDescriptor(String id)`.

- [ ] **Step 1: Write the failing tests**

Create `test/unit/variant_labels_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/variant_labels.dart';

void main() {
  test('variantTitle covers all five variants', () {
    expect(variantTitle('klondike-draw1'), 'Klondike (Draw 1)');
    expect(variantTitle('klondike-draw3'), 'Klondike (Draw 3)');
    expect(variantTitle('freecell'), 'FreeCell');
    expect(variantTitle('freecell-cells2'), 'FreeCell (2 cells)');
    expect(variantTitle('freecell-cells6'), 'FreeCell (6 cells)');
  });

  test('gameTitle names each game', () {
    expect(gameTitle('klondike'), 'Klondike');
    expect(gameTitle('freecell'), 'FreeCell');
  });

  test('variantShortLabel and descriptor are defined per variant', () {
    expect(variantShortLabel('klondike-draw1'), 'Draw 1');
    expect(variantShortLabel('freecell'), 'Classic · 4 cells');
    expect(variantShortLabel('freecell-cells2'), '2 cells · hard');
    expect(variantShortLabel('freecell-cells6'), '6 cells · relaxed');
    expect(variantDescriptor('freecell'), isNotEmpty);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/unit/variant_labels_test.dart`
Expected: FAIL — `gameTitle` / `variantShortLabel` / `variantDescriptor` not defined; `variantTitle('freecell-cells2')` returns the raw id.

- [ ] **Step 3: Extend the label functions**

Replace the contents of `lib/ui/variant_labels.dart`:

```dart
import '../core/game_catalog.dart';
import '../core/game_registry.dart';

/// A human-readable full title for a variant id (headers, records, resume rows).
String variantTitle(String id) {
  switch (id) {
    case GameRegistry.klondikeDraw1:
      return 'Klondike (Draw 1)';
    case GameRegistry.klondikeDraw3:
      return 'Klondike (Draw 3)';
    case GameRegistry.freecell:
      return 'FreeCell';
    case GameRegistry.freecellCells2:
      return 'FreeCell (2 cells)';
    case GameRegistry.freecellCells6:
      return 'FreeCell (6 cells)';
    default:
      return id;
  }
}

/// The display name of a game (title screen and options header).
String gameTitle(String gameId) {
  switch (gameId) {
    case GameCatalog.klondike:
      return 'Klondike';
    case GameCatalog.freecell:
      return 'FreeCell';
    default:
      return gameId;
  }
}

/// A short label for a variant row on a game's options page.
String variantShortLabel(String id) {
  switch (id) {
    case GameRegistry.klondikeDraw1:
      return 'Draw 1';
    case GameRegistry.klondikeDraw3:
      return 'Draw 3';
    case GameRegistry.freecell:
      return 'Classic · 4 cells';
    case GameRegistry.freecellCells2:
      return '2 cells · hard';
    case GameRegistry.freecellCells6:
      return '6 cells · relaxed';
    default:
      return id;
  }
}

/// A one-line descriptor under a variant's short label.
String variantDescriptor(String id) {
  switch (id) {
    case GameRegistry.klondikeDraw1:
      return 'Turn one card at a time';
    case GameRegistry.klondikeDraw3:
      return 'Turn three at a time';
    case GameRegistry.freecell:
      return 'Standard FreeCell';
    case GameRegistry.freecellCells2:
      return 'Fewer cells, tighter play';
    case GameRegistry.freecellCells6:
      return 'Extra room, easier';
    default:
      return '';
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/unit/variant_labels_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/variant_labels.dart test/unit/variant_labels_test.dart
git commit -m "feat: add game/variant labels and descriptors"
```

---

### Task 6: `MenuWidthLimit` — cap menu width on tablets

**Model:** Sonnet (mechanical).

**Files:**
- Modify: `lib/ui/theme/widgets.dart`
- Test: `test/widget/menu_width_limit_test.dart` (create)

**Interfaces:**
- Produces: `class MenuWidthLimit extends StatelessWidget { const MenuWidthLimit({required Widget child, double maxWidth = 520, Key? key}); }` — centers and width-caps its child.

- [ ] **Step 1: Write the failing test**

Create `test/widget/menu_width_limit_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/theme/widgets.dart';

void main() {
  testWidgets('MenuWidthLimit caps its child width', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MenuWidthLimit(
            child: SizedBox(
              key: Key('child'),
              height: 10,
              width: double.infinity,
            ),
          ),
        ),
      ),
    );
    final Size size = tester.getSize(find.byKey(const Key('child')));
    expect(size.width, lessThanOrEqualTo(520));
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widget/menu_width_limit_test.dart`
Expected: FAIL — `MenuWidthLimit` is not defined.

- [ ] **Step 3: Add the widget**

Append to `lib/ui/theme/widgets.dart`:

```dart
/// Centres menu content and caps its width so the menu never stretches
/// uncomfortably wide on tablets; the felt fills the margins.
class MenuWidthLimit extends StatelessWidget {
  const MenuWidthLimit({required this.child, this.maxWidth = 520, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widget/menu_width_limit_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/theme/widgets.dart test/widget/menu_width_limit_test.dart
git commit -m "feat: add MenuWidthLimit for tablet menu width"
```

---

### Task 7: `GameOptionsScreen` — a game's variant list

**Model:** default (Opus) — UI composition.

**Files:**
- Create: `lib/ui/game_options_screen.dart`
- Test: `test/widget/game_options_test.dart` (create)

**Interfaces:**
- Consumes: `GameCatalog.games`, `gameTitle`, `variantShortLabel`, `variantDescriptor`, `variantTitle`, `MenuWidthLimit`, `FeltBackground`/`FeltHeader` (theme/widgets), `GameBloc.newGame`, `GameBloc(...)`, `RecordsRepository.hasSave`/`loadGame`, `GameScreen`, `RecordsScreen`.
- Produces: `class GameOptionsScreen extends StatelessWidget { const GameOptionsScreen({required String gameId, required RecordsRepository repository, Duration? autoTick, Key? key}); }`.

- [ ] **Step 1: Write the failing tests**

Create `test/widget/game_options_test.dart`:

```dart
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/game_registry.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/presentation/board.dart';
import 'package:open_patience/ui/game_options_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<RecordsRepository> _repo() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return SharedPrefsRecordsRepository(prefs);
}

Widget _host(Widget child) => MediaQuery(
  data: const MediaQueryData(disableAnimations: true),
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('lists a game\'s variants and plays one', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(
      _host(GameOptionsScreen(gameId: 'freecell', repository: repo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Classic · 4 cells'), findsOneWidget);
    expect(find.text('2 cells · hard'), findsOneWidget);
    expect(find.text('6 cells · relaxed'), findsOneWidget);

    await tester.tap(find.text('Play').first);
    await tester.pumpAndSettle();
    expect(find.byType(Board), findsOneWidget);
  });

  testWidgets('Resume appears only for a variant with a save', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await repo.saveGame(
      variant: 'klondike-draw1',
      seed: 1,
      state: GameState.newGame(GameRegistry.rulesFor('klondike-draw1'), seed: 1),
    );
    await tester.pumpWidget(
      _host(GameOptionsScreen(gameId: 'klondike', repository: repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('Records opens the records screen for the variant', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(
      _host(GameOptionsScreen(gameId: 'freecell', repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Records').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Records'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/widget/game_options_test.dart`
Expected: FAIL — `game_options_screen.dart` / `GameOptionsScreen` do not exist.

- [ ] **Step 3: Create the screen**

Create `lib/ui/game_options_screen.dart`. Model the New game / Resume / Records logic on the current `_VariantCard` in `main_menu_screen.dart`. Skeleton:

```dart
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/game_catalog.dart';
import '../persistence/records_repository.dart';
import '../presentation/bloc/game_bloc.dart';
import 'game_screen.dart';
import 'records_screen.dart';
import 'theme/widgets.dart';
import 'variant_labels.dart';

/// The per-game page: one row per variant, each with Play (new deal), Resume
/// (when a save exists) and Records. Holds no game logic — it constructs a
/// [GameBloc] and pushes a [GameScreen], exactly like the old menu cards did.
class GameOptionsScreen extends StatelessWidget {
  const GameOptionsScreen({
    required this.gameId,
    required this.repository,
    this.autoTick,
    super.key,
  });

  final String gameId;
  final RecordsRepository repository;
  final Duration? autoTick;

  void _open(BuildContext context, GameBloc bloc) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => BlocProvider<GameBloc>(
          create: (BuildContext context) => bloc,
          child: GameScreen(autoTick: autoTick),
        ),
      ),
    );
  }

  void _play(BuildContext context, String variant) {
    final int seed = Random().nextInt(1 << 32);
    _open(
      context,
      GameBloc.newGame(variant: variant, repository: repository, seed: seed),
    );
  }

  Future<void> _resume(BuildContext context, String variant) async {
    final SavedGame? saved = await repository.loadGame(variant);
    if (!context.mounted) {
      return;
    }
    if (saved == null) {
      _play(context, variant);
      return;
    }
    _open(
      context,
      GameBloc(
        variant: variant,
        repository: repository,
        seed: saved.seed,
        state: saved.state,
      ),
    );
  }

  void _openRecords(BuildContext context, String variant) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RecordsScreen(
          repository: repository,
          variant: variant,
          title: variantTitle(variant),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Game game =
        GameCatalog.games.firstWhere((Game g) => g.id == gameId);
    return Scaffold(
      body: FeltBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FeltHeader(
                title: gameTitle(gameId),
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: MenuWidthLimit(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      for (final String variant in game.variantIds)
                        _VariantRow(
                          variant: variant,
                          hasSave: repository.hasSave(variant),
                          onPlay: () => _play(context, variant),
                          onResume: () => _resume(context, variant),
                          onRecords: () => _openRecords(context, variant),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VariantRow extends StatelessWidget {
  const _VariantRow({
    required this.variant,
    required this.hasSave,
    required this.onPlay,
    required this.onResume,
    required this.onRecords,
  });

  final String variant;
  final Future<bool> hasSave;
  final VoidCallback onPlay;
  final VoidCallback onResume;
  final VoidCallback onRecords;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              variantShortLabel(variant),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(variantDescriptor(variant)),
            const SizedBox(height: 12),
            FutureBuilder<bool>(
              future: hasSave,
              builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
                final bool saved = snapshot.data ?? false;
                return Wrap(
                  spacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play'),
                    ),
                    if (saved)
                      OutlinedButton.icon(
                        onPressed: onResume,
                        icon: const Icon(Icons.restore),
                        label: const Text('Resume'),
                      ),
                    TextButton.icon(
                      onPressed: onRecords,
                      icon: const Icon(Icons.leaderboard),
                      label: const Text('Records'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
```

Verify `FeltHeader`'s parameter names (`title`, `onBack`) against `lib/ui/theme/widgets.dart` and adjust if they differ. If `GameScreen`'s constructor differs from `GameScreen(autoTick: autoTick)`, match its real signature (see `lib/ui/game_screen.dart`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/widget/game_options_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/game_options_screen.dart test/widget/game_options_test.dart
git commit -m "feat: add GameOptionsScreen listing a game's variants"
```

---

### Task 8: Rewrite `MainMenuScreen` — games list + Continue section

**Model:** default (Opus) — UI composition.

**Files:**
- Modify: `lib/ui/main_menu_screen.dart` (rewrite body; remove `_VariantCard`)
- Modify: `test/widget/main_menu_test.dart` (rewrite for the new structure)

**Interfaces:**
- Consumes: `GameCatalog.games`, `GameCatalog.gameForVariant`, `gameTitle`, `variantTitle`, `MenuWidthLimit`, `RecordsRepository.loadAllSaves`, `GameOptionsScreen`, `GameBloc`, `GameScreen`, `formatDuration` (theme/game_palette), `SavedGame` (`state.elapsedSeconds`, `state.moveCount`).
- Produces: `MainMenuScreen` unchanged constructor (`{required RecordsRepository repository, Duration? autoTick, Key? key}`) with the new two-level body.

- [ ] **Step 1: Rewrite the widget tests (RED)**

Replace `test/widget/main_menu_test.dart` with:

```dart
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/game_registry.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/presentation/board.dart';
import 'package:open_patience/ui/main_menu_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<RecordsRepository> _repo() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return SharedPrefsRecordsRepository(prefs);
}

Widget _host(Widget child) => MediaQuery(
  data: const MediaQueryData(disableAnimations: true),
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('lists the games and opens a game\'s options', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(_host(MainMenuScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('Klondike'), findsOneWidget);
    expect(find.text('FreeCell'), findsOneWidget);
    // The title screen no longer shows per-variant rows.
    expect(find.text('Draw 1'), findsNothing);

    await tester.tap(find.text('Klondike'));
    await tester.pumpAndSettle();
    expect(find.text('Draw 1'), findsOneWidget);
  });

  testWidgets('an in-progress game appears in Continue and resumes', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await repo.saveGame(
      variant: 'freecell',
      seed: 9,
      state: GameState.newGame(GameRegistry.rulesFor('freecell'), seed: 9),
    );
    await tester.pumpWidget(_host(MainMenuScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('Continue playing'), findsOneWidget);
    await tester.tap(find.text('Resume').first);
    await tester.pumpAndSettle();
    expect(find.byType(Board), findsOneWidget);
  });

  testWidgets('no Continue section when nothing is in progress', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(_host(MainMenuScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('Continue playing'), findsNothing);
  });

  testWidgets('shows the handwritten signature footer', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(_host(MainMenuScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('a game by Dirk Wilden'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/widget/main_menu_test.dart`
Expected: FAIL — old menu shows `Klondike (Draw 1)` and `New game`, not `Klondike` game rows / `Continue playing`.

- [ ] **Step 3: Rewrite the menu body**

Rewrite `lib/ui/main_menu_screen.dart`. Remove `_VariantCard` (its logic now lives in `GameOptionsScreen`). New structure:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/game_catalog.dart';
import '../persistence/records_repository.dart';
import '../presentation/bloc/game_bloc.dart';
import 'game_options_screen.dart';
import 'game_screen.dart';
import 'theme/game_palette.dart';
import 'theme/widgets.dart';
import 'variant_labels.dart';
import 'widgets/menu_banner.dart';

/// The entry screen: a Continue section (every in-progress deal, one-tap
/// resume) above the list of games. Selecting a game opens its options page.
/// The menu holds no game logic.
class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({required this.repository, this.autoTick, super.key});

  final RecordsRepository repository;
  final Duration? autoTick;

  void _openGame(BuildContext context, String gameId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GameOptionsScreen(
          gameId: gameId,
          repository: repository,
          autoTick: autoTick,
        ),
      ),
    );
  }

  void _resume(BuildContext context, SavedGame saved) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => BlocProvider<GameBloc>(
          create: (BuildContext context) => GameBloc(
            variant: saved.variant,
            repository: repository,
            seed: saved.seed,
            state: saved.state,
          ),
          child: GameScreen(autoTick: autoTick),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FeltBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const MenuBanner(),
              const GameWordmark(),
              Expanded(
                child: MenuWidthLimit(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      _ContinueSection(
                        repository: repository,
                        onResume: (SavedGame s) => _resume(context, s),
                      ),
                      for (final Game game in GameCatalog.games)
                        Card(
                          child: ListTile(
                            title: Text(gameTitle(game.id)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openGame(context, game.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const GameSignature(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueSection extends StatelessWidget {
  const _ContinueSection({required this.repository, required this.onResume});

  final RecordsRepository repository;
  final void Function(SavedGame) onResume;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SavedGame>>(
      future: repository.loadAllSaves(),
      builder: (BuildContext context, AsyncSnapshot<List<SavedGame>> snapshot) {
        final List<SavedGame> saves = snapshot.data ?? const <SavedGame>[];
        if (saves.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Continue playing',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final SavedGame saved in saves)
              Card(
                child: ListTile(
                  title: Text(variantTitle(saved.variant)),
                  subtitle: Text(
                    '${formatDuration(saved.state.elapsedSeconds)} · '
                    '${saved.state.moveCount} moves',
                  ),
                  trailing: TextButton.icon(
                    onPressed: () => onResume(saved),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Resume'),
                  ),
                  onTap: () => onResume(saved),
                ),
              ),
            const SizedBox(height: 8),
            Text('Games', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}
```

Verify `GameState` exposes `elapsedSeconds` and `moveCount` (used by `GameBloc`; confirm in `lib/core/game_state.dart`) and that `formatDuration` is exported from `lib/ui/theme/game_palette.dart`. Adjust the `import` for `SavedGame` if it is not already reachable via `records_repository.dart`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/widget/main_menu_test.dart`
Expected: PASS.

- [ ] **Step 5: Full suite + analyze + format + boundary check**

Run:
```bash
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test
! grep -rl "package:flutter" lib/core lib/persistence
```
Expected: analyze clean, format clean, all tests green, grep prints nothing (exit 0).

- [ ] **Step 6: Commit**

```bash
git add lib/ui/main_menu_screen.dart test/widget/main_menu_test.dart
git commit -m "feat: two-level main menu with games list and Continue section"
```

---

## Self-Review

**Spec coverage:**
- Title lists games → Task 8. ✓
- In-progress games visible + one-tap resume (all of them) → Task 4 (`loadAllSaves`) + Task 8 (Continue section). ✓
- Per-game options page (Play/Resume/Records) → Task 7. ✓
- Tablet centered max-width column → Task 6 + applied in Tasks 7 & 8. ✓
- Records per variant, reachable per variant, no schema change → Task 7 (Records button) + existing `RecordsScreen`; no `Stats` change. ✓
- Two FreeCell cell-count variants → Tasks 1 & 2; catalog exposes them → Task 3; labels → Task 5. ✓
- Core stays Flutter-free → verified in Tasks 3 & 8 (grep). ✓

**Placeholder scan:** No TBD/TODO; every code step has concrete code. ✓

**Type consistency:** `freecellCount` (Tasks 1/2), `Game`/`variantIds`/`gameForVariant` (Task 3 → used in 7/8), `loadAllSaves` returns `List<SavedGame>` (Task 4 → used in 8), label fn names `gameTitle`/`variantShortLabel`/`variantDescriptor`/`variantTitle` (Task 5 → used in 7/8), `MenuWidthLimit` (Task 6 → used in 7/8), `GameOptionsScreen(gameId, repository, autoTick)` (Task 7 → used in 8). Consistent. ✓

**Known verification points flagged inline for the implementer:** `FeltHeader` param names, `GameScreen` constructor, `GameState.elapsedSeconds`/`moveCount`, `formatDuration` export location — each task tells the implementer to confirm against the real file and adjust.
