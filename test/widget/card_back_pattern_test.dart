import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/presentation/card_back_pattern.dart';
import 'package:open_patience/presentation/card_view.dart';

Future<void> _pumpFace(WidgetTester tester, Card card) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: CardFace(card: card, size: const Size(60, 84)),
        ),
      ),
    ),
  );
}

void main() {
  const Card faceDown = Card(suit: Suit.spades, rank: 7, faceUp: false);
  const Card faceUp = Card(suit: Suit.spades, rank: 7, faceUp: true);

  testWidgets('a face-down card renders the argyle lattice overlay', (
    WidgetTester tester,
  ) async {
    await _pumpFace(tester, faceDown);

    expect(find.byType(CardBackPattern), findsOneWidget);
  });

  testWidgets('a face-up card renders no lattice overlay', (
    WidgetTester tester,
  ) async {
    await _pumpFace(tester, faceUp);

    expect(find.byType(CardBackPattern), findsNothing);
  });

  testWidgets('the lattice does not disturb the face-down semantic label', (
    WidgetTester tester,
  ) async {
    await _pumpFace(tester, faceDown);

    expect(find.bySemanticsLabel('face-down card'), findsOneWidget);
  });
}
