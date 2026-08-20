import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/persistence/stats.dart';

void main() {
  group('Stats math', () {
    test('empty stats have zeroed counters and no records', () {
      const Stats s = Stats();
      expect(s.gamesPlayed, 0);
      expect(s.gamesWon, 0);
      expect(s.winPercentage, 0);
      expect(s.bestTimeSeconds, isNull);
      expect(s.fewestMoves, isNull);
    });

    test('win percentage is computed from played/won', () {
      Stats s = const Stats();
      s = s.recordWin(timeSeconds: 100, moves: 50); // 1/1
      s = s.recordLoss(); // 1/2
      s = s.recordLoss(); // 1/3
      s = s.recordWin(timeSeconds: 90, moves: 40); // 2/4
      expect(s.gamesPlayed, 4);
      expect(s.gamesWon, 2);
      expect(s.winPercentage, 50.0);
    });

    test('best time and fewest moves only improve', () {
      Stats s = const Stats();
      s = s.recordWin(timeSeconds: 120, moves: 80);
      expect(s.bestTimeSeconds, 120);
      expect(s.fewestMoves, 80);
      // A slower, higher-move win must not worsen the records.
      s = s.recordWin(timeSeconds: 200, moves: 90);
      expect(s.bestTimeSeconds, 120);
      expect(s.fewestMoves, 80);
      // A faster win with fewer moves improves both.
      s = s.recordWin(timeSeconds: 60, moves: 55);
      expect(s.bestTimeSeconds, 60);
      expect(s.fewestMoves, 55);
    });

    test('streaks: wins extend current, longest is a high-water mark', () {
      Stats s = const Stats();
      s = s.recordWin(timeSeconds: 10, moves: 10); // cur1 long1
      s = s.recordWin(timeSeconds: 10, moves: 10); // cur2 long2
      s = s.recordWin(timeSeconds: 10, moves: 10); // cur3 long3
      expect(s.currentStreak, 3);
      expect(s.longestStreak, 3);

      s = s.recordLoss(); // cur0 long3
      expect(s.currentStreak, 0);
      expect(s.longestStreak, 3);

      s = s.recordWin(timeSeconds: 10, moves: 10); // cur1 long3
      s = s.recordWin(timeSeconds: 10, moves: 10); // cur2 long3
      expect(s.currentStreak, 2);
      expect(s.longestStreak, 3, reason: 'longest is not overtaken yet');
    });

    test('json round-trips to equal stats', () {
      final Stats s = const Stats()
          .recordWin(timeSeconds: 45, moves: 33)
          .recordLoss();
      expect(Stats.fromJson(s.toJson()), equals(s));
    });
  });
}
