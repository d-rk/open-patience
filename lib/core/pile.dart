import 'package:equatable/equatable.dart';

import 'card.dart';

/// The role a [Pile] plays on the board. Rules are keyed off this so that
/// [GameState] itself stays game-agnostic.
enum PileKind { stock, waste, foundation, tableau, freecell }

/// An ordered collection of cards with a [kind].
///
/// The *top* of the pile is the last element of [cards] — the card a player
/// interacts with. Immutable: every mutating operation returns a new [Pile],
/// which keeps move/undo reasoning simple and makes structural equality
/// (via [Equatable]) trustworthy for snapshot assertions.
class Pile extends Equatable {
  Pile({required this.kind, List<Card> cards = const <Card>[]})
    : cards = List<Card>.unmodifiable(cards);

  factory Pile.fromJson(Map<String, dynamic> json) {
    final List<dynamic> rawCards = json['cards'] as List<dynamic>;
    return Pile(
      kind: PileKind.values[json['kind'] as int],
      cards: rawCards
          .map((dynamic c) => Card.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }

  final PileKind kind;
  final List<Card> cards;

  bool get isEmpty => cards.isEmpty;

  bool get isNotEmpty => cards.isNotEmpty;

  int get length => cards.length;

  /// The top (interactable) card, or `null` when the pile is empty.
  Card? get topCard => cards.isEmpty ? null : cards.last;

  /// The top [n] cards in board order (bottom-most of the group first).
  List<Card> topN(int n) {
    if (n < 0 || n > cards.length) {
      throw RangeError('Cannot take $n cards from a pile of ${cards.length}');
    }
    return cards.sublist(cards.length - n);
  }

  /// A copy with [card] added on top.
  Pile add(Card card) => Pile(kind: kind, cards: <Card>[...cards, card]);

  /// A copy with [newCards] added on top, preserving their order.
  Pile addAll(List<Card> newCards) =>
      Pile(kind: kind, cards: <Card>[...cards, ...newCards]);

  /// A copy with the top [n] cards removed.
  Pile removeTop(int n) {
    if (n < 0 || n > cards.length) {
      throw RangeError('Cannot remove $n cards from a pile of ${cards.length}');
    }
    return Pile(kind: kind, cards: cards.sublist(0, cards.length - n));
  }

  /// A copy with an entirely new card list.
  Pile withCards(List<Card> newCards) => Pile(kind: kind, cards: newCards);

  /// A copy with the top card turned face up (no-op on an empty pile).
  Pile flipTopUp() => _flipTop(true);

  /// A copy with the top card turned face down (no-op on an empty pile).
  Pile flipTopDown() => _flipTop(false);

  Pile _flipTop(bool faceUp) {
    if (cards.isEmpty) {
      return this;
    }
    final List<Card> next = List<Card>.of(cards);
    next[next.length - 1] = faceUp
        ? next.last.faceUpCard
        : next.last.faceDownCard;
    return Pile(kind: kind, cards: next);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'kind': kind.index,
    'cards': cards.map((Card c) => c.toJson()).toList(),
  };

  @override
  List<Object?> get props => <Object?>[kind, cards];

  @override
  bool get stringify => true;
}
