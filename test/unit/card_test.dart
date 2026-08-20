import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/core/card.dart';

void main() {
  group('Card', () {
    test('red/black colour is derived from suit', () {
      const Card ace = Card(suit: Suit.hearts, rank: 1);
      const Card two = Card(suit: Suit.diamonds, rank: 2);
      const Card three = Card(suit: Suit.clubs, rank: 3);
      const Card four = Card(suit: Suit.spades, rank: 4);
      expect(ace.color, SuitColor.red);
      expect(two.color, SuitColor.red);
      expect(three.color, SuitColor.black);
      expect(four.color, SuitColor.black);
      expect(ace.isRed, isTrue);
      expect(three.isRed, isFalse);
    });

    test('value equality ignores object identity', () {
      const Card a = Card(suit: Suit.spades, rank: 13, faceUp: true);
      const Card b = Card(suit: Suit.spades, rank: 13, faceUp: true);
      const Card c = Card(suit: Suit.spades, rank: 13);
      expect(a, equals(b));
      expect(a == c, isFalse, reason: 'faceUp participates in equality');
    });

    test('faceUp/faceDown produce oriented copies', () {
      const Card down = Card(suit: Suit.clubs, rank: 7);
      final Card up = down.faceUpCard;
      expect(up.faceUp, isTrue);
      expect(up.faceDownCard.faceUp, isFalse);
      expect(up.suit, down.suit);
      expect(up.rank, down.rank);
    });

    test('json round-trips to an equal card', () {
      const Card original = Card(suit: Suit.diamonds, rank: 11, faceUp: true);
      final Card restored = Card.fromJson(original.toJson());
      expect(restored, equals(original));
    });
  });
}
