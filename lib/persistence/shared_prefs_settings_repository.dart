import 'package:shared_preferences/shared_preferences.dart';

import 'settings_repository.dart';

/// [SettingsRepository] over the already-loaded [SharedPreferences], so
/// reads are synchronous.
class SharedPrefsSettingsRepository implements SettingsRepository {
  SharedPrefsSettingsRepository(this._prefs);

  static const String soundKey = 'settings.sound';

  final SharedPreferences _prefs;

  @override
  bool get soundEnabled {
    // A missing or corrupt (non-bool) value means "never turned off".
    final Object? raw = _prefs.get(soundKey);
    return raw is bool ? raw : true;
  }

  @override
  Future<void> setSoundEnabled(bool enabled) async {
    await _prefs.setBool(soundKey, enabled);
  }
}
