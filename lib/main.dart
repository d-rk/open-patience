import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'persistence/records_repository.dart';
import 'persistence/settings_repository.dart';
import 'persistence/shared_prefs_records_repository.dart';
import 'persistence/shared_prefs_settings_repository.dart';
import 'presentation/sound/audioplayers_sound_sink.dart';
import 'presentation/sound/sound_board.dart';
import 'presentation/sound/sound_effects.dart';
import 'ui/main_menu_screen.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final RecordsRepository repository = SharedPrefsRecordsRepository(prefs);
  final SettingsRepository settings = SharedPrefsSettingsRepository(prefs);
  final AudioplayersSoundSink sink = AudioplayersSoundSink();
  // Load sounds in the background — startup never waits on audio.
  unawaited(sink.preload(SoundBoard.allAssets));
  runApp(
    OpenPatienceApp(
      repository: repository,
      settings: settings,
      sound: SoundBoard(sink: sink, settings: settings),
    ),
  );
}

/// Root of the app. Owns the single [RecordsRepository] and hands it to the
/// menu, which builds a [GameBloc] per game. All game logic lives in `core/`
/// behind the bloc — this widget only wires dependencies and navigation.
class OpenPatienceApp extends StatelessWidget {
  const OpenPatienceApp({
    required this.repository,
    this.settings,
    this.sound = const SilentSoundEffects(),
    super.key,
  });

  final RecordsRepository repository;

  /// Forwarded to [GameScreen] for the menu's Sound toggle.
  final SettingsRepository? settings;

  /// Handed to every [GameBloc] this app creates.
  final SoundEffects sound;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Open Patience',
      theme: AppTheme.themeData,
      home: MainMenuScreen(
        repository: repository,
        autoTick: const Duration(seconds: 1),
        settings: settings,
        sound: sound,
      ),
    );
  }
}
