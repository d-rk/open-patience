import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/theme/game_motion.dart';

void main() {
  test('resolve returns the base duration when motion is allowed', () {
    expect(
      GameMotion.resolve(GameMotion.move, reduceMotion: false),
      GameMotion.move,
    );
  });

  test('resolve collapses to zero when reduce-motion is on', () {
    expect(
      GameMotion.resolve(GameMotion.move, reduceMotion: true),
      Duration.zero,
    );
  });

  test('tokens are positive and curves are defined', () {
    expect(GameMotion.move.inMilliseconds, greaterThan(0));
    expect(GameMotion.flip.inMilliseconds, greaterThan(0));
    expect(GameMotion.draw.inMilliseconds, greaterThan(0));
    expect(GameMotion.dealStagger.inMilliseconds, greaterThan(0));
    expect(GameMotion.moveCurve, isA<Curve>());
    expect(GameMotion.flipCurve, isA<Curve>());
  });
}
