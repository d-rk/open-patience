import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/theme/game_fonts.dart';
import 'package:open_patience/ui/theme/widgets.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('GamePill renders its label', (WidgetTester tester) async {
    await _pump(tester, const GamePill(icon: Icons.timer, label: '01:15'));
    expect(find.text('01:15'), findsOneWidget);
  });

  testWidgets('FeltHeader shows the title and fires onBack', (
    WidgetTester tester,
  ) async {
    int backs = 0;
    await _pump(tester, FeltHeader(title: 'Records', onBack: () => backs++));
    expect(find.text('Records'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    expect(backs, 1);
  });

  testWidgets('GameActionTile fires onPressed', (WidgetTester tester) async {
    int taps = 0;
    await _pump(
      tester,
      GameActionTile(
        icon: Icons.replay,
        label: 'Restart',
        background: const Color(0xFFD6F0DD),
        foreground: const Color(0xFF14532D),
        onPressed: () => taps++,
      ),
    );
    await tester.tap(find.text('Restart'));
    expect(taps, 1);
  });

  testWidgets('GameWordmark shows the two-tone all-caps wordmark', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const GameWordmark());
    expect(find.text('OPEN'), findsOneWidget);
    expect(find.text('PATIENCE'), findsOneWidget);
  });

  testWidgets(
    'GameSignature renders the handwritten credit in the script font',
    (WidgetTester tester) async {
      await _pump(tester, const GameSignature());
      final Finder credit = find.text('made by Dirk Wilden');
      expect(credit, findsOneWidget);
      final Text text = tester.widget<Text>(credit);
      expect(text.style?.fontFamily, GameFonts.signature);
      // Fully opaque black ink.
      expect(text.style?.color, const Color(0xFF000000));
    },
  );
}
