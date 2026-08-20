import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/core/card.dart';
import 'package:solitaire/core/pile.dart';

Card _c(Suit s, int r, {bool up = true}) => Card(suit: s, rank: r, faceUp: up);

void main() {
  group('Pile', () {
    test('top card is the last element; null when empty', () {
      final Pile empty = Pile(kind: PileKind.tableau);
      expect(empty.topCard, isNull);
      final Pile p = Pile(
        kind: PileKind.tableau,
        cards: <Card>[_c(Suit.clubs, 3), _c(Suit.hearts, 4)],
      );
      expect(p.topCard, _c(Suit.hearts, 4));
    });

    test('add/removeTop/topN are immutable and consistent', () {
      final Pile p = Pile(
        kind: PileKind.tableau,
      ).add(_c(Suit.clubs, 1)).add(_c(Suit.hearts, 2)).add(_c(Suit.spades, 3));
      expect(p.length, 3);
      expect(p.topN(2), <Card>[_c(Suit.hearts, 2), _c(Suit.spades, 3)]);
      final Pile fewer = p.removeTop(2);
      expect(fewer.length, 1);
      expect(p.length, 3, reason: 'original pile is unchanged');
    });

    test('flipTopUp/Down orient only the top card', () {
      final Pile p = Pile(
        kind: PileKind.tableau,
        cards: <Card>[
          _c(Suit.clubs, 9, up: false),
          _c(Suit.hearts, 6, up: false),
        ],
      );
      final Pile flipped = p.flipTopUp();
      expect(flipped.topCard!.faceUp, isTrue);
      expect(flipped.cards.first.faceUp, isFalse);
      expect(flipped.flipTopDown().topCard!.faceUp, isFalse);
    });

    test('json round-trips to an equal pile', () {
      final Pile p = Pile(
        kind: PileKind.foundation,
        cards: <Card>[_c(Suit.spades, 1), _c(Suit.spades, 2)],
      );
      expect(Pile.fromJson(p.toJson()), equals(p));
    });
  });
}
