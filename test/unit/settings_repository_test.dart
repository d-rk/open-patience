import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/persistence/shared_prefs_settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  test('sound is on by default', () async {
    final SharedPreferences prefs = await prefsWith(<String, Object>{});
    expect(SharedPrefsSettingsRepository(prefs).soundEnabled, isTrue);
  });

  test('turning sound off persists across instances', () async {
    final SharedPreferences prefs = await prefsWith(<String, Object>{});
    await SharedPrefsSettingsRepository(prefs).setSoundEnabled(false);
    expect(SharedPrefsSettingsRepository(prefs).soundEnabled, isFalse);
    expect(prefs.getBool('settings.sound'), isFalse);
  });

  test('turning it back on is read immediately', () async {
    final SharedPreferences prefs = await prefsWith(<String, Object>{
      'settings.sound': false,
    });
    final SharedPrefsSettingsRepository repo = SharedPrefsSettingsRepository(
      prefs,
    );
    await repo.setSoundEnabled(true);
    expect(repo.soundEnabled, isTrue);
  });

  test('a corrupt non-bool value reads as on instead of throwing', () async {
    final SharedPreferences prefs = await prefsWith(<String, Object>{
      'settings.sound': 'yes please',
    });
    expect(SharedPrefsSettingsRepository(prefs).soundEnabled, isTrue);
  });
}
