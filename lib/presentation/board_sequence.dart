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
/// piles peel off from the top down and bounce off the bottom of the board —
/// the classic solitaire "cascade" (à la the Windows 3.1/95 win animation),
/// not a one-way slide off the screen. It replaces the modest foundation
/// pulse this seam used to play; unlike that pulse it needs every card in
/// each foundation pile individually placed (not just the top), which
/// `board.dart` gets via `BoardGeometry.resolve(revealFoundationStacks:
/// true)`.
///
/// It is not a [SpecialSequence]: like the pulse before it, engagement is
/// driven by the bloc reporting a `GameWon` state, not a piles-diff, and its
/// per-card schedule is a property of the [GameState] alone (which foundation
/// pile a card sits in, how many cards are stacked above it) rather than of a
/// resolved [BoardGeometry].
///
/// All four foundations peel off together, rank by rank from the top (usually
/// the King) down to the Ace, so same-rank cards across foundations fly in the
/// same beat — the familiar rhythm of the genre's classic win animation. Each
/// card then falls under a small gravity simulation, bounces off the board's
/// bottom edge a few times with diminishing height, and drifts sideways off
/// whichever edge of the board it started furthest from (see [_laneFor]) —
/// deliberately a property of where a foundation actually renders, not of
/// which pile it is, since the foundations sit in a horizontal row in
/// portrait but a vertical column (all near one edge) in the tablet-landscape
/// layout.
class CascadeSequence {
  const CascadeSequence();

  /// Delay between successive ranks peeling off.
  static const Duration stagger = Duration(milliseconds: 45);

  /// How long a single card's fall takes, from the moment it activates to the
  /// moment it's settled at the floor and mostly drifted clear of the board.
  static const Duration flight = Duration(milliseconds: 1600);

  /// Downward acceleration, in logical pixels per second squared. Lower than
  /// real gravity so the fall and each bounce hang in the air a beat longer —
  /// tuned (with [_launchSpeed] and [_restitution]) for a slower, floatier
  /// cascade with two or three clearly-visible bounces within [flight].
  static const double _gravity = 5000;

  /// The upward "pop" a card launches with, in pixels per second — sells the
  /// peel-off as a flick rather than a drop.
  static const double _launchSpeed = 650;

  /// Fraction of a bounce's impact speed kept as its next rise: energy lost
  /// per bounce, so each one is visibly lower than the last. High enough that
  /// the first rebound is a real bounce, not a token hop off the floor.
  static const double _restitution = 0.65;

  /// Bounces allowed before a card is treated as settled at the floor.
  static const int _maxBounces = 4;

  /// Fraction of the board's width a card crosses sideways over one [flight]
  /// — tuned so it visibly clears the board edge, not just drifts partway.
  static const double _driftFraction = 0.85;

  /// Spin rate, in radians per second, applied for as long as a card is
  /// falling — a continuous tumble rather than a single small tilt. Slower
  /// than the fall/bounce rate so a longer [flight] doesn't read as frantic.
  static const double _spinSpeed = 2.2;

  /// The controller duration for the whole cascade: long enough that even the
  /// last (deepest-buried) card both activates and finishes its flight.
  Duration totalFor(GameState game) => stagger * _maxStep(game) + flight;

  /// How long [key] waits before it starts falling: zero for the top card of
  /// its foundation pile, one more [stagger] for each card beneath it.
  /// [Duration.zero] (inert — [offsetAt] never moves it) if [key] isn't
  /// currently sitting in a foundation pile.
  Duration delayFor(CardKey key, GameState game) {
    final int step = _stepFor(key, game);
    return step < 0 ? Duration.zero : stagger * step;
  }

  /// The board-local translation to apply to [key] at [elapsed] into the
  /// whole cascade: [Offset.zero] until its own [delayFor] elapses, then a
  /// bouncing fall from [origin] toward [boardSize]'s bottom edge, plus a
  /// sideways drift whose direction depends on [origin]'s position within
  /// [boardSize] (see [_laneFor]). The vertical motion settles at the floor
  /// once its bounces are spent; the horizontal drift keeps going, carrying a
  /// settled card off the side of the board rather than leaving it resting
  /// mid-floor forever.
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
    final double floor = math.max(0.0, boardSize.height - origin.bottom);
    final double dy = _bounceFall(t, floor);
    final double flightSeconds = flight.inMicroseconds / 1e6;
    final double driftSpeed = boardSize.width * _driftFraction / flightSeconds;
    final double dx = _laneFor(origin, boardSize.width) * driftSpeed * t;
    return Offset(dx, dy);
  }

  /// A continuous tumble to accompany the fall: `0.0` at the moment [key]
  /// activates, growing steadily (never capped — a bouncing card keeps
  /// spinning for as long as it's in view) in the direction of [origin]'s
  /// [_laneFor].
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
    return _laneFor(origin, boardSize.width) * _spinSpeed * t;
  }

  /// The vertical fall distance at [t] seconds into a card's own flight: a
  /// small-gravity simulation that starts at `0` with an upward [_launchSpeed]
  /// pop, accelerates down under [_gravity], and bounces off [floor] up to
  /// [_maxBounces] times — each bounce keeping [_restitution] of its impact
  /// speed — before settling exactly at [floor].
  double _bounceFall(double t, double floor) {
    if (floor <= 0) {
      return 0.0;
    }
    double y = 0.0;
    double vy = -_launchSpeed;
    double remaining = t;
    for (int bounce = 0; bounce < _maxBounces; bounce++) {
      final double timeToImpact = _timeToImpact(vy, y, floor);
      if (remaining < timeToImpact) {
        return y + vy * remaining + 0.5 * _gravity * remaining * remaining;
      }
      remaining -= timeToImpact;
      vy = -(vy + _gravity * timeToImpact) * _restitution;
      y = floor;
    }
    return floor;
  }

  /// The positive time (seconds) for a card starting at height [y0] with
  /// vertical speed [vy0] to reach [floor] under [_gravity]: the positive root
  /// of `0.5·g·s² + vy0·s + (y0 − floor) = 0`.
  double _timeToImpact(double vy0, double y0, double floor) {
    const double a = 0.5 * _gravity;
    final double b = vy0;
    final double c = y0 - floor;
    final double discriminant = b * b - 4 * a * c;
    return (-b + math.sqrt(discriminant)) / (2 * a);
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

  /// The deepest foundation pile's top-card step, so [totalFor] sizes the
  /// controller for the slowest-to-activate card.
  int _maxStep(GameState game) {
    int maxLength = 0;
    for (final Pile pile in game.piles) {
      if (pile.kind == PileKind.foundation) {
        maxLength = math.max(maxLength, pile.length);
      }
    }
    return maxLength == 0 ? 0 : maxLength - 1;
  }

  /// `1` (drifts right) if [origin] sits left-of-centre on a board of width
  /// [boardWidth], `-1` (drifts left) otherwise — i.e. away from whichever
  /// edge [origin] already sits closest to, so every card gets roughly the
  /// same amount of width to fall across regardless of where its foundation
  /// happens to render in the current layout. A pile-based lane would put a
  /// foundation that's already hard against, say, the right edge (as every
  /// foundation is in the tablet-landscape column layout) one flick from
  /// leaving the board.
  double _laneFor(Rect origin, double boardWidth) =>
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
