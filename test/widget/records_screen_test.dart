import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/persistence/stats.dart';
import 'package:open_patience/ui/records_screen.dart';
import 'package:open_patience/ui/theme/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPrefsRecordsRepository> _repoWith(Stats stats) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    '${SharedPrefsRecordsRepository.statsPrefix}klondike-draw1': jsonEncode(
      stats.toJson(),
    ),
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return SharedPrefsRecordsRepository(prefs);
}

Future<void> _pump(WidgetTester tester, Stats stats) async {
  final SharedPrefsRecordsRepository repo = await _repoWith(stats);
  await tester.pumpWidget(
    MaterialApp(
      home: RecordsScreen(
        repository: repo,
        variant: 'klondike-draw1',
        title: 'Klondike',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the win rate hero with won/played counts', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const Stats(
        gamesPlayed: 42,
        gamesWon: 17,
        bestTimeSeconds: 222,
        fewestMoves: 98,
        currentStreak: 3,
        longestStreak: 6,
      ),
    );

    expect(find.text('40%'), findsOneWidget);
    expect(find.text('Win rate'), findsOneWidget);
    expect(find.text('17 won'), findsOneWidget);
    expect(find.text('25 lost'), findsOneWidget);
  });

  testWidgets('header title is just "Records", with the variant as a subtitle '
      '(so it fits on a narrow phone)', (WidgetTester tester) async {
    await _pump(tester, const Stats(gamesPlayed: 1, gamesWon: 1));

    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Klondike'), findsOneWidget);
    expect(find.text('Klondike — Records'), findsNothing);
  });

  testWidgets(
    'the ring shows a tiered emoji reflecting the win rate — no digits, so '
    "there's nothing for a font's metrics to mis-center",
    (WidgetTester tester) async {
      Future<String> emojiOnRing(Stats stats) async {
        await _pump(tester, stats);
        final Finder ring = find
            .ancestor(
              of: find.byType(CircularProgressIndicator),
              matching: find.byType(SizedBox),
            )
            .first;
        final Finder emoji = find.descendant(
          of: ring,
          matching: find.byType(Text),
        );
        expect(emoji, findsOneWidget);
        return tester.widget<Text>(emoji).data!;
      }

      expect(await emojiOnRing(Stats.empty()), '🎴');
      expect(await emojiOnRing(const Stats(gamesPlayed: 5, gamesWon: 1)), '😅');
      expect(await emojiOnRing(const Stats(gamesPlayed: 4, gamesWon: 1)), '🙂');
      expect(await emojiOnRing(const Stats(gamesPlayed: 2, gamesWon: 1)), '⭐');
      expect(await emojiOnRing(const Stats(gamesPlayed: 4, gamesWon: 3)), '🌟');
      expect(await emojiOnRing(const Stats(gamesPlayed: 4, gamesWon: 4)), '🏆');

      // The percentage still exists, just as a free-standing headline.
      expect(find.text('100%'), findsOneWidget);
    },
  );

  testWidgets('shows every stat value in the tile grid', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const Stats(
        gamesPlayed: 42,
        gamesWon: 17,
        bestTimeSeconds: 222,
        fewestMoves: 98,
        currentStreak: 3,
        longestStreak: 6,
      ),
    );

    expect(find.text('42'), findsOneWidget);
    expect(find.text('Played'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.text('Won'), findsOneWidget);
    expect(find.text('03:42'), findsOneWidget);
    expect(find.text('Best time'), findsOneWidget);
    expect(find.text('98'), findsOneWidget);
    expect(find.text('Fewest moves'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Current streak'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Longest streak'), findsOneWidget);
  });

  testWidgets('shows placeholders before any game has been won', (
    WidgetTester tester,
  ) async {
    await _pump(tester, Stats.empty());

    expect(find.text('0%'), findsOneWidget);
    expect(find.text('0 won'), findsOneWidget);
    expect(find.text('0 lost'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(2));
  });

  testWidgets('content width is capped so it does not stretch on tablet', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const Stats(gamesPlayed: 1, gamesWon: 1, currentStreak: 1),
    );

    expect(find.byType(MenuWidthLimit), findsOneWidget);
  });
}
