import 'dart:ui' as ui;

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

  testWidgets(
    'the back texture is a cached raster, not per-frame vector paths',
    (WidgetTester tester) async {
      // Re-tessellating ~140 vector paths per face-down card on every animation
      // frame stalled the GPU (F-Droid review: FreeCell hung on an Adreno 610).
      // The texture is drawn once into an image and blitted from then on.
      await _pumpFace(tester, faceDown);

      final Finder pattern = find.byType(CardBackPattern);
      expect(
        find.descendant(of: pattern, matching: find.byType(RawImage)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: pattern, matching: find.byType(CustomPaint)),
        findsNothing,
      );
    },
  );

  testWidgets('same-size card backs share one cached image', (
    WidgetTester tester,
  ) async {
    const Size size = Size(60, 84);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: <Widget>[
              CardFace(card: faceDown, size: size),
              CardFace(
                card: Card(suit: Suit.hearts, rank: 2, faceUp: false),
                size: size,
              ),
            ],
          ),
        ),
      ),
    );

    final List<ui.Image?> images = tester
        .widgetList<RawImage>(find.byType(RawImage))
        .map((RawImage r) => r.image)
        .toList();
    expect(images, hasLength(2));
    expect(images.first, isNotNull);
    expect(identical(images.first, images.last), isTrue);
  });

  testWidgets('the back needs no per-card clip layer', (
    WidgetTester tester,
  ) async {
    // The rounded-corner clip is baked into the cached image, so a face-down
    // card adds no clip to the scene.
    await _pumpFace(tester, faceDown);

    expect(find.byType(ClipRRect), findsNothing);
  });
}
