import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solitaire/core/game_registry.dart';
import 'package:solitaire/core/game_state.dart';
import 'package:solitaire/core/games/klondike.dart';
import 'package:solitaire/persistence/records_repository.dart';
import 'package:solitaire/persistence/shared_prefs_records_repository.dart';
import 'package:solitaire/persistence/stats.dart';

void main() {
  late SharedPreferences prefs;
  late SharedPrefsRecordsRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    repo = SharedPrefsRecordsRepository(prefs);
  });

  group('SharedPrefsRecordsRepository stats', () {
    test('unknown variant returns empty stats', () async {
      final Stats s = await repo.statsFor('klondike-draw1');
      expect(s, Stats.empty());
    });

    test('recordResult persists and accumulates per variant', () async {
      await repo.recordResult(
        variant: 'freecell',
        won: true,
        timeSeconds: 90,
        moves: 60,
      );
      await repo.recordResult(
        variant: 'freecell',
        won: false,
        timeSeconds: 0,
        moves: 0,
      );
      final Stats s = await repo.statsFor('freecell');
      expect(s.gamesPlayed, 2);
      expect(s.gamesWon, 1);
      expect(s.bestTimeSeconds, 90);
      expect(s.currentStreak, 0);
      expect(s.longestStreak, 1);
      // Other variants are unaffected.
      expect(await repo.statsFor('klondike-draw1'), Stats.empty());
    });

    test('corrupt stats blob degrades to empty rather than throwing', () async {
      await prefs.setString('stats:freecell', 'not json');
      expect(await repo.statsFor('freecell'), Stats.empty());
    });
  });

  group('SharedPrefsRecordsRepository save/resume', () {
    test('saveGame then loadGame restores an equal GameState + seed', () async {
      final KlondikeRules rules =
          GameRegistry.rulesFor('klondike-draw1') as KlondikeRules;
      final GameState original = GameState.newGame(rules, seed: 4242);
      original.applyMove(rules.buildDraw(original)!);
      original.tick(15);

      await repo.saveGame(
        variant: 'klondike-draw1',
        seed: 4242,
        state: original,
      );
      expect(await repo.hasSave('klondike-draw1'), isTrue);

      final SavedGame? loaded = await repo.loadGame('klondike-draw1');
      expect(loaded, isNotNull);
      expect(loaded!.variant, 'klondike-draw1');
      expect(loaded.seed, 4242);
      expect(loaded.state, equals(original));
      expect(loaded.state.canUndo, isTrue);
    });

    test('clearSave removes the slot', () async {
      final KlondikeRules rules = KlondikeRules(drawCount: 3);
      await repo.saveGame(
        variant: 'klondike-draw3',
        seed: 1,
        state: GameState.newGame(rules, seed: 1),
      );
      await repo.clearSave('klondike-draw3');
      expect(await repo.hasSave('klondike-draw3'), isFalse);
      expect(await repo.loadGame('klondike-draw3'), isNull);
    });

    test('loadGame returns null when no save exists', () async {
      expect(await repo.loadGame('freecell'), isNull);
    });
  });
}
