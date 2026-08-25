import '../core/game_state.dart';
import 'stats.dart';

/// A saved in-progress game: everything needed to resume or restart the same
/// deal. [state] is game-agnostic; the [variant] id selects the rules and the
/// [seed] reproduces the original deal for a restart.
class SavedGame {
  const SavedGame({
    required this.variant,
    required this.seed,
    required this.state,
  });

  final String variant;
  final int seed;
  final GameState state;
}

/// The storage seam. Local now (shared_preferences), online-ready later — an
/// alternate backend implements this interface without any change to `core/`
/// or the widgets.
abstract class RecordsRepository {
  /// Records a win for [variant] with [timeSeconds] and [moves].
  Future<void> recordWin({
    required String variant,
    required int timeSeconds,
    required int moves,
  });

  /// The current [Stats] for [variant] — [Stats.empty] when none are stored.
  Future<Stats> statsFor(String variant);

  /// Persists the in-progress [state] for [variant] under its save slot,
  /// alongside the [seed] needed to restart the same deal.
  Future<void> saveGame({
    required String variant,
    required int seed,
    required GameState state,
  });

  /// Loads the saved game for [variant], or `null` when no save exists.
  Future<SavedGame?> loadGame(String variant);

  /// Whether a resumable save exists for [variant].
  Future<bool> hasSave(String variant);

  /// Clears the save slot for [variant] (e.g. after a win or a new deal).
  Future<void> clearSave(String variant);

  /// Every in-progress save across all variants. Corrupt entries are skipped.
  Future<List<SavedGame>> loadAllSaves();
}
