import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/card.dart';
import '../core/game_state.dart';
import '../core/pile.dart';
import '../ui/theme/game_motion.dart';
import 'board_geometry.dart';

/// The isolation seam for *set-piece* board animations driven by a piles-diff
/// — currently just the deal. The board asks a [SpecialSequence] whether the
/// current state transition is a set-piece; if so, it plays the sequence's
/// per-card *activation* schedule: each card waits at a fly-from origin until
/// its [delayFor] elapses, then reveals its real target so the existing
/// `AnimatedPositioned` tweens it into place. The whole point of the seam is
/// that a fancier deal later is a *new* [SpecialSequence] implementation —
/// `board.dart` and `board_geometry.dart` stay untouched.
///
/// Set-pieces engaged by a bloc *state type* rather than a piles-diff (the win
/// cascade, [CascadeSequence]) don't implement this interface — see its own
/// doc comment for why.
abstract interface class SpecialSequence {
  /// Whether the transition from [previous] (null on the very first render) to
  /// [next] is this set-piece.
  bool matches(GameState? previous, GameState next);

  /// How long [key] waits at the fly-from origin before it activates and glides
  /// to its resolved target.
  Duration delayFor(CardKey key, BoardGeometry geometry);

  /// The controller duration for the whole set-piece: long enough that the last
  /// card has both activated and finished its flight. Sized from [geometry] so a
  /// small deal doesn't leave the controller running a long empty tail past the
  /// last card.
  Duration totalFor(BoardGeometry geometry);
}

/// A modest staggered deal: cards start at the stock origin and reveal their
/// real target one after another on a fixed [GameMotion.dealStagger] cadence,
/// walking [BoardGeometry.cards] in paint order (pile-major, bottom-to-top).
class DealSequence implements SpecialSequence {
  const DealSequence();

  @override
  bool matches(GameState? previous, GameState next) {
    if (previous == null) {
      return true;
    }
    final Set<CardKey> before = _allCardKeys(previous);
    final List<CardKey> dealt = _dealtCardKeys(next);
    if (dealt.isEmpty) {
      return false;
    }
    for (final CardKey key in dealt) {
      if (before.contains(key)) {
        return false;
      }
    }
    return true;
  }

  @override
  Duration delayFor(CardKey key, BoardGeometry geometry) {
    final int index = geometry.cards.indexWhere(
      (CardPlacement placement) => placement.key == key,
    );
    if (index < 0) {
      return Duration.zero;
    }
    return GameMotion.dealStagger * index;
  }

  @override
  Duration totalFor(BoardGeometry geometry) {
    // The last card in paint order activates at dealStagger*(count-1); add one
    // move so the controller outlives its flight. Only the cards actually placed
    // in the geometry animate (a deep stock shows a single top card), so this is
    // usually far under a full 52-card deck.
    final int count = math.max(geometry.cards.length, 1);
    return GameMotion.dealStagger * (count - 1) + GameMotion.move;
  }

  /// Every card key anywhere in [state].
  Set<CardKey> _allCardKeys(GameState state) {
    final Set<CardKey> keys = <CardKey>{};
    for (final Pile pile in state.piles) {
      for (final Card card in pile.cards) {
        keys.add(CardKey.of(card));
      }
    }
    return keys;
  }

  /// The card keys in [state]'s tableau and stock piles — the cards a fresh
  /// deal lays out.
  List<CardKey> _dealtCardKeys(GameState state) {
    final List<CardKey> keys = <CardKey>[];
    for (final Pile pile in state.piles) {
      if (pile.kind == PileKind.tableau || pile.kind == PileKind.stock) {
        for (final Card card in pile.cards) {
          keys.add(CardKey.of(card));
        }
      }
    }
    return keys;
  }
}

/// The win cascade: once the game is won, the cards resting in the foundation
/// piles peel off from the top down and bounce around the board forever — a
/// reward animation the player can linger on for as long as they like rather
/// than a one-shot effect that ends on its own. It replaces the modest
/// foundation pulse this seam used to play; unlike that pulse it needs every
/// card in each foundation pile individually placed (not just the top), which
/// `board.dart` gets via `BoardGeometry.resolve(revealFoundationStacks:
/// true)`.
///
/// It is not a [SpecialSequence]: like the pulse before it, engagement is
/// driven by the bloc reporting a `GameWon` state, not a piles-diff, and its
/// per-card schedule is a property of the [GameState] alone (which foundation
/// pile a card sits in, how many cards are stacked above it) rather than of a
/// resolved [BoardGeometry]. It also has no fixed duration — see
/// `GameMotion.winCascadeMinimumBeforeDismiss` for the player-facing lifecycle
/// (a minimum look, then tap-anywhere-to-continue).
///
/// All four foundations peel off together, rank by rank from the top (usually
/// the King) down to the Ace, so same-rank cards across foundations fly in the
/// same beat — the familiar rhythm of the genre's classic win animation. Each
/// card then travels in a straight line at a constant speed and bounces
/// elastically off all four edges of the board — never losing speed, so it
/// keeps bouncing corner to corner indefinitely rather than settling. The
/// launch direction is derived from the card's own identity (so it's stable
/// and reproducible) biased away from whichever edge of the board its
/// foundation started closest to (see [_xSign]) — deliberately a property of
/// where a foundation actually renders, not of which pile it is, since the
/// foundations sit in a horizontal row in portrait but a vertical column (all
/// near one edge) in the tablet-landscape layout.
class CascadeSequence {
  const CascadeSequence();

  /// Delay between successive ranks peeling off.
  static const Duration stagger = Duration(milliseconds: 45);

  /// Constant travel speed, in logical pixels per second, on each axis'
  /// resultant vector. Never decays — a lossless bounce keeps this speed
  /// forever, which is what lets the cascade run indefinitely instead of
  /// settling.
  static const double _speed = 300;

  /// The launch angle (degrees, from the horizontal) is drawn from this range
  /// per card, keeping every trajectory visibly diagonal — never dead
  /// horizontal or vertical — so cards actually sweep both axes and clip every
  /// corner instead of just pacing along one wall. Deliberately narrow: a
  /// tight spread keeps cards moving in roughly the same direction at first,
  /// so the deck reads as one cascading group for longer before it spreads
  /// out across the whole board.
  static const double _minAngleDeg = 38;
  static const double _angleSpreadDeg = 14;

  /// Spin rate, in radians per second, applied for as long as a card is
  /// bouncing — a continuous tumble rather than a single small tilt. Never
  /// capped, matching the endless bounce.
  static const double _spinSpeed = 2.2;

  /// How long [key] waits before it starts bouncing: zero for the top card of
  /// its foundation pile, one more [stagger] for each card beneath it.
  /// [Duration.zero] (inert — [offsetAt] never moves it) if [key] isn't
  /// currently sitting in a foundation pile.
  Duration delayFor(CardKey key, GameState game) {
    final int step = _stepFor(key, game);
    return step < 0 ? Duration.zero : stagger * step;
  }

  /// The board-local translation to apply to [key] at [elapsed] into the
  /// whole cascade: [Offset.zero] until its own [delayFor] elapses, then a
  /// lossless elastic bounce off all four edges of [boardSize], starting from
  /// [origin] and never losing speed or settling.
  Offset offsetAt(
    CardKey key,
    Duration elapsed,
    GameState game,
    Rect origin,
    Size boardSize,
  ) {
    final Duration delay = delayFor(key, game);
    if (elapsed <= delay) {
      return Offset.zero;
    }
    final double t = (elapsed - delay).inMicroseconds / 1e6;
    final Offset velocity = _velocityFor(key, origin, boardSize.width);
    final double spanX = math.max(0.0, boardSize.width - origin.width);
    final double spanY = math.max(0.0, boardSize.height - origin.height);
    final double dx = _bounce(velocity.dx, t, -origin.left, spanX);
    final double dy = _bounce(velocity.dy, t, -origin.top, spanY);
    return Offset(dx, dy);
  }

  /// A continuous tumble to accompany the bounce: `0.0` at the moment [key]
  /// activates, growing steadily (never capped — a bouncing card keeps
  /// spinning for as long as it's in view) in the direction of [origin]'s
  /// [_xSign].
  double rotationAt(
    CardKey key,
    Duration elapsed,
    GameState game,
    Rect origin,
    Size boardSize,
  ) {
    final Duration delay = delayFor(key, game);
    if (elapsed <= delay) {
      return 0.0;
    }
    final double t = (elapsed - delay).inMicroseconds / 1e6;
    return _xSign(origin, boardSize.width) * _spinSpeed * t;
  }

  /// The position (in the same board-local coordinate [origin]'s edge sits
  /// in) at [t] seconds of a point that starts at the origin's edge, moves at
  /// constant speed [v], and reflects losslessly off the two walls
  /// `lo` and `lo + span` forever — the classic "unfold and fold back" trick
  /// for elastic 1-D bouncing, computed in closed form so it stays cheap and
  /// exact at any [t], however large.
  double _bounce(double v, double t, double lo, double span) {
    if (span <= 0) {
      return lo;
    }
    final double raw = -lo + v * t;
    double wrapped = raw % (2 * span);
    if (wrapped < 0) {
      wrapped += 2 * span;
    }
    final double folded = wrapped <= span ? wrapped : 2 * span - wrapped;
    return lo + folded;
  }

  /// The constant launch velocity for [key]: a fixed [_speed] split into an
  /// x/y pair by an angle drawn deterministically from [key]'s identity (so
  /// every card gets a distinct, reproducible diagonal trajectory), with the
  /// horizontal sign biased by [_xSign] so a card first heads away from
  /// whichever edge [origin] is already closest to.
  Offset _velocityFor(CardKey key, Rect origin, double boardWidth) {
    final int seed = key.hashCode & 0x7fffffff;
    final double angleDeg =
        _minAngleDeg + (seed % 1000) / 1000 * _angleSpreadDeg;
    final double angle = angleDeg * math.pi / 180;
    final double xSign = _xSign(origin, boardWidth);
    return Offset(xSign * _speed * math.cos(angle), _speed * math.sin(angle));
  }

  /// How many cards sit above [key] in its own foundation pile (`0` for the
  /// top card), or `-1` if [key] isn't currently a foundation card.
  int _stepFor(CardKey key, GameState game) {
    for (final Pile pile in game.piles) {
      if (pile.kind != PileKind.foundation) {
        continue;
      }
      for (int i = 0; i < pile.length; i++) {
        if (CardKey.of(pile.cards[i]) == key) {
          return pile.length - 1 - i;
        }
      }
    }
    return -1;
  }

  /// `1` (heads right) if [origin] sits left-of-centre on a board of width
  /// [boardWidth], `-1` (heads left) otherwise — i.e. away from whichever
  /// edge [origin] already sits closest to, so every card gets roughly the
  /// same amount of width to bounce across regardless of where its foundation
  /// happens to render in the current layout. A pile-based lane would put a
  /// foundation that's already hard against, say, the right edge (as every
  /// foundation is in the tablet-landscape column layout) one flick from an
  /// immediate bounce back.
  double _xSign(Rect origin, double boardWidth) =>
      origin.center.dx < boardWidth / 2 ? 1.0 : -1.0;
}

/// The deal fly-from point: the bottom-centre of the board, as a card-sized
/// slot's top-left in board-local coordinates. Cards fly up and out from the
/// player's edge, like dealing from a hand. Falls back to [Offset.zero] only for
/// a degenerate zero-size board so it can never crash.
Offset dealOriginOf(BoardGeometry geometry) {
  final Size card = geometry.cardSize;
  final Size board = geometry.size;
  if (board.isEmpty) {
    return Offset.zero;
  }
  final double dx = (board.width - card.width) / 2;
  final double dy = board.height - card.height;
  return Offset(dx, dy);
}
