import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/deck.dart';

void main() {
  group('Deck', () {
    test('standard deck has 52 unique cards', () {
      final Deck deck = Deck.standard();
      expect(deck.length, 52);
      final Set<String> ids = deck.cards
          .map((Card c) => '${c.suit.index}-${c.rank}')
          .toSet();
      expect(ids.length, 52);
    });

    test('same seed produces an identical shuffle (determinism)', () {
      final Deck a = Deck.standard()..shuffle(Random(42));
      final Deck b = Deck.standard()..shuffle(Random(42));
      expect(a.cards, equals(b.cards));
    });

    test('different seeds produce different orderings', () {
      final Deck a = Deck.standard()..shuffle(Random(1));
      final Deck b = Deck.standard()..shuffle(Random(2));
      expect(a.cards, isNot(equals(b.cards)));
    });

    test('shuffle is a permutation (no cards lost or duplicated)', () {
      final Deck deck = Deck.standard()..shuffle(Random(7));
      final Set<String> ids = deck.cards
          .map((Card c) => '${c.suit.index}-${c.rank}')
          .toSet();
      expect(deck.length, 52);
      expect(ids.length, 52);
    });

    test('deal removes cards from the top', () {
      final Deck deck = Deck.standard();
      final List<Card> dealt = deck.deal(5);
      expect(dealt.length, 5);
      expect(deck.length, 47);
    });
  });
}
