import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/game_state.dart';
import 'records_repository.dart';
import 'stats.dart';

/// [RecordsRepository] backed by `shared_preferences`. Each variant's stats
/// live under `stats:<variant>` and its in-progress save under `save:<variant>`,
/// both as JSON blobs. Corrupt or absent data degrades to a clean default
/// rather than throwing, so a bad blob never blocks starting a fresh game.
class SharedPrefsRecordsRepository implements RecordsRepository {
  SharedPrefsRecordsRepository(this._prefs);

  static const String statsPrefix = 'stats:';
  static const String savePrefix = 'save:';

  final SharedPreferences _prefs;

  @override
  Future<void> recordResult({
    required String variant,
    required bool won,
    required int timeSeconds,
    required int moves,
  }) async {
    final Stats current = await statsFor(variant);
    final Stats updated = won
        ? current.recordWin(timeSeconds: timeSeconds, moves: moves)
        : current.recordLoss();
    await _prefs.setString(
      '$statsPrefix$variant',
      jsonEncode(updated.toJson()),
    );
  }

  @override
  Future<Stats> statsFor(String variant) async {
    final String? raw = _prefs.getString('$statsPrefix$variant');
    if (raw == null) {
      return Stats.empty();
    }
    try {
      return Stats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return Stats.empty();
    }
  }

  @override
  Future<void> saveGame({
    required String variant,
    required int seed,
    required GameState state,
  }) async {
    final Map<String, dynamic> blob = <String, dynamic>{
      'variant': variant,
      'seed': seed,
      'state': state.toJson(),
    };
    await _prefs.setString('$savePrefix$variant', jsonEncode(blob));
  }

  @override
  Future<SavedGame?> loadGame(String variant) async {
    final String? raw = _prefs.getString('$savePrefix$variant');
    if (raw == null) {
      return null;
    }
    try {
      final Map<String, dynamic> blob = jsonDecode(raw) as Map<String, dynamic>;
      return SavedGame(
        variant: blob['variant'] as String,
        seed: blob['seed'] as int,
        state: GameState.fromJson(blob['state'] as Map<String, dynamic>),
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> hasSave(String variant) async {
    return _prefs.containsKey('$savePrefix$variant');
  }

  @override
  Future<void> clearSave(String variant) async {
    await _prefs.remove('$savePrefix$variant');
  }
}
