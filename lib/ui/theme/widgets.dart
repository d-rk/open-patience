import 'package:flutter/material.dart';

import 'game_fonts.dart';
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

/// A themed screen header: gold [title] with an optional leading back button
/// and an optional [subtitle] beneath it (e.g. the game variant, kept off the
/// title row so it stays short enough for a narrow phone). Replaces the
/// Material `AppBar` on themed screens.
class FeltHeader extends StatelessWidget {
  const FeltHeader({
    required this.title,
    this.subtitle,
    this.onBack,
    super.key,
  });

  final String title;
  final String? subtitle;
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontFamily: GameFonts.display,
                  color: GamePalette.gold,
                  fontSize: 24,
                  letterSpacing: 0.5,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontFamily: GameFonts.body,
                    color: GamePalette.cardFace.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
            ],
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

/// The app wordmark: a centered, all-caps two-tone logotype with a small
/// suit-pip flourish beneath. `OPEN` in cream, `PATIENCE` in gold, sitting on
/// the felt with a soft drop shadow. This is the main-menu title lockup.
class GameWordmark extends StatelessWidget {
  const GameWordmark({super.key});

  static const List<Shadow> _shadows = <Shadow>[
    Shadow(color: Color(0x66000000), offset: Offset(0, 2), blurRadius: 6),
  ];

  TextStyle _word(Color color) => TextStyle(
    fontFamily: GameFonts.display,
    color: color,
    fontSize: 42,
    height: 1.0,
    letterSpacing: 3,
    shadows: _shadows,
  );

  Widget _pip(String glyph) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text(
      glyph,
      style: const TextStyle(
        color: GamePalette.gold,
        fontSize: 15,
        height: 1.0,
      ),
    ),
  );

  Widget _rule() => Expanded(
    child: Container(height: 2, color: GamePalette.gold.withValues(alpha: 0.7)),
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              textBaseline: TextBaseline.alphabetic,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              children: <Widget>[
                Text('OPEN', style: _word(GamePalette.cardFace)),
                const SizedBox(width: 14),
                Text('PATIENCE', style: _word(GamePalette.gold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                _rule(),
                const SizedBox(width: 10),
                _pip('♠'),
                _pip('♥'),
                _pip('♦'),
                _pip('♣'),
                const SizedBox(width: 10),
                _rule(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The author's signature credit, styled as handwriting pressed into the felt.
/// A single centered line of script (Satisfy) in soft dark ink with a faint
/// light emboss edge. Used as a pinned footer on the main menu.
class GameSignature extends StatelessWidget {
  const GameSignature({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 4, bottom: 12),
      child: Text(
        'made by Dirk Wilden',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: GameFonts.signature,
          color: GamePalette.signatureInk,
          fontSize: 20,
          height: 1.0,
          shadows: <Shadow>[
            Shadow(color: GamePalette.signatureEmboss, offset: Offset(0, 1)),
          ],
        ),
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

/// Centres menu content and caps its width so the menu never stretches
/// uncomfortably wide on tablets; the felt fills the margins.
class MenuWidthLimit extends StatelessWidget {
  const MenuWidthLimit({required this.child, this.maxWidth = 520, super.key});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
