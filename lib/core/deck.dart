import 'dart:math';

import 'card.dart';

/// A mutable stack of cards used only during dealing.
///
/// Randomness is *injected*: [shuffle] takes a caller-supplied [Random] so a
/// seed fully determines the deal. Nothing in this class ever reaches for
/// global randomness — that guarantee is what makes deals reproducible and
/// tests deterministic.
class Deck {
  Deck(List<Card> cards) : _cards = List<Card>.of(cards);

  /// A standard 52-card deck in a fixed suit-major, ascending-rank order.
  /// Cards are face down by default; dealing decides final orientation.
  factory Deck.standard({bool faceUp = false}) {
    final List<Card> cards = <Card>[];
    for (final Suit suit in Suit.values) {
      for (int rank = aceRank; rank <= kingRank; rank++) {
        cards.add(Card(suit: suit, rank: rank, faceUp: faceUp));
      }
    }
    return Deck(cards);
  }

  final List<Card> _cards;

  int get length => _cards.length;

  bool get isEmpty => _cards.isEmpty;

  /// An immutable view of the current card order.
  List<Card> get cards => List<Card>.unmodifiable(_cards);

  /// In-place Fisher-Yates shuffle driven entirely by [random].
  void shuffle(Random random) {
    for (int i = _cards.length - 1; i > 0; i--) {
      final int j = random.nextInt(i + 1);
      final Card tmp = _cards[i];
      _cards[i] = _cards[j];
      _cards[j] = tmp;
    }
  }

  /// Removes and returns the top [n] cards (from the end of the deck).
  List<Card> deal(int n) {
    if (n < 0 || n > _cards.length) {
      throw RangeError('Cannot deal $n cards from a deck of ${_cards.length}');
    }
    final List<Card> dealt = _cards.sublist(_cards.length - n);
    _cards.removeRange(_cards.length - n, _cards.length);
    return dealt;
  }

  /// Removes and returns the single top card.
  Card dealOne() => deal(1).first;
}
