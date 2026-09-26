import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/theme/game_palette.dart';

void main() {
  group('formatDuration', () {
    test('pads minutes and seconds to mm:ss', () {
      expect(formatDuration(0), '00:00');
      expect(formatDuration(9), '00:09');
      expect(formatDuration(75), '01:15');
      expect(formatDuration(600), '10:00');
    });
  });

  group('formatMoves', () {
    test('uses the singular for exactly one move', () {
      expect(formatMoves(1), '1 move');
    });

    test('uses the plural for zero and many moves', () {
      expect(formatMoves(0), '0 moves');
      expect(formatMoves(2), '2 moves');
      expect(formatMoves(147), '147 moves');
    });
  });

  test('palette exposes the felt gradient and gold accent', () {
    expect(GamePalette.feltGradient.colors, isNotEmpty);
    expect(GamePalette.gold, const Color(0xFFF6C65B));
  });
}
