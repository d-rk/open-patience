// Real-device check that every bundled sound decodes and plays through the
// audio plugin. Headless tests never touch the plugin; this is the one place
// the actual .ogg files meet the platform's decoder.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:open_patience/presentation/sound/audioplayers_sound_sink.dart';
import 'package:open_patience/presentation/sound/sound_board.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every bundled sound preloads and plays', (
    WidgetTester tester,
  ) async {
    final List<Object> errors = <Object>[];
    final AudioplayersSoundSink sink = AudioplayersSoundSink(
      onError: errors.add,
    );

    await sink.preload(SoundBoard.allAssets);
    for (final String asset in SoundBoard.allAssets) {
      expect(sink.isLoaded(asset), isTrue, reason: asset);
      sink.play(asset, 0.1);
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(errors, isEmpty);
  });
}
