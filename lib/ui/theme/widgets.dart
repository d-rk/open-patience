import 'package:flutter/material.dart';

import 'game_palette.dart';

/// Paints the Emerald Felt gradient behind [child]. Wrap a screen body in it.
class FeltBackground extends StatelessWidget {
  const FeltBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: GamePalette.feltGradient),
      child: child,
    );
  }
}

/// A themed screen header: gold [title] with an optional leading back button.
/// Replaces the Material `AppBar` on themed screens.
class FeltHeader extends StatelessWidget {
  const FeltHeader({required this.title, this.onBack, super.key});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: <Widget>[
          if (onBack != null)
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back, color: GamePalette.gold),
              onPressed: onBack,
            ),
          Text(
            title,
            style: const TextStyle(
              color: GamePalette.gold,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded stat pill (icon + label) used for timer / moves.
class GamePill extends StatelessWidget {
  const GamePill({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: GamePalette.gold),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: GamePalette.gold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A menu action tile (icon + label on a colored, rounded background).
class GameActionTile extends StatelessWidget {
  const GameActionTile({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, color: foreground, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
