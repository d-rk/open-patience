import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/ui/theme/game_palette.dart';

void main() {
  group('formatDuration', () {
    test('pads minutes and seconds to mm:ss', () {
      expect(formatDuration(0), '00:00');
      expect(formatDuration(9), '00:09');
      expect(formatDuration(75), '01:15');
      expect(formatDuration(600), '10:00');
    });
  });

  test('palette exposes the felt gradient and gold accent', () {
    expect(GamePalette.feltGradient.colors, isNotEmpty);
    expect(GamePalette.gold, const Color(0xFFF6C65B));
  });
}
