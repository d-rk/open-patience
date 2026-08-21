import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/card.dart';
import '../core/game_state.dart';
import '../core/pile.dart';
import '../ui/theme/game_motion.dart';
import 'board_geometry.dart';

/// The isolation seam for *set-piece* board animations (a deal, a win flourish,
/// …). The board asks a [SpecialSequence] whether the current state transition
/// is a set-piece; if so, it plays the sequence's per-card *activation*
/// schedule: each card waits at a fly-from origin until its [delayFor] elapses,
/// then reveals its real target so the existing `AnimatedPositioned` tweens it
/// into place. The whole point of the seam is that a fancier deal or a win
/// animation later is a *new* [SpecialSequence] implementation — `board.dart`
/// and `board_geometry.dart` stay untouched.
abstract interface class SpecialSequence {
  /// Whether the transition from [previous] (null on the very first render) to
  /// [next] is this set-piece.
  bool matches(GameState? previous, GameState next);

  /// How long [key] waits at the fly-from origin before it activates and glides
  /// to its resolved target.
  Duration delayFor(CardKey key, BoardGeometry geometry);

  /// The controller duration for the whole set-piece: long enough that the last
  /// card has both activated and finished its flight.
  Duration get total;
}

/// A modest staggered deal: cards start at the stock origin and reveal their
/// real target one after another on a fixed [GameMotion.dealStagger] cadence,
/// walking [BoardGeometry.cards] in paint order (pile-major, bottom-to-top).
class DealSequence implements SpecialSequence {
  const DealSequence();

  /// Upper bound on the cards a single deal can involve (a full deck). Used to
  /// size [total] without needing the geometry, so the controller always
  /// outlives the last card's flight regardless of the variant.
  static const int _maxDealCards = 52;

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
  Duration get total =>
      GameMotion.dealStagger * (_maxDealCards - 1) + GameMotion.move;

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

/// A modest win flourish: a brief, symmetric scale pulse of the foundation
/// cards when the game is won. Kept deliberately small and isolated behind the
/// [SpecialSequence] seam so a fuller arcade cascade can later replace it by
/// swapping this one class (see `_winSequence` in `board.dart`).
///
/// Unlike [DealSequence], its engagement is *not* driven by a piles-diff: the
/// board plays it when the bloc emits a `GameWon` state — the win-ness the
/// engine has already decided. So [matches] is intentionally conservative and
/// unused for engagement (it always returns `false`), and [delayFor] is unused
/// too: every foundation card pulses together, so it returns [Duration.zero].
class WinSequence implements SpecialSequence {
  const WinSequence();

  /// The peak extra scale at the pulse's midpoint (an 8% swell).
  static const double _amplitude = 0.08;

  @override
  bool matches(GameState? previous, GameState next) => false;

  @override
  Duration delayFor(CardKey key, BoardGeometry geometry) => Duration.zero;

  @override
  Duration get total => const Duration(milliseconds: 600);

  /// The foundation-card scale at [elapsed] into the flourish: a symmetric ease
  /// pulse that starts at 1.0, swells to `1 + _amplitude` (~1.08) at the
  /// midpoint, and eases back to 1.0 at [total]. Flat at 1.0 before the start
  /// and once the flourish is over, so it is safe to sample at any time.
  double pulseAt(Duration elapsed) {
    final double t = elapsed.inMicroseconds / total.inMicroseconds;
    if (t <= 0.0 || t >= 1.0) {
      return 1.0;
    }
    return 1.0 + _amplitude * math.sin(math.pi * t);
  }
}

/// The deal fly-from point: the stock slot's top-left in board-local
/// coordinates. Prefers an empty stock's [SlotPlacement]; when the stock holds
/// cards it has no slot, so falls back to the first card placement (paint order
/// is pile-major with the stock/waste region first, so this is the stock's top
/// card). Falls back to [Offset.zero] for a variant with neither (e.g. an
/// empty board) so it can never crash.
Offset dealOriginOf(BoardGeometry geometry) {
  for (final SlotPlacement slot in geometry.slots) {
    if (slot.kind == PileKind.stock) {
      return slot.rect.topLeft;
    }
  }
  if (geometry.cards.isNotEmpty) {
    return geometry.cards.first.rect.topLeft;
  }
  return Offset.zero;
}
