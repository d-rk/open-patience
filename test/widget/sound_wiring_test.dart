// Regression guard for the settings/sound threading: a real navigation from
// the main menu into a game must hand the same [SoundEffects] and
// [SettingsRepository] all the way down to the GameBloc / in-game menu, not
// just some of the way. See lib/ui/main_menu_screen.dart and
// lib/ui/game_options_screen.dart, which forward both through.
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/settings_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_settings_repository.dart';
import 'package:open_patience/presentation/sound/sound_cue.dart';
import 'package:open_patience/presentation/sound/sound_effects.dart';
import 'package:open_patience/ui/main_menu_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSound implements SoundEffects {
  final List<SoundCue> played = <SoundCue>[];

  @override
  void play(SoundCue cue) => played.add(cue);
}

Future<RecordsRepository> _repo() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return SharedPrefsRecordsRepository(prefs);
}

Future<SettingsRepository> _settings() async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return SharedPrefsSettingsRepository(prefs);
}

void main() {
  testWidgets(
    'main menu wires sound and settings through to the game and its menu',
    (WidgetTester tester) async {
      // A real landscape size, as game_options_test/main_menu_test use, so
      // the destination Board doesn't trip a pre-existing layout overflow.
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final RecordsRepository repo = await _repo();
      final SettingsRepository settings = await _settings();
      final _FakeSound sound = _FakeSound();

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(1200, 800),
            disableAnimations: true,
          ),
          child: MaterialApp(
            home: MainMenuScreen(
              repository: repo,
              settings: settings,
              sound: sound,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Navigate into a game via the real UI: main menu -> game options ->
      // Play a variant.
      await tester.tap(find.text('Klondike'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play').first);
      await tester.pumpAndSettle();

      expect(sound.played, contains(SoundCue.deal));

      // Open the in-game menu and confirm the settings repository made it
      // all the way down too.
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('Sound: On'), findsOneWidget);
    },
  );
}
