import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/presentation/board.dart';
import 'package:open_patience/presentation/card_view.dart';
import 'package:open_patience/ui/game_options_screen.dart';
import 'package:open_patience/ui/main_menu_screen.dart';
import 'package:open_patience/ui/records_screen.dart';
import 'package:open_patience/ui/theme/game_motion.dart';
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

/// Drives the app to one King away from winning: main menu → Klondike →
/// debug near-win trigger → every foundation but the last built up. Uses
/// bounded pumps throughout rather than `pumpAndSettle` — with animations
/// enabled (unlike [_repo]'s other, `disableAnimations: true` caller), a
/// decorative main-menu animation never settles on its own, and the caller
/// taps the final King itself, whose cascade runs forever once started.
Future<void> _openGameOneKingFromWinning(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final RecordsRepository repo = await _repo();
  await tester.pumpWidget(MaterialApp(home: MainMenuScreen(repository: repo)));
  await tester.pump(const Duration(milliseconds: 500));

  await tester.tap(find.text('Klondike'));
  // The push transition plus the options screen's `hasSave` FutureBuilder
  // both need more than one frame's worth of real time to settle.
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));

  // The debug-only near-win trigger deals all four foundations to a Queen
  // with the matching King alone on a tableau column.
  await tester.tap(find.byIcon(Icons.bug_report).first);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));

  const List<Suit> suits = Suit.values;
  for (final Suit suit in suits.take(suits.length - 1)) {
    await tester.tap(_kingFace(suit));
    await tester.pump(const Duration(milliseconds: 350)); // double-tap window
    await tester.pump(const Duration(milliseconds: 300)); // move settles
  }
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

  testWidgets('a tap during the win cascade before its minimum look does not '
      'navigate to records', (WidgetTester tester) async {
    await _openGameOneKingFromWinning(tester);
    final Suit lastSuit = Suit.values.last;
    await tester.tap(_kingFace(lastSuit));
    await tester.pump(const Duration(milliseconds: 350)); // fire onTap
    await tester.pump(); // rebuild: GameWon, the cascade begins

    // The win overlay is opaque and sits on top of the whole play area, so
    // this lands on it rather than Board itself — exactly the "tap
    // anywhere" surface under test.
    await tester.tap(find.byType(Board), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RecordsScreen), findsNothing);
  });

  testWidgets(
    'tapping anywhere after the win cascade\'s minimum look navigates to '
    'records',
    (WidgetTester tester) async {
      await _openGameOneKingFromWinning(tester);
      final Suit lastSuit = Suit.values.last;
      await tester.tap(_kingFace(lastSuit));
      await tester.pump(const Duration(milliseconds: 350)); // fire onTap
      await tester.pump(); // rebuild: GameWon, the cascade begins

      await tester.pump(GameMotion.winCascadeMinimumBeforeDismiss);
      await tester.tap(find.byType(Board), warnIfMissed: false);
      await tester.pump();
      // The push transition needs another frame's worth of real time to
      // actually insert the new route's page into the tree.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(RecordsScreen), findsOneWidget);
    },
  );
}
