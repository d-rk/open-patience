/// Player preferences that outlive a game. Pure Dart — the storage behind it
/// is an implementation detail, exactly like RecordsRepository.
abstract class SettingsRepository {
  /// Whether sound effects play. `true` until the player turns them off.
  bool get soundEnabled;

  Future<void> setSoundEnabled(bool enabled);
}
