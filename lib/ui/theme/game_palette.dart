import 'package:flutter/material.dart';

/// Emerald Felt design tokens — the single source of truth for the game's
/// palette. Widgets reference these instead of hardcoding colors.
class GamePalette {
  GamePalette._();

  // Felt table.
  static const Color feltGreenLight = Color(0xFF2E8B57);
  static const Color feltGreenMid = Color(0xFF1C6B3C);
  static const Color feltGreenDark = Color(0xFF14532D);
  static const RadialGradient feltGradient = RadialGradient(
    center: Alignment(0, -0.8),
    radius: 1.2,
    colors: <Color>[feltGreenLight, feltGreenDark],
  );

  // Accent + cards.
  static const Color gold = Color(0xFFF6C65B);
  static const Color cardFace = Color(0xFFFFF8EC);
  static const Color cardRed = Color(0xFFC0392B);
  static const Color cardInk = Color(0xFF1C2833);

  // Leaderboard rank tinting: silver and bronze accents for 2nd/3rd place
  // (gold is reused for 1st).
  static const Color silver = Color(0xFFD6D6D6);
  static const Color bronze = Color(0xFFCD7F32);

  // Empty pile slot outline (gold at ~50%).
  static const Color pileSlotOutline = Color(0x80F6C65B);

  // Role-distinguishing empty-slot fills and marker glyph. Foundations (where
  // aces go) get a faint warm-gold wash; free cells (where cards park) get a
  // cool, darker green wash. The ghost marker glyph is gold at ~40%.
  static const Color foundationSlotFill = Color(0x1AF6C65B);
  static const Color freecellSlotFill = Color(0xA60B321E);
  static const Color slotGlyph = Color(0x66F6C65B);

  // Zone trays: translucent panels behind the two top-area groups so a player
  // can tell the foundation zone (aces build up) from the parking zone (free
  // cells) at a glance. Foundations get a warm gold wash + border; the parking
  // zone a cool, darker felt wash + a cool light border.
  static const Color foundationTrayFill = Color(0x1FF6C65B);
  static const Color foundationTrayBorder = Color(0x4DF6C65B);
  static const Color parkingTrayFill = Color(0x2E0B321E);
  static const Color parkingTrayBorder = Color(0x4DA9D4BC);

  // Handwritten signature footer: solid black ink pressed into the felt, lifted
  // by a faint light emboss edge. Ink is fully opaque black, emboss white at ~10%.
  static const Color signatureInk = Color(0xFF000000);
  static const Color signatureEmboss = Color(0x1AFFFFFF);
}

/// Formats a whole number of [seconds] as `mm:ss`.
String formatDuration(int seconds) {
  final int minutes = seconds ~/ 60;
  final int secs = seconds % 60;
  final String mm = minutes.toString().padLeft(2, '0');
  final String ss = secs.toString().padLeft(2, '0');
  return '$mm:$ss';
}
