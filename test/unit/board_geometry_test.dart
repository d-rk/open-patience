import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/presentation/board_geometry.dart';

void main() {
  group('CardKey', () {
    test('identity ignores faceUp and equals by suit+rank', () {
      const CardKey a = CardKey(Suit.hearts, 5);
      final CardKey b = CardKey.of(
        const Card(suit: Suit.hearts, rank: 5, faceUp: true),
      );
      final CardKey c = CardKey.of(
        const Card(suit: Suit.hearts, rank: 5, faceUp: false),
      );
      expect(b, a);
      expect(c, a);
      expect(<CardKey>{a, b, c}.length, 1);
    });

    test('widgetKey is stable and distinct per card', () {
      expect(
        const CardKey(Suit.spades, 13).widgetKey,
        const CardKey(Suit.spades, 13).widgetKey,
      );
      expect(
        const CardKey(Suit.spades, 13).widgetKey ==
            const CardKey(Suit.clubs, 13).widgetKey,
        isFalse,
      );
    });
  });

  test('CardPlacement.key derives from its card', () {
    const CardPlacement p = CardPlacement(
      card: Card(suit: Suit.clubs, rank: 2, faceUp: true),
      pileIndex: 3,
      indexInPile: 0,
      isTop: true,
      rect: Rect.fromLTWH(0, 0, 10, 14),
    );
    expect(p.key, const CardKey(Suit.clubs, 2));
  });
}
