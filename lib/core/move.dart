import 'package:equatable/equatable.dart';

import 'card.dart';

/// A reversible description of moving one or more cards between piles — the
/// unit of undo/redo.
///
/// Invariant that makes reversal exact: [cards] lists the moved cards in the
/// **same order they sat on the source pile** (bottom-most of the group
/// first), but in their **destination orientation**. [GameState] applies a
/// move by removing that many cards from [fromPile] and appending [cards] to
/// [toPile]; it reverts by removing them from [toPile] and appending them back
/// to [fromPile] in source orientation. Two flags capture the only side
/// effects that a plain list move cannot:
///
/// * [flipMovedCards] — the moved cards changed orientation between source and
///   destination (a Klondike stock->waste draw, or a waste->stock recycle).
///   On revert their orientation is inverted to restore the source exactly.
/// * [flipUnderCard] — removing the cards exposed a face-down card on a
///   tableau source which was auto-flipped face up. Set by [GameState] when it
///   applies the move; on revert that exposed card is turned back face down.
class Move extends Equatable {
  const Move({
    required this.fromPile,
    required this.toPile,
    required this.cards,
    this.flipMovedCards = false,
    this.flipUnderCard = false,
  });

  factory Move.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawCards = json['cards'] as List<dynamic>;
    return Move(
      fromPile: json['from'] as int,
      toPile: json['to'] as int,
      cards: rawCards
          .map((dynamic c) => Card.fromJson(c as Map<String, dynamic>))
          .toList(),
      flipMovedCards: json['fm'] as bool,
      flipUnderCard: json['fu'] as bool,
    );
  }

  final int fromPile;
  final int toPile;
  final List<Card> cards;
  final bool flipMovedCards;
  final bool flipUnderCard;

  int get cardCount => cards.length;

  Move copyWith({bool? flipMovedCards, bool? flipUnderCard}) {
    return Move(
      fromPile: fromPile,
      toPile: toPile,
      cards: cards,
      flipMovedCards: flipMovedCards ?? this.flipMovedCards,
      flipUnderCard: flipUnderCard ?? this.flipUnderCard,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'from': fromPile,
    'to': toPile,
    'cards': cards.map((Card c) => c.toJson()).toList(),
    'fm': flipMovedCards,
    'fu': flipUnderCard,
  };

  @override
  List<Object?> get props => <Object?>[
    fromPile,
    toPile,
    cards,
    flipMovedCards,
    flipUnderCard,
  ];

  @override
  bool get stringify => true;
}
