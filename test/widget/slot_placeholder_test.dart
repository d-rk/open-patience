import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/core/pile.dart';
import 'package:solitaire/presentation/pile_view.dart';

/// The empty-slot markers must be distinguishable per pile role so a player can
/// tell at a glance where aces go (foundation) versus where a card can be
/// parked (free cell).
const Key foundationMarker = foundationSlotMarkerKey;
const Key freecellMarker = freecellSlotMarkerKey;

Future<void> _pumpEmpty(WidgetTester tester, PileKind kind) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: PileView(
            pile: Pile(kind: kind),
            pileIndex: 0,
            cardSize: const Size(60, 84),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('empty foundation shows the foundation marker only', (
    WidgetTester tester,
  ) async {
    await _pumpEmpty(tester, PileKind.foundation);

    expect(find.byKey(foundationMarker), findsOneWidget);
    expect(find.byKey(freecellMarker), findsNothing);
  });

  testWidgets('empty free cell shows the park marker only', (
    WidgetTester tester,
  ) async {
    await _pumpEmpty(tester, PileKind.freecell);

    expect(find.byKey(freecellMarker), findsOneWidget);
    expect(find.byKey(foundationMarker), findsNothing);
  });

  testWidgets('empty tableau shows neither role marker', (
    WidgetTester tester,
  ) async {
    await _pumpEmpty(tester, PileKind.tableau);

    expect(find.byKey(foundationMarker), findsNothing);
    expect(find.byKey(freecellMarker), findsNothing);
  });
}
