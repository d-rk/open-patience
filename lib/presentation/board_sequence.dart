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
/// piles peel off from the top down and tumble off the bottom of the board —
/// the classic solitaire "cascade" a completed game deserves. It replaces the
/// modest foundation pulse this seam used to play; unlike that pulse it needs
/// every card in each foundation pile individually placed (not just the top),
/// which `board.dart` gets via `BoardGeometry.resolve(revealFoundationStacks:
/// true)`.
///
/// It is not a [SpecialSequence]: like the pulse before it, engagement is
/// driven by the bloc reporting a `GameWon` state, not a piles-diff, and its
/// per-card schedule is a property of the [GameState] alone (which foundation
/// pile a card sits in, how many cards are stacked above it) rather than of a
/// resolved [BoardGeometry] — so a caller only needs a board size for the fall
/// distance, never a full geometry resolve.
///
/// All four foundations peel off together, rank by rank from the top (usually
/// the King) down to the Ace, so same-rank cards across foundations fly in the
/// same beat — the familiar rhythm of the genre's classic win animation.
class CascadeSequence {
  const CascadeSequence();

  /// Delay between successive ranks peeling off.
  static const Duration stagger = Duration(milliseconds: 45);

  /// How long a single card's tumble takes, from the moment it activates to
  /// the moment it is fully clear of the board.
  static const Duration flight = Duration(milliseconds: 900);

  /// The controller duration for the whole cascade: long enough that even the
  /// last (deepest-buried) card both activates and finishes its flight.
  Duration totalFor(GameState game) => stagger * _maxStep(game) + flight;

  /// How long [key] waits before it starts tumbling: zero for the top card of
  /// its foundation pile, one more [stagger] for each card beneath it.
  /// [Duration.zero] (inert — [offsetAt] never moves it) if [key] isn't
  /// currently sitting in a foundation pile.
  Duration delayFor(CardKey key, GameState game) {
    final int step = _stepFor(key, game);
    return step < 0 ? Duration.zero : stagger * step;
  }

  /// The board-local translation to apply to [key] at [elapsed] into the whole
  /// cascade: [Offset.zero] until its own [delayFor] elapses, then an easing
  /// fall guaranteed to clear [boardSize]'s height, with a small per-card
  /// sideways drift. Holds at the fully-exited offset once its own [flight]
  /// completes, so a settled card never snaps back.
  Offset offsetAt(
    CardKey key,
    Duration elapsed,
    GameState game,
    Size boardSize,
  ) {
    final double t = _progress(key, elapsed, game);
    if (t <= 0.0) {
      return Offset.zero;
    }
    final double fall = boardSize.height * 1.15 * Curves.easeIn.transform(t);
    final double drift = _driftFor(key) * Curves.easeOut.transform(t);
    return Offset(drift, fall);
  }

  /// A gentle tumble to accompany the fall, purely cosmetic: `0.0` until [key]
  /// activates, easing up to a small fixed tilt (radians) by the time it
  /// exits — a tumble, not a pinwheel.
  double rotationAt(CardKey key, Duration elapsed, GameState game) {
    final double t = _progress(key, elapsed, game);
    return t <= 0.0 ? 0.0 : _spinFor(key) * Curves.easeOut.transform(t);
  }

  /// This card's `[0, 1]` progress through its own flight at [elapsed] into
  /// the whole cascade: `0` before its [delayFor] elapses, `1` once its own
  /// [flight] completes.
  double _progress(CardKey key, Duration elapsed, GameState game) {
    final Duration delay = delayFor(key, game);
    if (elapsed <= delay) {
      return 0.0;
    }
    return ((elapsed - delay).inMicroseconds / flight.inMicroseconds).clamp(
      0.0,
      1.0,
    );
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

  /// A small, deterministic per-card sideways drift (logical pixels) so the
  /// cascade fans out instead of falling as one uniform curtain. Derived from
  /// the card's own identity rather than [math.Random] so a replay of the same
  /// win — or a test — always tumbles the same way.
  double _driftFor(CardKey key) {
    const List<double> perSuitLane = <double>[-1.5, -0.5, 0.5, 1.5];
    final double lane = perSuitLane[key.suit.index % perSuitLane.length];
    final double jitter = (key.rank * 37) % 11 - 5; // -5..5
    return lane * 60.0 + jitter * 3.0;
  }

  /// A small, deterministic per-card tilt (radians) for the tumble.
  double _spinFor(CardKey key) {
    final double turns = 0.3 + (key.rank % 4) * 0.08;
    return key.rank.isEven ? turns : -turns;
  }
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
