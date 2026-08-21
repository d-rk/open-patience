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

  ValueKey<String> get widgetKey =>
      ValueKey<String>('card-${suit.index}-$rank');

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
