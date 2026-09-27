import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/presentation/sound/sound_board.dart';

void main() {
  test('every sound the board can play is bundled', () {
    for (final String asset in SoundBoard.allAssets) {
      expect(File('assets/$asset').existsSync(), isTrue, reason: asset);
    }
  });

  test('pubspec bundles the sounds folder', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('- assets/sounds/'),
    );
  });
}
