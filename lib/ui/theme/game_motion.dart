import 'package:flutter/animation.dart';

/// Motion tokens for card animations. All card-animation durations and curves
/// live here so no widget hardcodes them (per the design-language rule that
/// shared visual tokens live in `lib/ui/theme/`).
class GameMotion {
  const GameMotion._();

  /// A card gliding from one pile to another (tap / double-tap / drop-settle).
  static const Duration move = Duration(milliseconds: 220);

  /// A card turning face-down↔face-up.
  static const Duration flip = Duration(milliseconds: 260);

  /// A stock→waste draw slide.
  static const Duration draw = Duration(milliseconds: 200);

  /// Delay between successive cards in a staggered deal.
  static const Duration dealStagger = Duration(milliseconds: 40);

  /// The win cascade runs indefinitely as a reward the player can linger on;
  /// this is the minimum time it plays before a tap anywhere is honored to
  /// dismiss it and move on to the records screen.
  static const Duration winCascadeMinimumBeforeDismiss = Duration(seconds: 3);

  static const Curve moveCurve = Curves.easeOutCubic;
  static const Curve flipCurve = Curves.easeInOut;

  /// Perspective depth for the card flip (the `(3,2)` entry of the rotation
  /// matrix). Non-zero so the turning card foreshortens like a real card
  /// pivoting in space instead of squashing flat. Tuned for card-sized widgets.
  static const double flipPerspective = 0.002;

  /// The effective duration honoring the OS reduce-motion setting: [base] when
  /// motion is allowed, [Duration.zero] (instant snap) when [reduceMotion].
  static Duration resolve(Duration base, {required bool reduceMotion}) =>
      reduceMotion ? Duration.zero : base;
}
