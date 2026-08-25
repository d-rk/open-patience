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

Future<void> _pump(
  WidgetTester tester,
  Stats stats, {
  int? justWonTimeSeconds,
  int? justWonMoves,
}) async {
  final SharedPrefsRecordsRepository repo = await _repoWith(stats);
  await tester.pumpWidget(
    MaterialApp(
      home: RecordsScreen(
        repository: repo,
        variant: 'klondike-draw1',
        title: 'Klondike',
        justWonTimeSeconds: justWonTimeSeconds,
        justWonMoves: justWonMoves,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _textAt(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;

void main() {
  testWidgets('shows total wins and the best win badge', (
    WidgetTester tester,
  ) async {
    final DateTime day1 = DateTime(2026, 8, 20);
    Stats stats = const Stats();
    stats = stats.recordWin(timeSeconds: 200, moves: 90, timestamp: day1);
    stats = stats.recordWin(timeSeconds: 102, moves: 63, timestamp: day1);
    await _pump(tester, stats);

    expect(_textAt(tester, 'totalWins'), '2');
    expect(_textAt(tester, 'bestWinTime'), '01:42');
    expect(_textAt(tester, 'bestWinMoves'), '63 moves · best');
  });

  testWidgets('header title is just "Records", with the variant as a subtitle '
      '(so it fits on a narrow phone)', (WidgetTester tester) async {
    await _pump(
      tester,
      const Stats().recordWin(
        timeSeconds: 90,
        moves: 40,
        timestamp: DateTime(2026, 8, 1),
      ),
    );

    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Klondike'), findsOneWidget);
    expect(find.text('Klondike — Records'), findsNothing);
  });

  testWidgets(
    'lists every best win in fastest-first order with time, moves and date',
    (WidgetTester tester) async {
      final DateTime day1 = DateTime(2026, 8, 20);
      final DateTime day2 = DateTime(2026, 8, 12);
      Stats stats = const Stats();
      stats = stats.recordWin(timeSeconds: 115, moves: 71, timestamp: day2);
      stats = stats.recordWin(timeSeconds: 102, moves: 63, timestamp: day1);
      await _pump(tester, stats);

      expect(_textAt(tester, 'rank-1'), '1');
      expect(_textAt(tester, 'time-1'), '01:42');
      expect(_textAt(tester, 'moves-1'), '63 moves');
      expect(_textAt(tester, 'date-1'), 'Aug 20');

      expect(_textAt(tester, 'rank-2'), '2');
      expect(_textAt(tester, 'time-2'), '01:55');
      expect(_textAt(tester, 'moves-2'), '71 moves');
      expect(_textAt(tester, 'date-2'), 'Aug 12');
    },
  );

  testWidgets('shows a placeholder before any game has been won', (
    WidgetTester tester,
  ) async {
    await _pump(tester, Stats.empty());

    expect(_textAt(tester, 'totalWins'), '0');
    expect(_textAt(tester, 'bestWinTime'), '—');
    expect(find.text('Win a game to start your leaderboard.'), findsOneWidget);
  });

  testWidgets(
    'a just-won game that places on the leaderboard shows the banner with '
    'a rank chip and tags its row NEW',
    (WidgetTester tester) async {
      final DateTime today = DateTime.now();
      Stats stats = const Stats();
      stats = stats.recordWin(timeSeconds: 102, moves: 63, timestamp: today);
      stats = stats.recordWin(timeSeconds: 115, moves: 71, timestamp: today);
      await _pump(tester, stats, justWonTimeSeconds: 115, justWonMoves: 71);

      expect(find.text('You won in 01:55 · 71 moves'), findsOneWidget);
      expect(find.text('#2 BEST'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
    },
  );

  testWidgets(
    'a just-won game outside the top 10 shows the banner without a rank '
    'chip and highlights nothing',
    (WidgetTester tester) async {
      final DateTime today = DateTime.now();
      final Stats stats = const Stats().recordWin(
        timeSeconds: 102,
        moves: 63,
        timestamp: today,
      );
      await _pump(tester, stats, justWonTimeSeconds: 400, justWonMoves: 140);

      expect(find.text('You won in 06:40 · 140 moves'), findsOneWidget);
      expect(find.textContaining('BEST'), findsNothing);
      expect(find.text('NEW'), findsNothing);
    },
  );

  testWidgets('content width is capped so it does not stretch on tablet', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const Stats().recordWin(
        timeSeconds: 90,
        moves: 40,
        timestamp: DateTime(2026, 8, 1),
      ),
    );

    expect(find.byType(MenuWidthLimit), findsOneWidget);
  });
}
