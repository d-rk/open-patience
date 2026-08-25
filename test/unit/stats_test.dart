import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/persistence/stats.dart';

void main() {
  group('WinRecord', () {
    test('json round-trips to an equal record', () {
      final WinRecord w = WinRecord(
        timestamp: DateTime(2026, 8, 20, 14, 32),
        timeSeconds: 123,
        moves: 87,
      );
      expect(WinRecord.fromJson(w.toJson()), equals(w));
    });
  });

  group('Stats math', () {
    test('empty stats have zero wins and no leaderboard entries', () {
      const Stats s = Stats();
      expect(s.totalWins, 0);
      expect(s.bestWins, isEmpty);
    });

    test('recordWin always increments totalWins, even off the leaderboard', () {
      Stats s = const Stats();
      s = s.recordWin(
        timeSeconds: 100,
        moves: 50,
        timestamp: DateTime(2026, 1, 1),
      );
      s = s.recordWin(
        timeSeconds: 90,
        moves: 40,
        timestamp: DateTime(2026, 1, 2),
      );
      expect(s.totalWins, 2);
    });

    test('bestWins is sorted fastest-first, ties broken by fewer moves', () {
      Stats s = const Stats();
      s = s.recordWin(
        timeSeconds: 100,
        moves: 50,
        timestamp: DateTime(2026, 1, 1),
      );
      s = s.recordWin(
        timeSeconds: 80,
        moves: 60,
        timestamp: DateTime(2026, 1, 2),
      );
      s = s.recordWin(
        timeSeconds: 80,
        moves: 45,
        timestamp: DateTime(2026, 1, 3),
      );
      expect(s.bestWins.map((WinRecord w) => w.moves).toList(), <int>[
        45,
        60,
        50,
      ]);
    });

    test('bestWins is capped at maxBestWins, keeping only the fastest', () {
      Stats s = const Stats();
      for (int i = 0; i < Stats.maxBestWins; i++) {
        s = s.recordWin(
          timeSeconds: 100 + i,
          moves: 50,
          timestamp: DateTime(2026, 1, 1),
        );
      }
      expect(s.bestWins.length, Stats.maxBestWins);
      expect(s.totalWins, Stats.maxBestWins);

      // A slower win doesn't grow or change the list.
      s = s.recordWin(
        timeSeconds: 999,
        moves: 50,
        timestamp: DateTime(2026, 1, 2),
      );
      expect(s.bestWins.length, Stats.maxBestWins);
      expect(s.bestWins.any((WinRecord w) => w.timeSeconds == 999), isFalse);
      expect(s.totalWins, Stats.maxBestWins + 1);

      // A faster win evicts the current slowest.
      final int slowestBefore = s.bestWins.last.timeSeconds;
      s = s.recordWin(
        timeSeconds: 50,
        moves: 50,
        timestamp: DateTime(2026, 1, 3),
      );
      expect(s.bestWins.length, Stats.maxBestWins);
      expect(s.bestWins.first.timeSeconds, 50);
      expect(
        s.bestWins.any((WinRecord w) => w.timeSeconds == slowestBefore),
        isFalse,
      );
    });

    test('recordWin rejects negative time or moves', () {
      const Stats s = Stats();
      expect(
        () => s.recordWin(
          timeSeconds: -1,
          moves: 0,
          timestamp: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => s.recordWin(
          timeSeconds: 0,
          moves: -1,
          timestamp: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('json round-trips to equal stats', () {
      final Stats s = const Stats()
          .recordWin(
            timeSeconds: 45,
            moves: 33,
            timestamp: DateTime(2026, 8, 20),
          )
          .recordWin(
            timeSeconds: 60,
            moves: 20,
            timestamp: DateTime(2026, 8, 21),
          );
      expect(Stats.fromJson(s.toJson()), equals(s));
    });
  });
}
