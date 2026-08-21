# Card Move Animations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Animate card movement (tap/double-tap moves, drop-settle, stock→waste draw+flip, deal, win) by rendering the board as one positioned `Stack` of keyed `AnimatedPositioned` cards driven by a pure, unit-testable geometry function.

**Architecture:** A new pure-Dart `BoardGeometry` resolver computes every card's board-local `Rect` from `GameState` + available size (no runtime coordinate measurement). `Board` becomes a `StatefulWidget` that builds a single `Stack` of `AnimatedPositioned` `CardView`s keyed by `(suit, rank)`; when the bloc emits new state the cards interpolate to their new rects. Deal/win set-pieces sit behind a `SpecialSequence` seam so they can be swapped without touching the core. OS reduce-motion collapses every animation to an instant snap (today's behavior).

**Tech Stack:** Flutter (stable), Dart, `flutter_bloc`, `flutter_test`. Built-in `AnimatedPositioned`, `TweenAnimationBuilder`, `MediaQuery`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-08-21-card-move-animations-design.md`

## Global Constraints

- **No Flutter imports in `lib/core/` or `lib/persistence/`.** New geometry code lives in `lib/presentation/` — it may import `dart:ui`/`package:flutter` but must not leak rules. Game logic stays in `core/`. (CLAUDE.md rule 2.)
- **TDD mandatory:** every task is RED → GREEN → REFACTOR. No production code before a failing test. (CLAUDE.md rule 1.)
- **Explicit static types on all public APIs.** `var` only for locals with an unambiguous same-line type. No `dynamic`.
- **Style:** `dart format` (2-space indent, trailing commas on multi-line), lines < 100 chars, single quotes, `const` constructors wherever possible. Run `dart format` before every commit.
- **Motion tokens live in `lib/ui/theme/`.** No widget hardcodes a `Duration` or `Curve`.
- **Reduce-motion:** honor `MediaQuery.of(context).disableAnimations` only; no in-app toggle. When true, animations are `Duration.zero` (instant).
- **Regression gate:** the existing suite must stay green throughout. Run `flutter analyze && flutter test` before each commit. The `!grep -rl "package:flutter" lib/core lib/persistence` check must find nothing.
- **Card identity:** `(suit, rank)` uniquely identifies a card in a single deck; `faceUp` is NOT part of identity (it changes on flip).

---

### Task 1: Motion tokens

**Files:**
- Create: `lib/ui/theme/game_motion.dart`
- Test: `test/unit/game_motion_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `class GameMotion` with `static const Duration move, flip, draw, dealStagger`,
    `static const Curve moveCurve, flipCurve`, and
    `static Duration resolve(Duration base, {required bool reduceMotion})`.

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/game_motion_test.dart
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/theme/game_motion.dart';

void main() {
  test('resolve returns the base duration when motion is allowed', () {
    expect(
      GameMotion.resolve(GameMotion.move, reduceMotion: false),
      GameMotion.move,
    );
  });

  test('resolve collapses to zero when reduce-motion is on', () {
    expect(
      GameMotion.resolve(GameMotion.move, reduceMotion: true),
      Duration.zero,
    );
  });

  test('tokens are positive and curves are defined', () {
    expect(GameMotion.move.inMilliseconds, greaterThan(0));
    expect(GameMotion.flip.inMilliseconds, greaterThan(0));
    expect(GameMotion.draw.inMilliseconds, greaterThan(0));
    expect(GameMotion.dealStagger.inMilliseconds, greaterThan(0));
    expect(GameMotion.moveCurve, isA<Curve>());
    expect(GameMotion.flipCurve, isA<Curve>());
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/game_motion_test.dart`
Expected: FAIL — `game_motion.dart` / `GameMotion` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/theme/game_motion.dart
import 'package:flutter/animation.dart';

/// Motion tokens for card animations. All card-animation durations and curves
/// live here so no widget hardcodes them (per the design-language rule that
/// shared visual tokens live in `lib/ui/theme/`).
class GameMotion {
  const GameMotion._();

  /// A card gliding from one pile to another (tap / double-tap / drop-settle).
  static const Duration move = Duration(milliseconds: 220);

  /// A card turning face-down↔face-up.
  static const Duration flip = Duration(milliseconds: 260);

  /// A stock→waste draw slide.
  static const Duration draw = Duration(milliseconds: 200);

  /// Delay between successive cards in a staggered deal.
  static const Duration dealStagger = Duration(milliseconds: 40);

  static const Curve moveCurve = Curves.easeOutCubic;
  static const Curve flipCurve = Curves.easeInOut;

  /// The effective duration honoring the OS reduce-motion setting: [base] when
  /// motion is allowed, [Duration.zero] (instant snap) when [reduceMotion].
  static Duration resolve(Duration base, {required bool reduceMotion}) =>
      reduceMotion ? Duration.zero : base;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/game_motion_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
dart format lib/ui/theme/game_motion.dart test/unit/game_motion_test.dart
git add lib/ui/theme/game_motion.dart test/unit/game_motion_test.dart
git commit -m "feat: add card-animation motion tokens"
```

---

### Task 2: Geometry value types (`CardKey`, `CardPlacement`, `SlotPlacement`)

**Files:**
- Create: `lib/presentation/board_geometry.dart`
- Test: `test/unit/board_geometry_test.dart`

**Interfaces:**
- Consumes: `Card`, `Suit` (`core/card.dart`); `PileKind` (`core/pile.dart`).
- Produces:
  - `class CardKey { const CardKey(this.suit, this.rank); factory CardKey.of(Card); final Suit suit; final int rank; ValueKey<String> get widgetKey; }` with value equality.
  - `class CardPlacement { final Card card; final int pileIndex; final int indexInPile; final bool isTop; final Rect rect; CardKey get key; }`
  - `class SlotPlacement { final int pileIndex; final PileKind kind; final Rect rect; }`

- [ ] **Step 1: Write the failing test**

```dart
// test/unit/board_geometry_test.dart
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/presentation/board_geometry.dart';

void main() {
  group('CardKey', () {
    test('identity ignores faceUp and equals by suit+rank', () {
      const CardKey a = CardKey(Suit.hearts, 5);
      final CardKey b = CardKey.of(
        const Card(suit: Suit.hearts, rank: 5, faceUp: true),
      );
      final CardKey c = CardKey.of(
        const Card(suit: Suit.hearts, rank: 5, faceUp: false),
      );
      expect(b, a);
      expect(c, a);
      expect(<CardKey>{a, b, c}.length, 1);
    });

    test('widgetKey is stable and distinct per card', () {
      expect(
        const CardKey(Suit.spades, 13).widgetKey,
        const CardKey(Suit.spades, 13).widgetKey,
      );
      expect(
        const CardKey(Suit.spades, 13).widgetKey ==
            const CardKey(Suit.clubs, 13).widgetKey,
        isFalse,
      );
    });
  });

  test('CardPlacement.key derives from its card', () {
    const CardPlacement p = CardPlacement(
      card: Card(suit: Suit.clubs, rank: 2, faceUp: true),
      pileIndex: 3,
      indexInPile: 0,
      isTop: true,
      rect: Rect.fromLTWH(0, 0, 10, 14),
    );
    expect(p.key, const CardKey(Suit.clubs, 2));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/board_geometry_test.dart`
Expected: FAIL — `board_geometry.dart` not found.

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/presentation/board_geometry.dart
import 'dart:ui';

import 'package:flutter/widgets.dart';

import '../core/card.dart';
import '../core/pile.dart';

/// Stable identity of a card within a single 52-card deck: `(suit, rank)`,
/// ignoring `faceUp` (which changes on a flip). Used as the animation key so
/// `AnimatedPositioned` can recognise the same card across a move.
@immutable
class CardKey {
  const CardKey(this.suit, this.rank);

  factory CardKey.of(Card card) => CardKey(card.suit, card.rank);

  final Suit suit;
  final int rank;

  ValueKey<String> get widgetKey => ValueKey<String>('card-${suit.index}-$rank');

  @override
  bool operator ==(Object other) =>
      other is CardKey && other.suit == suit && other.rank == rank;

  @override
  int get hashCode => Object.hash(suit, rank);
}

/// One card placed on the board: the card, where it sits (pile + index within
/// the pile), whether it is the interactive top card, and the board-local rect
/// it occupies.
@immutable
class CardPlacement {
  const CardPlacement({
    required this.card,
    required this.pileIndex,
    required this.indexInPile,
    required this.isTop,
    required this.rect,
  });

  final Card card;
  final int pileIndex;
  final int indexInPile;
  final bool isTop;
  final Rect rect;

  CardKey get key => CardKey.of(card);
}

/// An empty pile's slot-marker rect (foundation / free-cell / stock / tableau).
@immutable
class SlotPlacement {
  const SlotPlacement({
    required this.pileIndex,
    required this.kind,
    required this.rect,
  });

  final int pileIndex;
  final PileKind kind;
  final Rect rect;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/board_geometry_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
dart format lib/presentation/board_geometry.dart test/unit/board_geometry_test.dart
git add lib/presentation/board_geometry.dart test/unit/board_geometry_test.dart
git commit -m "feat: add board geometry value types (CardKey, placements)"
```

---

### Task 3: `BoardGeometry.resolve` — stacked layouts (portrait / phone-landscape)

Port the stacked-layout arithmetic from `lib/presentation/board.dart`
(`_stackedLayout`, `_topRow`, `_tableauRow`, `_slot`, `_fanGap`) and
`lib/presentation/pile_view.dart` (`_fanned`, `_stacked`, `_wasteFan`) into pure
coordinate math. Board-local origin `(0,0)` is the top-left of the resolved
area. Cards use `BoardMetrics.resolve(...)` for size, exactly as the board does
today.

**Files:**
- Modify: `lib/presentation/board_geometry.dart`
- Test: `test/unit/board_geometry_test.dart`

**Interfaces:**
- Consumes: `BoardMetrics` (`board_metrics.dart`), `GameState` (`core/game_state.dart`), `PileKind`.
- Produces:
  - `class BoardGeometry { final BoardMetrics metrics; final List<CardPlacement> cards; final List<SlotPlacement> slots; final Map<int, Rect> dropTargets; Size get cardSize; }`
  - `static BoardGeometry resolve({required GameState game, required double width, required double height, required double shortestSide, required bool isLandscape, required int wasteVisibleCount})`
  - `cards` is in paint order: pile-major (stock/waste/freecell, then foundations, then tableau), each pile bottom-to-top.
  - `dropTargets[pileIndex]` covers the pile's card area (union of its card rects; the slot rect when empty).
  - `slots` holds one `SlotPlacement` per empty pile.

**Layout facts to reproduce (from `board.dart`):** `pad = BoardMetrics.pad` (6). Pile partition by kind: `upper` = stock/waste/freecell, `foundations`, `tableau` — in `game.piles` order. Top row is one card tall at `y = pad`; upper piles left-aligned from the left inner edge (each `cardW` wide, `pad` after); foundations right-aligned against the right inner edge (each preceded by `pad`). Tableau row starts at `y = pad + cardH + pad`; columns share the inner width equally, card centered in its column. Face-up fan gap = `_fanGap` (below); face-down gap = half that. Waste fans its last `wasteVisibleCount` cards horizontally at step `cardW * 0.16`, plus one backing card at the oldest-visible position when older draws remain (see `pile_view.dart:241-267`). Phone-landscape centers the content: inner content width = `cardW*cols + pad*(cols-1)`, left inset = `(width - (cardW*cols + pad*(cols+1)))/2 + pad`.

`_fanGap` (from `board.dart:237-253`), with `bottomHeight = (height - 2*pad) - cardH - pad` for stacked layouts:

```dart
double _fanGap(GameState game, List<int> tableau, double cardH, double bottomH) {
  final double defaultGap = cardH * 0.30;
  int maxLen = 1;
  for (final int i in tableau) {
    maxLen = maxLen > game.pileAt(i).length ? maxLen : game.pileAt(i).length;
  }
  if (maxLen <= 1) return defaultGap;
  final double fitGap = (bottomH - cardH) / (maxLen - 1);
  return math.max(cardH * 0.06, math.min(defaultGap, fitGap));
}
```

- [ ] **Step 1: Write the failing tests**

```dart
// add to test/unit/board_geometry_test.dart
import 'package:open_patience/core/game_state.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

GameState _klondike() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock, cards: <Card>[
      const Card(suit: Suit.clubs, rank: 9),
    ]),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation, cards: <Card>[_up(Suit.clubs, aceRank)]),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, 5)]),
    Pile(kind: PileKind.tableau, cards: <Card>[
      for (int r = kingRank; r >= 1; r--) _up(Suit.hearts, r),
    ]),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.diamonds, kingRank)]),
  ],
);

Rect _rectOf(BoardGeometry g, Suit s, int r) =>
    g.cards.firstWhere((CardPlacement p) => p.key == CardKey(s, r)).rect;

void main() {
  // ... (keep the Task 2 groups) ...

  group('stacked geometry (portrait)', () {
    late BoardGeometry g;
    setUp(() {
      g = BoardGeometry.resolve(
        game: _klondike(),
        width: 400,
        height: 800,
        shortestSide: 400,
        isLandscape: false,
        wasteVisibleCount: 1,
      );
    });

    test('layout is portrait', () {
      expect(g.metrics.layout, BoardLayout.portrait);
    });

    test('foundations sit above the tableau', () {
      expect(
        _rectOf(g, Suit.clubs, aceRank).center.dy,
        lessThan(_rectOf(g, Suit.spades, 5).center.dy),
      );
    });

    test('every card fits inside the viewport height', () {
      for (final CardPlacement p in g.cards) {
        expect(p.rect.bottom, lessThanOrEqualTo(800 + 0.5));
        expect(p.rect.top, greaterThanOrEqualTo(-0.5));
      }
    });

    test('the longest fan descends within the viewport', () {
      expect(
        _rectOf(g, Suit.hearts, aceRank).bottom,
        lessThanOrEqualTo(800 + 0.5),
      );
      // Fanned: each deeper card is lower than the one above it.
      expect(
        _rectOf(g, Suit.hearts, aceRank).top,
        greaterThan(_rectOf(g, Suit.hearts, kingRank).top),
      );
    });

    test('empty piles produce slot placements, filled piles do not', () {
      final Set<int> slotPiles =
          g.slots.map((SlotPlacement s) => s.pileIndex).toSet();
      expect(slotPiles.contains(3), isTrue); // empty foundation
      expect(slotPiles.contains(2), isFalse); // foundation with the ace
    });

    test('each pile has a drop-target rect covering its cards', () {
      expect(g.dropTargets.containsKey(7), isTrue);
      final Rect dt = g.dropTargets[7]!;
      expect(dt.contains(_rectOf(g, Suit.hearts, kingRank).center), isTrue);
      expect(dt.contains(_rectOf(g, Suit.hearts, aceRank).center), isTrue);
    });
  });

  group('stacked geometry (phone landscape)', () {
    test('fit-to-height: nothing overflows the short edge', () {
      final BoardGeometry g = BoardGeometry.resolve(
        game: _klondike(),
        width: 800,
        height: 360,
        shortestSide: 360,
        isLandscape: true,
        wasteVisibleCount: 1,
      );
      expect(g.metrics.layout, BoardLayout.phoneLandscape);
      for (final CardPlacement p in g.cards) {
        expect(p.rect.bottom, lessThanOrEqualTo(360 + 0.5));
      }
    });
  });

  group('waste fan', () {
    test('draw-3 waste fans the last three cards left-to-right', () {
      final GameState g3 = GameState(
        piles: <Pile>[
          Pile(kind: PileKind.stock),
          Pile(kind: PileKind.waste, cards: <Card>[
            _up(Suit.clubs, 2),
            _up(Suit.clubs, 3),
            _up(Suit.clubs, 4),
          ]),
          Pile(kind: PileKind.foundation),
          Pile(kind: PileKind.foundation),
          Pile(kind: PileKind.foundation),
          Pile(kind: PileKind.foundation),
          for (int i = 0; i < 7; i++) Pile(kind: PileKind.tableau),
        ],
      );
      final BoardGeometry g = BoardGeometry.resolve(
        game: g3,
        width: 400,
        height: 800,
        shortestSide: 400,
        isLandscape: false,
        wasteVisibleCount: 3,
      );
      final double x2 = _rectOf(g, Suit.clubs, 2).left;
      final double x3 = _rectOf(g, Suit.clubs, 3).left;
      final double x4 = _rectOf(g, Suit.clubs, 4).left;
      expect(x3, greaterThan(x2));
      expect(x4, greaterThan(x3));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/board_geometry_test.dart`
Expected: FAIL — `BoardGeometry.resolve` / `BoardLayout` not found (import `board_metrics.dart` in the geometry file for `BoardMetrics`/`BoardLayout`).

- [ ] **Step 3: Write the implementation**

Add to `lib/presentation/board_geometry.dart` (add imports `import 'dart:math' as math;`, `import '../core/game_state.dart';`, `import 'board_metrics.dart';`, and re-export the layout enum by importing it):

```dart
class BoardGeometry {
  const BoardGeometry({
    required this.metrics,
    required this.cards,
    required this.slots,
    required this.dropTargets,
  });

  final BoardMetrics metrics;
  final List<CardPlacement> cards;
  final List<SlotPlacement> slots;
  final Map<int, Rect> dropTargets;

  Size get cardSize => metrics.cardSize;

  static const double _wasteStep = 0.16; // matches PileView._wasteFanStep

  static BoardGeometry resolve({
    required GameState game,
    required double width,
    required double height,
    required double shortestSide,
    required bool isLandscape,
    required int wasteVisibleCount,
  }) {
    final List<int> upper = <int>[];
    final List<int> foundations = <int>[];
    final List<int> tableau = <int>[];
    for (int i = 0; i < game.piles.length; i++) {
      switch (game.pileAt(i).kind) {
        case PileKind.stock:
        case PileKind.waste:
        case PileKind.freecell:
          upper.add(i);
        case PileKind.foundation:
          foundations.add(i);
        case PileKind.tableau:
          tableau.add(i);
      }
    }

    int maxPileLength = 1;
    for (final int i in tableau) {
      maxPileLength = math.max(maxPileLength, game.pileAt(i).length);
    }

    final BoardMetrics metrics = BoardMetrics.resolve(
      width: width,
      height: height,
      columns: tableau.length,
      maxPileLength: maxPileLength,
      shortestSide: shortestSide,
      isLandscape: isLandscape,
      sideStackCount: math.max(upper.length, foundations.length),
    );

    final _Builder builder = _Builder(
      game: game,
      metrics: metrics,
      width: width,
      height: height,
      upper: upper,
      foundations: foundations,
      tableau: tableau,
      wasteVisibleCount: wasteVisibleCount,
    );
    switch (metrics.layout) {
      case BoardLayout.portrait:
      case BoardLayout.phoneLandscape:
        builder.stacked();
      case BoardLayout.tabletLandscape:
        builder.tablet(); // implemented in Task 4
    }
    return BoardGeometry(
      metrics: metrics,
      cards: builder.cards,
      slots: builder.slots,
      dropTargets: builder.dropTargets,
    );
  }
}
```

Then a private mutable `_Builder` that accumulates placements. Implement `stacked()` now; leave `tablet()` as a stub that throws `UnimplementedError()` until Task 4.

```dart
class _Builder {
  _Builder({
    required this.game,
    required this.metrics,
    required this.width,
    required this.height,
    required this.upper,
    required this.foundations,
    required this.tableau,
    required this.wasteVisibleCount,
  });

  final GameState game;
  final BoardMetrics metrics;
  final double width;
  final double height;
  final List<int> upper;
  final List<int> foundations;
  final List<int> tableau;
  final int wasteVisibleCount;

  final List<CardPlacement> cards = <CardPlacement>[];
  final List<SlotPlacement> slots = <SlotPlacement>[];
  final Map<int, Rect> dropTargets = <int, Rect>{};

  static const double _pad = BoardMetrics.pad;

  double get _cardW => metrics.cardSize.width;
  double get _cardH => metrics.cardSize.height;

  /// Records a single-card (stock/foundation/free-cell) or empty slot at [origin].
  void _placeSingleOrSlot(int pileIndex, Offset origin) {
    final Pile pile = game.pileAt(pileIndex);
    final Rect slotRect = origin & metrics.cardSize;
    if (pile.isEmpty) {
      slots.add(
        SlotPlacement(pileIndex: pileIndex, kind: pile.kind, rect: slotRect),
      );
      dropTargets[pileIndex] = slotRect;
      return;
    }
    final int topIndex = pile.length - 1;
    cards.add(
      CardPlacement(
        card: pile.cards[topIndex],
        pileIndex: pileIndex,
        indexInPile: topIndex,
        isTop: true,
        rect: slotRect,
      ),
    );
    dropTargets[pileIndex] = slotRect;
  }

  /// Records the waste's fanned cards (last [wasteVisibleCount] + a backing
  /// card when older draws remain), mirroring PileView._wasteFan.
  void _placeWaste(int pileIndex, Offset origin) {
    final Pile pile = game.pileAt(pileIndex);
    if (pile.isEmpty) {
      final Rect slotRect = origin & metrics.cardSize;
      slots.add(
        SlotPlacement(pileIndex: pileIndex, kind: PileKind.waste, rect: slotRect),
      );
      dropTargets[pileIndex] = slotRect;
      return;
    }
    final int visible = math.min(wasteVisibleCount, pile.length);
    final double step = _cardW * BoardGeometry._wasteStep;
    final int oldestVisible = pile.length - visible;
    final int topIndex = pile.length - 1;

    if (oldestVisible > 0) {
      // One backing card at the oldest-visible slot (revealed mid-drag).
      cards.add(
        CardPlacement(
          card: pile.cards[oldestVisible - 1],
          pileIndex: pileIndex,
          indexInPile: oldestVisible - 1,
          isTop: false,
          rect: origin & metrics.cardSize,
        ),
      );
    }
    for (int i = 0; i < visible; i++) {
      final int idx = oldestVisible + i;
      final Offset o = origin.translate(step * i, 0);
      cards.add(
        CardPlacement(
          card: pile.cards[idx],
          pileIndex: pileIndex,
          indexInPile: idx,
          isTop: idx == topIndex,
          rect: o & metrics.cardSize,
        ),
      );
    }
    final double fanWidth = _cardW + step * (visible - 1);
    dropTargets[pileIndex] = origin & Size(fanWidth, _cardH);
  }

  /// Records a fanned tableau column at [origin] with the given gaps.
  void _placeTableau(int pileIndex, Offset origin, double upGap, double downGap) {
    final Pile pile = game.pileAt(pileIndex);
    if (pile.isEmpty) {
      final Rect slotRect = origin & metrics.cardSize;
      slots.add(
        SlotPlacement(
          pileIndex: pileIndex,
          kind: PileKind.tableau,
          rect: slotRect,
        ),
      );
      dropTargets[pileIndex] = slotRect;
      return;
    }
    double top = origin.dy;
    double lastTop = top;
    for (int i = 0; i < pile.length; i++) {
      final Card card = pile.cards[i];
      lastTop = top;
      cards.add(
        CardPlacement(
          card: card,
          pileIndex: pileIndex,
          indexInPile: i,
          isTop: i == pile.length - 1,
          rect: Offset(origin.dx, top) & metrics.cardSize,
        ),
      );
      top += card.faceUp ? upGap : downGap;
    }
    dropTargets[pileIndex] =
        Rect.fromLTWH(origin.dx, origin.dy, _cardW, (lastTop - origin.dy) + _cardH);
  }

  double _fanGap(double bottomHeight) {
    final double defaultGap = _cardH * 0.30;
    int maxLen = 1;
    for (final int i in tableau) {
      maxLen = math.max(maxLen, game.pileAt(i).length);
    }
    if (maxLen <= 1) return defaultGap;
    final double fitGap = (bottomHeight - _cardH) / (maxLen - 1);
    return math.max(_cardH * 0.06, math.min(defaultGap, fitGap));
  }

  void stacked() {
    final bool centred = metrics.layout == BoardLayout.phoneLandscape;
    final int cols = tableau.length;
    final double originX;
    final double innerW;
    if (centred) {
      final double contentW = _cardW * cols + _pad * (cols + 1);
      originX = (width - contentW) / 2 + _pad;
      innerW = _cardW * cols + _pad * (cols - 1);
    } else {
      originX = _pad;
      innerW = width - 2 * _pad;
    }
    final double topY = _pad;

    // Top row: upper piles left, foundations right.
    double ux = originX;
    for (final int i in upper) {
      if (game.pileAt(i).kind == PileKind.waste) {
        _placeWaste(i, Offset(ux, topY));
      } else {
        _placeSingleOrSlot(i, Offset(ux, topY));
      }
      ux += _cardW + _pad;
    }
    double fx = originX + innerW;
    for (int k = foundations.length - 1; k >= 0; k--) {
      fx -= _cardW;
      _placeSingleOrSlot(foundations[k], Offset(fx, topY));
      fx -= _pad;
    }

    // Tableau row.
    final double tableauTop = topY + _cardH + _pad;
    final double usableHeight = height - 2 * _pad;
    final double bottomHeight = math.max(_cardH, usableHeight - _cardH - _pad);
    final double upGap = _fanGap(bottomHeight);
    final double downGap = upGap * 0.5;
    final double colW = innerW / cols;
    for (int j = 0; j < cols; j++) {
      final double centerX = originX + colW * j + colW / 2;
      final double cardX = centerX - _cardW / 2;
      _placeTableau(tableau[j], Offset(cardX, tableauTop), upGap, downGap);
    }
  }

  void tablet() => throw UnimplementedError(); // Task 4
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/board_geometry_test.dart`
Expected: PASS. Adjust the arithmetic until every assertion holds (these are invariants, not magic pixels).

- [ ] **Step 5: Commit**

```bash
dart format lib/presentation/board_geometry.dart test/unit/board_geometry_test.dart
git add lib/presentation/board_geometry.dart test/unit/board_geometry_test.dart
git commit -m "feat: board geometry for stacked (portrait/phone-landscape) layouts"
```

---

### Task 4: `BoardGeometry.resolve` — tablet-landscape branch

Port `_sideColumnLayout` / `_sideColumn` / `_sideStack` from `board.dart`: the
tableau takes the left, the upper piles and foundations become two vertical
sub-columns in a right-hand side column of width `metrics.sideColumnWidth`.

**Files:**
- Modify: `lib/presentation/board_geometry.dart` (implement `_Builder.tablet()`)
- Test: `test/unit/board_geometry_test.dart`

**Interfaces:**
- Consumes / Produces: same `BoardGeometry` shape as Task 3; `tablet()` fills `cards`/`slots`/`dropTargets` for `BoardLayout.tabletLandscape`.

**Layout facts (from `board.dart:160-235`):** outer `pad`. Row = `Expanded(tableau)`, `SizedBox(pad)`, `SizedBox(sideColumnWidth)`. So `tableauAreaW = (width - 2*pad) - pad - sideColumnWidth`; tableau columns share `tableauAreaW`; tableau top = `pad` (full height, no top row). Side column: `Align(topCenter)` of a min-width `Row[ sideStack(upper), SizedBox(pad), sideStack(foundations) ]`; each sub-column is `cardW` wide, slots stacked `pad` apart from `y = pad`. Row width = `2*cardW + pad`; `sideColumnWidth = 2*cardW + 3*pad`, so the centered row is inset `pad` inside the side column. `bottomHeight = height - 2*pad` for the fan gap here.

- [ ] **Step 1: Write the failing tests**

```dart
// add to test/unit/board_geometry_test.dart
GameState _freecell() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.freecell, cards: <Card>[_up(Suit.spades, 7)]),
    Pile(kind: PileKind.freecell),
    Pile(kind: PileKind.freecell),
    Pile(kind: PileKind.freecell),
    Pile(kind: PileKind.foundation, cards: <Card>[_up(Suit.clubs, aceRank)]),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    for (int i = 0; i < 8; i++) Pile(kind: PileKind.tableau),
  ],
);

void main() {
  // ... existing groups ...

  group('tablet-landscape geometry', () {
    test('foundations sit to the right of the last tableau column', () {
      final BoardGeometry g = BoardGeometry.resolve(
        game: _klondike(),
        width: 1200,
        height: 800,
        shortestSide: 800,
        isLandscape: true,
        wasteVisibleCount: 1,
      );
      expect(g.metrics.layout, BoardLayout.tabletLandscape);
      expect(
        _rectOf(g, Suit.clubs, aceRank).center.dx,
        greaterThan(_rectOf(g, Suit.diamonds, kingRank).center.dx),
      );
    });

    test('free cells sit left of the foundations', () {
      final BoardGeometry g = BoardGeometry.resolve(
        game: _freecell(),
        width: 1200,
        height: 800,
        shortestSide: 800,
        isLandscape: true,
        wasteVisibleCount: 1,
      );
      expect(
        _rectOf(g, Suit.spades, 7).center.dx,
        lessThan(_rectOf(g, Suit.clubs, aceRank).center.dx),
      );
    });

    test('nothing overflows the viewport', () {
      final BoardGeometry g = BoardGeometry.resolve(
        game: _klondike(),
        width: 1200,
        height: 800,
        shortestSide: 800,
        isLandscape: true,
        wasteVisibleCount: 1,
      );
      for (final CardPlacement p in g.cards) {
        expect(p.rect.right, lessThanOrEqualTo(1200 + 0.5));
        expect(p.rect.bottom, lessThanOrEqualTo(800 + 0.5));
      }
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/board_geometry_test.dart`
Expected: FAIL — `tablet()` throws `UnimplementedError`.

- [ ] **Step 3: Implement `_Builder.tablet()`**

```dart
void tablet() {
  final int cols = tableau.length;
  final double sideW = metrics.sideColumnWidth;
  final double topY = _pad;
  final double tableauAreaW = (width - 2 * _pad) - _pad - sideW;
  final double colW = tableauAreaW / cols;

  // Tableau on the left, full height.
  final double bottomHeight = math.max(_cardH, height - 2 * _pad);
  final double upGap = _fanGap(bottomHeight);
  final double downGap = upGap * 0.5;
  for (int j = 0; j < cols; j++) {
    final double centerX = _pad + colW * j + colW / 2;
    _placeTableau(tableau[j], Offset(centerX - _cardW / 2, topY), upGap, downGap);
  }

  // Right side column: two centered sub-columns (upper left, foundations right).
  final double sideLeft = _pad + tableauAreaW + _pad;
  final double upperX = sideLeft + _pad; // centered inset (see layout facts)
  final double foundX = upperX + _cardW + _pad;
  for (int i = 0; i < upper.length; i++) {
    final double y = topY + i * (_cardH + _pad);
    final int idx = upper[i];
    if (game.pileAt(idx).kind == PileKind.waste) {
      _placeWaste(idx, Offset(upperX, y));
    } else {
      _placeSingleOrSlot(idx, Offset(upperX, y));
    }
  }
  for (int i = 0; i < foundations.length; i++) {
    final double y = topY + i * (_cardH + _pad);
    _placeSingleOrSlot(foundations[i], Offset(foundX, y));
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/board_geometry_test.dart`
Expected: PASS. Tune insets until green.

- [ ] **Step 5: Commit**

```bash
dart format lib/presentation/board_geometry.dart test/unit/board_geometry_test.dart
git add lib/presentation/board_geometry.dart test/unit/board_geometry_test.dart
git commit -m "feat: board geometry for tablet-landscape layout"
```

---

### Task 5: Extract `SlotPlaceholder` widget from `PileView`

Pure refactor: lift `PileView._placeholder` / `_slotFill` / `_slotMarker` /
`_foundationMarker` / `_parkMarker` into a standalone `SlotPlaceholder` widget so
the rewritten board (Task 6) can render empty slots without `PileView`. No
behavior change; the existing `slot_placeholder_test.dart` is the gate.

**Files:**
- Create: `lib/presentation/slot_placeholder.dart`
- Modify: `lib/presentation/pile_view.dart` (delegate `_placeholder` to the new widget)
- Test: existing `test/widget/slot_placeholder_test.dart` (unchanged) is the gate.

**Interfaces:**
- Produces: `class SlotPlaceholder extends StatelessWidget { const SlotPlaceholder({required this.kind, required this.cardSize, this.onTap, super.key}); }` — renders the outlined slot + role marker; forwards a tap when `onTap != null`. Re-exports the existing `foundationSlotMarkerKey` / `parkSlotMarkerKey` keys (move the `const Key` declarations here and re-export from `pile_view.dart`, or keep them in `pile_view.dart` and import).
- Consumes: `PileKind`, `GamePalette`.

- [ ] **Step 1: Confirm the current gate is green**

Run: `flutter test test/widget/slot_placeholder_test.dart`
Expected: PASS (baseline before refactor).

- [ ] **Step 2: Create `SlotPlaceholder`**

Move the body of `PileView._placeholder` (pile_view.dart:92-195) into
`SlotPlaceholder`, parameterised by `PileKind kind` and `Size cardSize` and an
optional `VoidCallback? onTap` (used by the stock's recycle tap). Keep the
`foundationSlotMarkerKey` / `parkSlotMarkerKey` keys on the same markers. The
stock shows `Icon(Icons.refresh)`; foundation the 2×2 suit cluster; freecell &
tableau the park diamond; waste nothing.

- [ ] **Step 3: Delegate from `PileView`**

In `pile_view.dart`, replace `_placeholder()`'s body with:

```dart
Widget _placeholder() => SlotPlaceholder(
  kind: pile.kind,
  cardSize: cardSize,
  onTap: onPileTap,
);
```

Keep `foundationSlotMarkerKey` / `parkSlotMarkerKey` importable from wherever
they now live so `slot_placeholder_test.dart` still resolves them.

- [ ] **Step 4: Run the gate**

Run: `flutter analyze && flutter test test/widget/slot_placeholder_test.dart test/widget/board_layout_test.dart`
Expected: PASS with no analyzer warnings.

- [ ] **Step 5: Commit**

```bash
dart format lib/presentation/slot_placeholder.dart lib/presentation/pile_view.dart
git add lib/presentation/slot_placeholder.dart lib/presentation/pile_view.dart
git commit -m "refactor: extract SlotPlaceholder widget from PileView"
```

---

### Task 6: Rewrite `Board` as a static positioned `Stack` (no animation yet)

Replace the Flex tree in `board.dart` with a single `Stack` built from
`BoardGeometry`: one `Positioned` per card (a keyed `CardView`), one `Positioned`
`SlotPlaceholder` per empty pile, and one `Positioned` `DragTarget` per pile hit
region. Keep every gesture wiring identical. **Still uses plain `Positioned`** —
animation arrives in Task 7. The **entire existing widget suite** is the gate.

**Files:**
- Modify: `lib/presentation/board.dart`
- Test: existing `test/widget/board_layout_test.dart`, `card_drag_test.dart`, `waste_pile_test.dart`, `slot_placeholder_test.dart`, `game_widget_test.dart`, `game_menu_test.dart` are the gate.

**Interfaces:**
- Consumes: `BoardGeometry`, `CardPlacement`, `SlotPlacement`, `CardKey`, `SlotPlaceholder`, `CardView`, `CardDragData`, `GameBloc`, events.
- Produces: `Board` renders a `Stack`. `CardView`s carry `key: placement.key.widgetKey`. Drop callback now also passes the drop offset (see next line).
- **Signature change:** `PileView.onDrop` / the drop path must surface the drop location for Task 10. Change `CardView`/drop wiring so the board's drop handler receives `(CardDragData data, Offset globalDropOffset)`. In this task, wire it through `DragTarget.onAcceptWithDetails` using `details.offset`; the board may ignore the offset for now (Task 10 consumes it). Define the board drop handler as `void _drop(BuildContext, CardDragData, Offset, int toPile)`.

- [ ] **Step 1: Confirm the full gate is green (baseline)**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 2: Write a new failing structural test**

```dart
// test/widget/board_animation_test.dart  (new file — grows across Tasks 6-11)
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/presentation/bloc/game_bloc.dart';
import 'package:open_patience/presentation/board.dart';
import 'package:open_patience/presentation/card_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

Finder _cardFace(Suit s, int rank) => find.byWidgetPredicate(
  (Widget w) =>
      w is CardFace && w.card.suit == s && w.card.rank == rank && w.card.faceUp,
);

GameState _oneAce() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, aceRank)]),
    for (int i = 0; i < 6; i++) Pile(kind: PileKind.tableau),
  ],
);

Future<GameBloc> _pump(
  WidgetTester tester,
  Size size, {
  required GameState state,
  bool disableAnimations = false,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final RecordsRepository repo =
      SharedPrefsRecordsRepository(await SharedPreferences.getInstance());
  final GameBloc bloc = GameBloc(
    variant: 'klondike-draw1',
    repository: repo,
    seed: 1,
    state: state,
  );
  addTearDown(bloc.close);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          disableAnimations: disableAnimations,
        ),
        child: Scaffold(
          body: BlocProvider<GameBloc>.value(value: bloc, child: const Board()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return bloc;
}

void main() {
  testWidgets('board renders every card exactly once inside a single Stack', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const Size(400, 800), state: _oneAce());
    expect(tester.takeException(), isNull);
    expect(_cardFace(Suit.spades, aceRank), findsOneWidget);
  });
}
```

- [ ] **Step 3: Rewrite `Board`**

Rewrite `board.dart` so `build` wraps a `DragScopeHost` around a
`BlocBuilder<GameBloc, GameBlocState>` (keep the existing `buildWhen` on
`piles`), then a `LayoutBuilder` + `MediaQuery` that calls
`BoardGeometry.resolve(...)` and builds a `Stack(clipBehavior: Clip.none)` with,
in this order: (1) a `Positioned` `DragTarget` per `dropTargets` entry, (2) a
`Positioned` `SlotPlaceholder` per `slots` entry, (3) a `Positioned` `CardView`
per `cards` entry (in `geometry.cards` order). Compute
`wasteVisibleCount` exactly as today (`_wasteVisibleCount`).

```dart
// build one card
Widget _positionedCard(BuildContext context, CardPlacement p, BoardGeometry g) {
  final Pile pile = /* game.pileAt(p.pileIndex) */;
  return Positioned(
    key: p.key.widgetKey,
    left: p.rect.left,
    top: p.rect.top,
    width: p.rect.width,
    height: p.rect.height,
    child: _cardWidgetFor(context, p, pile), // ports PileView's per-kind logic
  );
}
```

`_cardWidgetFor` replicates today's per-kind interactivity:
- **stock:** a `CardFace(card: top.faceDownCard)` wrapped in a `GestureDetector`
  dispatching `TapMoveRequested(fromPile: idx)` (the recycle/draw tap).
- **waste:** the top (`isTop`) card is an interactive `CardView` with
  `dragData: CardDragData(fromPile: idx, cardIndex: p.indexInPile)` and
  tap/double-tap; non-top waste cards are plain `CardFace`.
- **foundation / freecell:** interactive `CardView` for the top card.
- **tableau:** face-up cards get `CardView` with `dragData` +
  `dragStack: pile.cards.sublist(p.indexInPile)`; `onTap`/`onDoubleTap` only on
  the top face-up card (matches `pile_view.dart:300-309`); face-down cards are
  plain `CardFace`.

Drop targets:

```dart
Widget _positionedDropTarget(BuildContext context, int pileIndex, Rect r) {
  return Positioned.fromRect(
    rect: r,
    child: DragTarget<CardDragData>(
      onWillAcceptWithDetails: (DragTargetDetails<CardDragData> d) =>
          d.data.fromPile != pileIndex,
      onAcceptWithDetails: (DragTargetDetails<CardDragData> d) =>
          _drop(context, d.data, d.offset, pileIndex),
      builder: (BuildContext _, _, _) => const SizedBox.expand(),
    ),
  );
}

void _drop(BuildContext c, CardDragData data, Offset globalDrop, int toPile) {
  c.read<GameBloc>().add(
    MoveRequested(
      fromPile: data.fromPile,
      toPile: toPile,
      cardIndex: data.cardIndex,
    ),
  );
  // globalDrop is unused until Task 10.
}
```

Keep `_tap` / `_doubleTap` dispatching `TapMoveRequested` / `DoubleTapRequested`
exactly as today. Delete the now-dead `_stackedLayout` / `_sideColumnLayout` /
`_topRow` / `_tableauRow` / `_slot` / `_fanGap` helpers and the `PileView` import
if unused. (Keep `pile_view.dart` for `waste_pile_test` only if those tests
still target it — otherwise migrate those assertions to `CardFace` finders in a
follow-up within this task; do not leave dead code.)

- [ ] **Step 4: Run the full gate**

Run: `flutter analyze && flutter test`
Expected: PASS. The `board_layout_test` relative-position and fit-to-height
assertions, `card_drag_test` drag flows, and `waste_pile_test` must all stay
green. If a relative assertion fails, fix the geometry (Tasks 3-4), not the
test. If `waste_pile_test`/`slot_placeholder_test` reference `PileView`
internals that no longer render, update those tests to assert the same
user-visible behavior via `CardFace` / `SlotPlaceholder` finders — note the
change in the commit.

- [ ] **Step 5: Commit**

```bash
dart format lib/presentation/board.dart test/widget/board_animation_test.dart
git add -A
git commit -m "refactor: render board as one positioned Stack from BoardGeometry"
```

---

### Task 7: Animate positions with `AnimatedPositioned` + reduce-motion

Make `Board` a `StatefulWidget`, swap each card's `Positioned` for an
`AnimatedPositioned` keyed by `CardKey`. Duration comes from `GameMotion`,
collapsed to `Duration.zero` when `MediaQuery.disableAnimations`. Slots and drop
targets stay plain `Positioned`. This alone delivers tap/double-tap move
animation and the stock→waste slide (both are just a card whose target rect
changed).

**Files:**
- Modify: `lib/presentation/board.dart`
- Test: `test/widget/board_animation_test.dart`

**Interfaces:**
- Consumes: `GameMotion`.
- Produces: `Board` is a `StatefulWidget`; card widgets are `AnimatedPositioned`.

- [ ] **Step 1: Write the failing tests**

```dart
// add to test/widget/board_animation_test.dart

testWidgets('reduce-motion: a tap-move lands instantly in one frame', (
  WidgetTester tester,
) async {
  final GameBloc bloc = await _pump(
    tester,
    const Size(400, 800),
    state: _oneAce(),
    disableAnimations: true,
  );
  await tester.tap(_cardFace(Suit.spades, aceRank));
  await tester.pump(); // process the event
  await tester.pump(); // one build; no animation to settle
  expect(bloc.state.state.pileAt(6).isEmpty, isTrue);
  // The ace now renders at a foundation position (top of the board).
  expect(
    tester.getCenter(_cardFace(Suit.spades, aceRank)).dy,
    lessThan(200),
  );
});

testWidgets('animated tap-move converges to the same final layout', (
  WidgetTester tester,
) async {
  await _pump(tester, const Size(400, 800), state: _oneAce());
  final Offset before = tester.getCenter(_cardFace(Suit.spades, aceRank));
  await tester.tap(_cardFace(Suit.spades, aceRank));
  await tester.pump(); // start animation
  await tester.pump(const Duration(milliseconds: 60)); // mid-flight
  final Offset mid = tester.getCenter(_cardFace(Suit.spades, aceRank));
  await tester.pumpAndSettle();
  final Offset after = tester.getCenter(_cardFace(Suit.spades, aceRank));
  // It actually moved during the animation (not an instant jump)...
  expect(mid, isNot(equals(before)));
  expect(mid, isNot(equals(after)));
  // ...and settled above where it started (now on a foundation).
  expect(after.dy, lessThan(before.dy));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/board_animation_test.dart`
Expected: FAIL — the animated test finds `mid == before` (no animation) or
`mid == after` (instant), because Task 6 uses plain `Positioned`.

- [ ] **Step 3: Implement**

Convert `Board` to `StatefulWidget`. In `build`, read
`final bool reduceMotion = MediaQuery.of(context).disableAnimations;` and
`final Duration d = GameMotion.resolve(GameMotion.move, reduceMotion: reduceMotion);`.
Replace `_positionedCard`'s `Positioned` with:

```dart
AnimatedPositioned(
  key: p.key.widgetKey,
  duration: d,
  curve: GameMotion.moveCurve,
  left: p.rect.left,
  top: p.rect.top,
  width: p.rect.width,
  height: p.rect.height,
  child: _cardWidgetFor(context, p, pile),
)
```

The stable `key` is what lets `AnimatedPositioned` recognise the same card
across a rebuild and tween `left`/`top`.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter analyze && flutter test test/widget/board_animation_test.dart && flutter test`
Expected: PASS (whole suite).

- [ ] **Step 5: Commit**

```bash
dart format lib/presentation/board.dart test/widget/board_animation_test.dart
git add lib/presentation/board.dart test/widget/board_animation_test.dart
git commit -m "feat: animate card positions with AnimatedPositioned (+reduce-motion)"
```

---

### Task 8: Correct paint order during flight (moving-set)

A card flying across the board must paint above the piles it crosses. Track the
previous state; cards whose `(pileIndex, indexInPile)` changed this transition
are the *moving set* and are appended last in the `Stack` children (painted on
top). Release a card from the set via `AnimatedPositioned.onEnd`.

**Files:**
- Modify: `lib/presentation/board.dart`
- Test: `test/widget/board_animation_test.dart`

**Interfaces:**
- Consumes: `CardPlacement`, `CardKey`.
- Produces: `_BoardState` holds `GameState? _previous` and `Set<CardKey> _moving`; a helper `List<CardPlacement> _paintOrdered(BoardGeometry)` returns cards with moving ones last.

- [ ] **Step 1: Write the failing test**

```dart
// add to test/widget/board_animation_test.dart

testWidgets('a moving card paints above the cards it flies over', (
  WidgetTester tester,
) async {
  // Ace on tableau col 6; when tapped it flies up to a foundation, crossing
  // other top-row slots. Mid-flight it must be the last CardView in the Stack.
  await _pump(tester, const Size(400, 800), state: _oneAce());
  await tester.tap(_cardFace(Suit.spades, aceRank));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 60)); // mid-flight

  final List<CardFace> faces =
      tester.widgetList<CardFace>(find.byType(CardFace)).toList();
  // The flying ace is the last-painted CardFace.
  expect(faces.last.card.suit, Suit.spades);
  expect(faces.last.card.rank, aceRank);

  await tester.pumpAndSettle();
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/board_animation_test.dart`
Expected: FAIL — without a moving-set the ace keeps its pile-major order and is
not last.

- [ ] **Step 3: Implement**

In `_BoardState`:

```dart
GameState? _previous;
final Set<CardKey> _moving = <CardKey>{};

Set<CardKey> _diffMoved(GameState? prev, GameState next) {
  if (prev == null) return <CardKey>{};
  final Map<CardKey, (int, int)> before = _positions(prev);
  final Map<CardKey, (int, int)> after = _positions(next);
  final Set<CardKey> moved = <CardKey>{};
  after.forEach((CardKey k, (int, int) pos) {
    final (int, int)? was = before[k];
    if (was == null || was != pos) moved.add(k);
  });
  return moved;
}

Map<CardKey, (int, int)> _positions(GameState g) {
  final Map<CardKey, (int, int)> m = <CardKey, (int, int)>{};
  for (int pi = 0; pi < g.piles.length; pi++) {
    final Pile pile = g.pileAt(pi);
    for (int ci = 0; ci < pile.length; ci++) {
      m[CardKey.of(pile.cards[ci])] = (pi, ci);
    }
  }
  return m;
}
```

In `build`, when the rendered `GameState` differs from `_previous`, compute the
new moving set (use a post-frame `setState` or compute it inline while updating
`_previous`; keep it side-effect-free within `build` by doing the diff in
`didUpdateWidget`-style logic keyed off the bloc state — simplest is to track
`_previous` and recompute in a `BlocListener` on `piles` that calls
`setState(() { _moving = _diffMoved(_previous, next); _previous = next; })`).
Order children with moving cards last:

```dart
List<CardPlacement> ordered = <CardPlacement>[
  ...geometry.cards.where((CardPlacement p) => !_moving.contains(p.key)),
  ...geometry.cards.where((CardPlacement p) => _moving.contains(p.key)),
];
```

Add `onEnd: () => setState(() => _moving.remove(p.key))` to the moving card's
`AnimatedPositioned`. Under reduce-motion (`duration == Duration.zero`),
`onEnd` fires immediately, so the set self-clears — correct.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter analyze && flutter test`
Expected: PASS (whole suite).

- [ ] **Step 5: Commit**

```bash
dart format lib/presentation/board.dart test/widget/board_animation_test.dart
git add lib/presentation/board.dart test/widget/board_animation_test.dart
git commit -m "feat: paint moving cards above the piles they cross"
```

---

### Task 9: Flip animation in `CardView`

When a card's `faceUp` changes, run a short Y-axis flip. Contained entirely in
`card_view.dart`; honors reduce-motion.

**Files:**
- Modify: `lib/presentation/card_view.dart`
- Test: `test/widget/board_animation_test.dart`

**Interfaces:**
- Consumes: `GameMotion`.
- Produces: `CardFace` (or a new private `_FlippingFace` used inside `CardView`/waste/stock) animates a face change. Public `CardFace` / `CardView` constructors unchanged.

- [ ] **Step 1: Write the failing test**

```dart
// add to test/widget/board_animation_test.dart

GameState _stockToDraw() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock, cards: <Card>[
      const Card(suit: Suit.hearts, rank: 9), // face-down in stock
    ]),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    for (int i = 0; i < 7; i++) Pile(kind: PileKind.tableau),
  ],
);

testWidgets('drawing from stock ends with a face-up card on the waste', (
  WidgetTester tester,
) async {
  final GameBloc bloc = await _pump(
    tester,
    const Size(400, 800),
    state: _stockToDraw(),
  );
  // Tap the stock (top-left) to draw.
  await tester.tap(find.byType(CardFace).first);
  await tester.pumpAndSettle();
  expect(bloc.state.state.pileAt(1).topCard!.faceUp, isTrue);
  expect(_cardFace(Suit.hearts, 9), findsOneWidget); // face-up nine on waste
});

testWidgets('reduce-motion shows the flipped face immediately', (
  WidgetTester tester,
) async {
  final GameBloc bloc = await _pump(
    tester,
    const Size(400, 800),
    state: _stockToDraw(),
    disableAnimations: true,
  );
  await tester.tap(find.byType(CardFace).first);
  await tester.pump();
  await tester.pump();
  expect(bloc.state.state.pileAt(1).topCard!.faceUp, isTrue);
});
```

- [ ] **Step 2: Run test to verify it fails / passes trivially**

Run: `flutter test test/widget/board_animation_test.dart`
Expected: the "ends face-up" test may already PASS structurally (the slide from
Task 7 moves the card and the waste renders it face-up). If both pass with no
flip code, still add the flip in Step 3 for the *visual* — and add the assertion
below that a flip transform is present mid-animation to force real code:

```dart
testWidgets('a face change runs a flip transform', (WidgetTester tester) async {
  await _pump(tester, const Size(400, 800), state: _stockToDraw());
  await tester.tap(find.byType(CardFace).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80)); // mid-flip
  // A Transform (the rotationY flip) is animating a card mid-draw.
  expect(find.byType(Transform), findsWidgets);
  await tester.pumpAndSettle();
});
```

(There are already static `Transform.rotate`s in card corners; make this
assertion specific by giving the flip `Transform` a `key: const Key('cardFlip')`
and finding that key instead.)

- [ ] **Step 3: Implement the flip**

Wrap the face in a small stateful `_FlippingFace` that runs a
`TweenAnimationBuilder<double>` from 0→1 whenever `card.faceUp` changes, applying
`Transform(key: const Key('cardFlip'), transform: Matrix4.rotationY(...))` and
swapping the shown face at the half-way point. Duration
`GameMotion.resolve(GameMotion.flip, reduceMotion: MediaQuery.of(context).disableAnimations)`.
Use it inside `CardView` and for the waste/stock faces so a drawn card flips.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter analyze && flutter test`
Expected: PASS (whole suite).

- [ ] **Step 5: Commit**

```bash
dart format lib/presentation/card_view.dart test/widget/board_animation_test.dart
git add lib/presentation/card_view.dart test/widget/board_animation_test.dart
git commit -m "feat: flip animation when a card turns face up/down"
```

---

### Task 10: Drop-settle from the release point

`AnimatedPositioned` would animate a dropped card from its *source* pile, which
reads as a teleport-back. Instead seed the moved card's animation start at the
release point. `DragTarget.onAcceptWithDetails` gives a global offset; convert it
once through the board container's own `RenderBox` (the single, bounded
measurement in the system) to board-local, place the card there for one frame,
then let `AnimatedPositioned` tween to the target.

**Files:**
- Modify: `lib/presentation/board.dart`
- Test: `test/widget/board_animation_test.dart`

**Interfaces:**
- Consumes: `_drop(..., Offset globalDrop, ...)` from Task 6.
- Produces: `_BoardState` holds `Map<CardKey, Offset> _settleFrom` and a `GlobalKey _stackKey` on the board's `Stack` container.

- [ ] **Step 1: Write the failing test**

```dart
// add to test/widget/board_animation_test.dart

GameState _dragPair() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, 7)]),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.hearts, 8)]),
    for (int i = 0; i < 5; i++) Pile(kind: PileKind.tableau),
  ],
);

testWidgets('a dropped card settles from the release point, not the source', (
  WidgetTester tester,
) async {
  final GameBloc bloc = await _pump(
    tester,
    const Size(400, 800),
    state: _dragPair(),
  );
  final Offset source = tester.getCenter(_cardFace(Suit.spades, 7));
  final Offset target = tester.getCenter(_cardFace(Suit.hearts, 8));

  final TestGesture g = await tester.startGesture(source);
  await tester.pump(const Duration(milliseconds: 200));
  await g.moveTo(target);
  await tester.pump();
  await g.up();
  await tester.pump(); // move accepted; card re-homed to col 7
  await tester.pump(const Duration(milliseconds: 30)); // first settle frame

  // Mid-settle the seven is near the release point (col 7), NOT back at col 6.
  final double x = tester.getCenter(_cardFace(Suit.spades, 7)).dx;
  expect((x - target.dx).abs(), lessThan((x - source.dx).abs()));

  await tester.pumpAndSettle();
  expect(bloc.state.state.pileAt(7).length, 2); // 8 then 7
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget/board_animation_test.dart`
Expected: FAIL — the seven animates from col 6 (source), so mid-settle it is
closer to `source` than `target`.

- [ ] **Step 3: Implement**

Give the board `Stack` a `GlobalKey _stackKey`. In `_drop`, before dispatching
`MoveRequested`, convert and record the settle origin:

```dart
final RenderBox? box =
    _stackKey.currentContext?.findRenderObject() as RenderBox?;
if (box != null) {
  final Offset local = box.globalToLocal(globalDrop);
  setState(() => _settleFrom[data.cardKeyOf()] = local);
}
```

(Derive the moved card's `CardKey` from `data` — thread the top card's identity
into `CardDragData`, or look it up from the source pile at `data.cardIndex`
before the move applies.) When building a card whose key is in `_settleFrom`,
render it for the first post-move frame at that offset with `duration:
Duration.zero`, then in a post-frame callback `setState` to remove it from
`_settleFrom` so the next build places it at the real target and
`AnimatedPositioned` tweens release→target. Clear via `onEnd` as a backstop.
Under reduce-motion, skip the seeding (snap straight to target).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter analyze && flutter test`
Expected: PASS (whole suite, including `card_drag_test`).

- [ ] **Step 5: Commit**

```bash
dart format lib/presentation/board.dart test/widget/board_animation_test.dart
git add lib/presentation/board.dart test/widget/board_animation_test.dart
git commit -m "feat: settle a dropped card from the release point"
```

---

### Task 11: Deal animation behind a `SpecialSequence` seam

Introduce the isolation seam and a modest staggered deal. The board asks a
`SpecialSequence` whether a transition is a set-piece; if so, it plays the
sequence's per-card *activation* schedule (cards start at the stock origin and
reveal their real target on a stagger). Swapping in a fancier deal later is one
new `SpecialSequence` implementation — `board.dart` and the geometry are
untouched.

**Files:**
- Create: `lib/presentation/board_sequence.dart`
- Modify: `lib/presentation/board.dart`
- Test: `test/unit/board_sequence_test.dart`, `test/widget/board_animation_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class SpecialSequence { bool matches(GameState? previous, GameState next); Duration delayFor(CardKey key, BoardGeometry geometry); Duration get total; }`
  - `class DealSequence implements SpecialSequence` — `matches` returns true when `previous == null` (first render) or when every tableau/stock card in `next` was absent in `previous` (a fresh deal); `delayFor` returns `GameMotion.dealStagger * orderIndex` where `orderIndex` walks piles/cards in deal order; `total` is the last delay + `GameMotion.move`.
  - `Offset dealOriginOf(BoardGeometry)` — the stock slot's top-left (deal fly-from point).

- [ ] **Step 1: Write the failing unit test**

```dart
// test/unit/board_sequence_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/presentation/board_geometry.dart';
import 'package:open_patience/presentation/board_sequence.dart';
import 'package:open_patience/ui/theme/game_motion.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

GameState _dealt() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, 5)]),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.hearts, 8)]),
    for (int i = 0; i < 5; i++) Pile(kind: PileKind.tableau),
  ],
);

void main() {
  test('DealSequence matches the first render', () {
    expect(DealSequence().matches(null, _dealt()), isTrue);
  });

  test('DealSequence does not match an ordinary move', () {
    final GameState a = _dealt();
    expect(DealSequence().matches(a, a), isFalse);
  });

  test('later cards in deal order get longer delays', () {
    final DealSequence s = DealSequence();
    final BoardGeometry g = BoardGeometry.resolve(
      game: _dealt(),
      width: 400,
      height: 800,
      shortestSide: 400,
      isLandscape: false,
      wasteVisibleCount: 1,
    );
    final Duration d5 = s.delayFor(const CardKey(Suit.spades, 5), g);
    final Duration d8 = s.delayFor(const CardKey(Suit.hearts, 8), g);
    expect(d5, isNot(equals(d8)));
    expect(s.total, greaterThanOrEqualTo(GameMotion.move));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/board_sequence_test.dart`
Expected: FAIL — `board_sequence.dart` not found.

- [ ] **Step 3: Implement the seam + `DealSequence`**

Create `board_sequence.dart` with the interface and `DealSequence` as specified
in Interfaces. `delayFor` assigns each card an order index by iterating
`geometry.cards` (already pile-major, bottom-to-top) and multiplying its index
by `GameMotion.dealStagger`.

- [ ] **Step 4: Run the unit test**

Run: `flutter test test/unit/board_sequence_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire the deal into the board + widget test**

Add the widget test first (RED):

```dart
// add to test/widget/board_animation_test.dart

testWidgets('a fresh deal converges to the resolved layout', (
  WidgetTester tester,
) async {
  await _pump(tester, const Size(400, 800), state: _dragPair());
  // During the deal, some cards have not yet reached their slots.
  await tester.pump(const Duration(milliseconds: 10));
  // After it settles, both distinctive cards are at rest and visible.
  await tester.pumpAndSettle();
  expect(_cardFace(Suit.spades, 7), findsOneWidget);
  expect(_cardFace(Suit.hearts, 8), findsOneWidget);
  expect(tester.takeException(), isNull);
});

testWidgets('reduce-motion deals instantly (no stagger)', (
  WidgetTester tester,
) async {
  await _pump(
    tester,
    const Size(400, 800),
    state: _dragPair(),
    disableAnimations: true,
  );
  await tester.pump();
  expect(_cardFace(Suit.spades, 7), findsOneWidget);
});
```

Then implement: in `_BoardState`, when the current transition
`_activeSequence?.matches(prev, next)` is true, drive an `AnimationController`
(duration `sequence.total`) started on that transition. For each card, if
`controller.lastElapsedDuration < sequence.delayFor(key, geometry)` it has not
"activated" yet: render it at `dealOriginOf(geometry)` (the stock slot). Once
activated, render it at its real target so `AnimatedPositioned` tweens it out.
Rebuild each tick via the controller (`AnimatedBuilder` or
`addListener(setState)`). Under reduce-motion, skip the controller entirely and
render targets immediately. Keep the sequence field pluggable:
`final SpecialSequence _dealSequence = DealSequence();` — a comment notes that
swapping deal/win animations means replacing these fields only.

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter analyze && flutter test`
Expected: PASS (whole suite).

- [ ] **Step 7: Commit**

```bash
dart format lib/presentation/board_sequence.dart lib/presentation/board.dart \
  test/unit/board_sequence_test.dart test/widget/board_animation_test.dart
git add -A
git commit -m "feat: staggered deal animation behind a SpecialSequence seam"
```

---

### Task 12: Modest win flourish behind the seam

Add a `WinSequence` (a second `SpecialSequence`) that plays a brief, gentle
flourish when the bloc emits `GameWon` — e.g. a short scale/opacity pulse of the
foundation cards. Kept modest and isolated so a full arcade cascade can replace
it later by swapping this one class.

**Files:**
- Modify: `lib/presentation/board_sequence.dart` (add `WinSequence`)
- Modify: `lib/presentation/board.dart` (engage `WinSequence` on `GameWon`)
- Test: `test/unit/board_sequence_test.dart`, `test/widget/board_animation_test.dart`

**Interfaces:**
- Produces: `class WinSequence implements SpecialSequence` — `matches` reserved for a `GameWon`-derived flag (the board passes win-ness in; keep `matches` signature but drive engagement from the bloc state type in the board). Expose `Duration get total` and a `double pulseAt(Duration elapsed)` scale factor in `[1.0, 1.08]` for foundation cards.

- [ ] **Step 1: Write the failing unit test**

```dart
// add to test/unit/board_sequence_test.dart

void main() {
  // ... existing ...
  test('WinSequence pulse starts and returns to rest scale', () {
    final WinSequence w = WinSequence();
    expect(w.pulseAt(Duration.zero), closeTo(1.0, 0.001));
    expect(w.pulseAt(w.total), closeTo(1.0, 0.02));
    expect(w.pulseAt(w.total ~/ 2), greaterThan(1.0));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/unit/board_sequence_test.dart`
Expected: FAIL — `WinSequence` not found.

- [ ] **Step 3: Implement `WinSequence`**

Add `WinSequence` computing a symmetric ease pulse (up then back to 1.0) over
`total` (e.g. 600ms).

- [ ] **Step 4: Wire into the board + widget test (RED first)**

```dart
// add to test/widget/board_animation_test.dart

GameState _almostWon() {
  // A board one legal tap-to-foundation away from a win, so the bloc emits
  // GameWon after the move. Build the minimal completed-except-one layout for
  // klondike-draw1 (all foundations full but one, last card tap-movable).
  // (Construct with all four foundations K-high except one missing its King,
  //  which sits face-up alone on a tableau column.)
  // ... see klondike_test.dart / auto_complete_test.dart for a winnable setup.
}

testWidgets('winning plays a flourish and then rests without error', (
  WidgetTester tester,
) async {
  final GameBloc bloc = await _pump(
    tester,
    const Size(400, 800),
    state: _almostWon(),
  );
  // Perform the final move (tap the last king to its foundation).
  await tester.tap(_cardFace(Suit.spades, kingRank));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100)); // mid-flourish
  await tester.pumpAndSettle();
  expect(bloc.state.state.isWon(bloc.rules), isTrue);
  expect(tester.takeException(), isNull);
});
```

Build `_almostWon()` from the winnable helpers in `test/unit/auto_complete_test.dart`
/ `klondike_test.dart` (reuse an existing near-win `GameState` builder rather
than inventing one). In `_BoardState`, when the bloc state is `GameWon`, engage
`WinSequence` via an `AnimationController(duration: WinSequence().total)` and
apply `pulseAt(elapsed)` as a `Transform.scale` on foundation-pile cards. Under
reduce-motion, skip the pulse.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter analyze && flutter test`
Expected: PASS (whole suite).

- [ ] **Step 6: Commit**

```bash
dart format lib/presentation/board_sequence.dart lib/presentation/board.dart \
  test/unit/board_sequence_test.dart test/widget/board_animation_test.dart
git add -A
git commit -m "feat: modest win flourish behind the SpecialSequence seam"
```

---

### Task 13: Final verification

**Files:** none (verification only).

- [ ] **Step 1: Full static + test gate**

Run: `flutter analyze`
Expected: no issues.

- [ ] **Step 2: Import-boundary check**

Run: `! grep -rl "package:flutter" lib/core lib/persistence`
Expected: exits 0 (no matches) — the pure layers stay Flutter-free.

- [ ] **Step 3: Full suite**

Run: `flutter test`
Expected: all unit + widget tests PASS.

- [ ] **Step 4: Manual device sanity (the device-glitch guard)**

Run: `flutter run` on a phone-portrait, a phone-landscape, and a tablet-landscape
target (or emulators of each). Verify: tap-move glides, drag drop settles from
the release point, stock→waste slides+flips, a new deal staggers in, a win
flourishes, and nothing overflows or mis-positions on any form factor. Then flip
the OS "remove animations" accessibility setting and confirm every motion
becomes an instant snap with no layout change.

- [ ] **Step 5: Optional — run the golden-path integration suite**

Run: `flutter test integration_test`
Expected: the existing golden path still passes (now exercising real animation
timing).

---

## Self-Review

**Spec coverage:**
- Unified positioned board → Tasks 6-7. ✓
- Pure geometry (anti-glitch core) → Tasks 2-4. ✓
- Tap/double-tap move → Task 7. ✓
- Drop-settle → Task 10. ✓
- Stock→waste draw slide → Task 7 (offset change) + flip Task 9. ✓
- Deal → Task 11; Win → Task 12; both behind `SpecialSequence` seam → Tasks 11-12. ✓
- Reduce-motion (OS only) → Task 1 token + honored in Tasks 7, 9, 10, 11, 12. ✓
- Motion tokens in `ui/theme/` → Task 1. ✓
- Paint order during flight → Task 8. ✓
- One bounded measurement (drop-settle) → Task 10. ✓
- Testing: geometry unit tests (2-4), moving-set (8), snap==settle/converge (7), flip (9), deal (11), win (12), full-suite + boundary + device (13). ✓

**Placeholder scan:** `_almostWon()` in Task 12 defers its body to the existing
winnable builders in `auto_complete_test.dart`/`klondike_test.dart` — this is a
deliberate reuse instruction, not an invented API; the implementer copies a real
existing helper. No "TBD"/"handle edge cases"/testless steps remain.

**Type consistency:** `CardKey` / `CardPlacement` / `SlotPlacement` /
`BoardGeometry` (`cards`/`slots`/`dropTargets`/`cardSize`) are defined in Tasks
2-4 and consumed with the same names in Tasks 6-12. `GameMotion.resolve` /
`.move` / `.flip` / `.draw` / `.dealStagger` / `.moveCurve` used consistently.
`SpecialSequence` (`matches`/`delayFor`/`total`) and `DealSequence`/`WinSequence`
match between Tasks 11-12. The drop handler signature
`_drop(context, CardDragData, Offset, int)` is introduced in Task 6 and consumed
in Task 10.
