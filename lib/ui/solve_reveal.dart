import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme/game_palette.dart';

/// Wraps the top bar's auto-solve button so it *announces itself* the moment
/// the board becomes trivially solvable, instead of silently popping into the
/// row. On the hidden → visible edge the [child] scales in with a little
/// overshoot and then glows gold [_pulseCount] times before settling. While
/// hidden it renders nothing (occupying no space, exactly as an absent button
/// would), so the surrounding layout is unchanged.
///
/// Purely presentational: it owns the reveal animation and knows nothing about
/// *why* the button appeared — the [visible] flag is driven from the bloc's
/// `canAutoSolve`. Under reduce-motion the child simply appears at full size.
class SolveReveal extends StatefulWidget {
  const SolveReveal({required this.visible, required this.child, super.key});

  /// Whether the auto-solve action is currently available. Flipping this from
  /// `false` to `true` plays the reveal.
  final bool visible;

  /// The button to reveal (the Solve [IconButton]).
  final Widget child;

  @override
  State<SolveReveal> createState() => _SolveRevealState();
}

class _SolveRevealState extends State<SolveReveal>
    with SingleTickerProviderStateMixin {
  static const Duration _entrance = Duration(milliseconds: 460);
  static const Duration _pulse = Duration(milliseconds: 900);
  static const int _pulseCount = 3;

  // Created eagerly in [initState] (not a lazy `late` field) so [dispose] never
  // triggers its first initialisation on an already-deactivated element.
  late final AnimationController _controller;

  /// Fraction of the whole timeline spent on the entrance; the remainder is the
  /// glow pulses.
  late final double _entranceFraction =
      _entrance.inMilliseconds / _controller.duration!.inMilliseconds;

  late final Animation<double> _scale = Tween<double>(begin: 0.4, end: 1.0)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(0.0, _entranceFraction, curve: Curves.easeOutBack),
        ),
      );

  /// Cached from [MediaQuery] so the reveal can honour reduce-motion without
  /// reading an inherited widget from [didUpdateWidget] (unsafe there).
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _entrance + _pulse * _pulseCount,
    );
    // A button that is already solvable on first mount still animates in, but
    // MediaQuery isn't readable yet in initState — defer to the first frame.
    if (widget.visible) {
      WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        if (mounted) {
          _reveal();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
  }

  @override
  void didUpdateWidget(SolveReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _reveal();
    } else if (!widget.visible && oldWidget.visible) {
      // Re-arm so a later reveal plays fresh from the start.
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Plays the reveal, or — under reduce-motion — jumps straight to rest so the
  /// button appears at full size with no motion.
  void _reveal() {
    if (_reduceMotion) {
      _controller.value = 1.0;
    } else {
      _controller.forward(from: 0.0);
    }
  }

  /// The glow strength (0..1) at timeline position [t]: nothing during the
  /// entrance, then [_pulseCount] gold humps across the remainder.
  double _glowAt(double t) {
    if (t <= _entranceFraction) {
      return 0.0;
    }
    final double p = (t - _entranceFraction) / (1.0 - _entranceFraction);
    return math.sin(p * _pulseCount * math.pi).abs();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) {
      return const SizedBox.shrink();
    }
    return ScaleTransition(
      key: const ValueKey<String>('solve-reveal-scale'),
      scale: _scale,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final double glow = _glowAt(_controller.value);
          return DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: glow == 0.0
                  ? const <BoxShadow>[]
                  : <BoxShadow>[
                      BoxShadow(
                        color: GamePalette.gold.withValues(alpha: 0.45 * glow),
                        blurRadius: 18.0 * glow,
                        spreadRadius: 4.0 * glow,
                      ),
                    ],
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
