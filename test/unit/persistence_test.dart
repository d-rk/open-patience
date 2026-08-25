import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/game_registry.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/games/klondike.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/persistence/stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    test('recordWin persists and accumulates per variant', () async {
      await repo.recordWin(variant: 'freecell', timeSeconds: 90, moves: 60);
      await repo.recordWin(variant: 'freecell', timeSeconds: 70, moves: 55);
      final Stats s = await repo.statsFor('freecell');
      expect(s.totalWins, 2);
      expect(s.bestWins.first.timeSeconds, 70);
      // Other variants are unaffected.
      expect(await repo.statsFor('klondike-draw1'), Stats.empty());
    });

    test('corrupt stats blob degrades to empty rather than throwing', () async {
      await prefs.setString('stats:freecell', 'not json');
      expect(await repo.statsFor('freecell'), Stats.empty());
    });

    test('old pre-leaderboard stats blob degrades to empty rather than '
        'throwing', () async {
      await prefs.setString(
        'stats:freecell',
        jsonEncode(<String, dynamic>{
          'gamesPlayed': 5,
          'gamesWon': 3,
          'bestTimeSeconds': 120,
          'fewestMoves': 80,
          'currentStreak': 1,
          'longestStreak': 2,
        }),
      );
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

  group('SharedPrefsRecordsRepository loadAllSaves', () {
    test('returns every saved game and skips corrupt blobs', () async {
      final GameState k = GameState.newGame(
        GameRegistry.rulesFor('klondike-draw1'),
        seed: 11,
      );
      final GameState f = GameState.newGame(
        GameRegistry.rulesFor('freecell'),
        seed: 22,
      );
      await repo.saveGame(variant: 'klondike-draw1', seed: 11, state: k);
      await repo.saveGame(variant: 'freecell', seed: 22, state: f);
      await prefs.setString('save:corrupt', 'not json');

      final List<SavedGame> all = await repo.loadAllSaves();
      final Map<String, SavedGame> byVariant = <String, SavedGame>{
        for (final SavedGame s in all) s.variant: s,
      };
      expect(byVariant.keys.toSet(), <String>{'klondike-draw1', 'freecell'});
      expect(byVariant['klondike-draw1']!.seed, 11);
      expect(byVariant['freecell']!.seed, 22);
    });

    test('returns empty when there are no saves', () async {
      expect(await repo.loadAllSaves(), isEmpty);
    });
  });
}
