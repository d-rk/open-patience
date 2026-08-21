# Card Move Animations — Design

**Date:** 2026-08-21
**Status:** Approved design, pre-implementation
**Framework:** Flutter (latest stable)
**Language:** Dart

## Purpose

Cards currently teleport. When the `GameBloc` emits a new `GameState`, the
whole board rebuilds and each card snaps to its new spot one frame later.
This spec adds smooth motion when cards move — a tap/double-tap move, a
drag drop settling into place, a stock→waste draw, and the set-piece deal
and win flourishes.

The overriding constraint from the request: **no glitches that appear only
on certain devices.** The design achieves this by deriving every card's
resting position from a single pure, unit-testable geometry function with
no runtime coordinate measurement — so "does the card land in the right
place at this screen size" is a millisecond headless test, not a device
gamble.

## Scope

**Animated (this pass)**
- Tap / double-tap moves — card glides to its legal destination.
- Drop-settle — after a drag is accepted, the card eases from the release
  point into its final slot.
- Stock → waste draw — the drawn card slides to the waste; face-down→
  face-up cards flip.
- Deal — a modest staggered slide-out of the initial deal.
- Win — a modest flourish.

**Reduce motion**
- Honor the OS setting (`MediaQuery.disableAnimations`) only. No in-app
  toggle. When reduce-motion is on, cards snap instantly — identical to
  today's behavior. This is also the path widget tests use.

**Explicitly deferred**
- A full arcade "bouncing cards" win cascade. The set-piece animations sit
  behind an isolation seam (see `SpecialSequence` below) so a fancier deal
  or win can be plugged in later by adding one file, without touching the
  core board or geometry.

## Chosen approach: unified positioned board

Rejected alternative: an `Overlay` "flight" layer over today's Flex layout.
It animates a moved card by measuring source and destination global rects
via `GlobalKey`/`RenderBox` and flying a ghost card between them. That makes
the *entire* flight path depend on post-frame measurement in global
coordinates, whose timing and rounding vary with orientation, safe-area
insets, and rebuild races — precisely the device-specific glitch class the
request rules out. Rejected on that basis.

Chosen: replace the per-pile Flex + local-`Stack` rendering with **one
board-level `Stack`** in which every card is an `AnimatedPositioned` at an
absolute offset, keyed by its identity `ValueKey(suit, rank)`.

- A card's screen position comes entirely from a pure geometry function
  (below). No `RenderBox` reads for resting positions.
- On each new `GameState`, the board recomputes every card's target offset.
  Because each card keeps a stable key across rebuilds, `AnimatedPositioned`
  interpolates old→new automatically. Cards that didn't move don't animate.
- **All four move-type effects ride this one path.** A tap-move, a stock→
  waste slide, and a deal step are each just "this card's target offset
  changed." One mechanism instead of four fragile special cases — the
  property that makes it robust.

## Architecture

Dependency direction is unchanged; all new logic respects the existing
`ui/ → core`, `presentation/ → core` boundaries. The geometry layer is pure
Dart (zero Flutter imports) and lives beside `board_metrics.dart`.

### Pure geometry layer (the anti-glitch core)

Extend `lib/presentation/board_metrics.dart` into a full board-geometry
resolver (keeping the existing `BoardMetrics` sizing math it already holds):

```
BoardGeometry.resolve(state, width, height, isLandscape, shortestSide, …) →
  {
    cardRect(suit, rank) : Rect,          // every card's offset + size
    placeholderRects     : List<Rect>,    // empty-slot markers, per pile
    dropTargetRects      : Map<int, Rect> // hit region per pile index
  }
```

- Today Flex computes pile origins implicitly. This moves that arithmetic
  into pure Dart — the same discipline `BoardMetrics` already applies to
  card *size*. It computes pile origins for all three existing layouts
  (portrait / phone-landscape / tablet-landscape). **No layout behavior
  changes** — the same arrangement, expressed as math.
- Must reproduce today's rules exactly: fit-to-height card sizing, the
  `minCardWidth` clamp, `_fanGap` compression (`faceUpGap` /
  `faceDownGap = faceUpGap * 0.5`), the waste horizontal fan
  (`_wasteFanStep`, `wasteVisibleCount`), and the tablet side-column split.

Pure Dart is non-negotiable here: it is what makes the resting layout
assertable headlessly and independent of device timing.

### Widgets (`lib/presentation/`)

- **`board.dart`** — becomes a thin `StatefulWidget`. Builds the `Stack` of
  `AnimatedPositioned` (keyed) → `CardView` / placeholders from the geometry
  model. Holds the *previous* `GameState` to compute the moving set (cards
  whose pile or index changed) for paint order. Keeps all gesture wiring
  (tap / double-tap / drop → the same `GameEvent`s). Reads
  `MediaQuery.disableAnimations`; when true, animation duration is
  `Duration.zero` (instant snap == today).
- **`pile_view.dart`** — shrinks. Fan/stack positioning math moves into the
  geometry layer; what remains is the positioned drop-target region and the
  empty-slot placeholder (foundation / park / stock markers). The
  `DragScope` dimming behavior for the in-flight stack is preserved.
- **`card_view.dart`** — `Draggable` / tap wiring unchanged. Gains a small
  flip animation (a `TweenAnimationBuilder` rotationY) that fires when its
  `faceUp` changes. This is the only per-card stateful bit. Honors
  reduce-motion.
- **`drag_scope.dart`** — unchanged.

### Paint order during flight

A card flying across the board must paint above the piles it crosses. The
board keeps a *moving set* (diff of previous vs current state) and appends
those cards last in the `Stack` children so they paint on top. A moving
card is released from the set via `AnimatedPositioned.onEnd` — event-driven,
no wall-clock timer, resume-safe. At rest a moved card is the top of its
destination pile, and piles do not overlap spatially, so normal paint order
is correct once released.

### Motion tokens (`lib/ui/theme/`)

A new `lib/ui/theme/game_motion.dart` holds all durations and curves — no
widget hardcodes a `Duration` or `Curve`, per the design-language rule that
shared visual tokens live in `ui/theme/`. Proposed defaults: moves ~220ms
`easeOutCubic`; flip ~260ms; draw ~200ms; deal per-card stagger ~40ms.

### Set-piece isolation seam

Deal and win go behind a small interface so they are pluggable and isolated
from the core move mechanism:

```
abstract interface class SpecialSequence {
  /// Given the resolved geometry, emit the timed target-offset overrides
  /// the board plays out for this set-piece.
  Stream<BoardFrame> frames(BoardGeometry geometry, GameState state);
}
```

Concrete `DealSequence` and `WinSequence` implement modest versions built on
the same `AnimatedPositioned` targets. Swapping in a fancier deal or a full
arcade win cascade later means adding one `SpecialSequence` implementation —
`board.dart` and the geometry layer are untouched. (Exact seam shape to be
finalized during planning; the requirement is that the core board is blind
to which sequence is plugged in.)

## The two controlled wrinkles

1. **Drop-settle start point.** `AnimatedPositioned` would animate a dropped
   card from its *source* pile, but the eye last saw it under the finger near
   the destination — animating from source would read as a teleport-back. To
   settle from the release point the board makes **one** coordinate
   conversion: `Draggable.onDragEnd` gives a global offset, converted through
   the *board container's own* `RenderBox` (a single, stable measurement —
   not per-card, not per-pile) into board-local space, used as the
   animation's start. This is bounded: the settle spans a short distance, so
   any small error is a few pixels, unlike Approach B where the whole flight
   path depends on two measured rects. This is the only measurement in the
   system and is isolated to the settle.

2. **Paint order during flight** — handled by the moving-set + `onEnd`
   release above.

## Data flow

Unchanged from today. Input → widget dispatches a `GameEvent` → `GameBloc`
calls `GameState.tryMove()` → rules validate → state mutates → bloc emits →
board rebuilds. The only addition is on the render side: the rebuild now
animates to the new geometry instead of snapping. The `core/` and
`presentation/bloc/` layers are not touched by this feature.

## Testing strategy

TDD throughout (RED → GREEN → REFACTOR). The bulk is headless unit tests on
the pure geometry — that is where the anti-glitch guarantee lives.

**Unit (headless, milliseconds)**
- Geometry: exact `cardRect` / `placeholderRects` / `dropTargetRects` for
  representative states across all three layouts and edge sizes — the
  `minCardWidth` clamp, the longest tableau fan, empty piles, the waste fan,
  the tablet side-column split. Assert the resolver reproduces today's
  positions.
- Moving-set diff: given previous and next `GameState`, assert which cards
  are reported as moved.

**Widget (`test/widget/`)**
- All existing happy-path tests stay green — this is a behavior-preserving
  rewrite of rendering and input wiring.
- `disableAnimations = true`: after one pump, cards are at their correct
  final positions (snap path == old behavior).
- Animations on: after `pumpAndSettle`, the layout equals the snap layout —
  proves the animation converges to the correct rest state with no drift.
- Draw + flip: after a stock draw settles, the waste's top card is face-up.
- Deal: after a new deal settles, all cards render at their tableau/stock
  positions.

**`integration_test` (less frequent)**
- Keep the existing golden-path flow green on a real device/emulator; it now
  also exercises real animation timing.

## Key design decisions

1. **Pure geometry over runtime measurement.** The resting layout is a
   deterministic function of state + size, testable headlessly. This is the
   direct answer to "no device-specific glitches."
2. **One mechanism for all move types.** `AnimatedPositioned` on keyed cards
   handles moves, draws, and deal steps uniformly; fewer special cases means
   fewer places for a device-specific bug to hide.
3. **Reduce-motion == today's snap.** Zero-duration animation reuses the
   exact current behavior, giving both accessibility and a simple test path.
4. **Set-pieces behind a seam.** Deal/win are isolated so they can be
   replaced without touching the core.
5. **Exactly one bounded measurement.** Only the drop-settle start point
   reads a `RenderBox`, and only the board container's, over a short
   distance.

## Additional libraries

None expected. Everything uses Flutter's built-in `AnimatedPositioned`,
`TweenAnimationBuilder`, and `MediaQuery`.

## Files touched (indicative)

```
lib/presentation/board_metrics.dart      # → full BoardGeometry resolver (pure)
lib/presentation/board.dart              # → StatefulWidget, unified Stack
lib/presentation/pile_view.dart          # → drop-target + placeholder only
lib/presentation/card_view.dart          # + flip animation
lib/ui/theme/game_motion.dart            # new: motion tokens
lib/presentation/board_sequence.dart     # new: SpecialSequence seam + deal/win
test/unit/board_geometry_test.dart       # new: geometry math
test/unit/board_moving_set_test.dart     # new: move diff
test/widget/board_animation_test.dart    # new: snap == settle, flip, deal
```
