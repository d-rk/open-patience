import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/presentation/card_view.dart';
import 'package:open_patience/ui/game_options_screen.dart';
import 'package:open_patience/ui/main_menu_screen.dart';
import 'package:open_patience/ui/records_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<RecordsRepository> _repo() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return SharedPrefsRecordsRepository(prefs);
}

Finder _kingFace(Suit s) => find.byWidgetPredicate(
  (Widget w) =>
      w is CardFace &&
      w.card.suit == s &&
      w.card.rank == kingRank &&
      w.card.faceUp,
);

/// A single tap on a card that also handles double-tap is intentionally
/// deferred by Flutter's gesture arena until the double-tap window closes, so
/// the test must let that timer elapse before `onTap` fires.
Future<void> _tapCard(WidgetTester tester, Finder card) async {
  await tester.tap(card);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'winning then leaving the records screen returns to the main menu, '
    'not the finished board',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final RecordsRepository repo = await _repo();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(1200, 800),
            disableAnimations: true,
          ),
          child: MaterialApp(home: MainMenuScreen(repository: repo)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Klondike'));
      await tester.pumpAndSettle();
      expect(find.byType(GameOptionsScreen), findsOneWidget);

      // The debug-only near-win trigger deals all four foundations to a
      // Queen with the matching King alone on a tableau column.
      await tester.tap(find.byIcon(Icons.bug_report).first);
      await tester.pumpAndSettle();

      for (final Suit suit in Suit.values) {
        await _tapCard(tester, _kingFace(suit));
      }

      expect(find.byType(RecordsScreen), findsOneWidget);

      final NavigatorState nav = tester.state(find.byType(Navigator));
      nav.pop();
      await tester.pumpAndSettle();

      expect(find.byType(MainMenuScreen), findsOneWidget);
      expect(find.byType(GameOptionsScreen), findsNothing);
      expect(find.byType(RecordsScreen), findsNothing);
    },
  );
}
