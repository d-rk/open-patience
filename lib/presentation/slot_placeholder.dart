import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import '../core/pile.dart';
import '../ui/theme/game_palette.dart';

/// Keys for the role markers on empty slots, so tests (and future callers) can
/// find them without reaching into glyph internals.
const Key foundationSlotMarkerKey = Key('foundationSlotMarker');
const Key parkSlotMarkerKey = Key('parkSlotMarker');

/// An empty pile slot: a subtle outlined placeholder that still accepts
/// drops and taps. Foundations and free cells carry a role-distinguishing
/// wash and ghost marker so a player can tell aces-here from park-here at a
/// glance.
class SlotPlaceholder extends StatelessWidget {
  const SlotPlaceholder({
    required this.kind,
    required this.cardSize,
    this.onTap,
    super.key,
  });

  final PileKind kind;
  final Size cardSize;

  /// Forwarded when the slot itself is tapped (used by the stock's recycle
  /// tap).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget slot = Container(
      width: cardSize.width,
      height: cardSize.height,
      decoration: BoxDecoration(
        color: _slotFill,
        borderRadius: BorderRadius.circular(cardSize.width * 0.12),
        border: Border.all(color: GamePalette.pileSlotOutline, width: 1.5),
      ),
      child: _slotMarker(),
    );
    if (onTap == null) {
      return slot;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: slot,
    );
  }

  Color? get _slotFill {
    switch (kind) {
      case PileKind.foundation:
        return GamePalette.foundationSlotFill;
      case PileKind.freecell:
        return GamePalette.freecellSlotFill;
      case PileKind.stock:
      case PileKind.waste:
      case PileKind.tableau:
        return null;
    }
  }

  Widget? _slotMarker() {
    switch (kind) {
      case PileKind.stock:
        return const Center(
          child: Icon(Icons.refresh, color: GamePalette.gold),
        );
      case PileKind.foundation:
        return Center(child: _foundationMarker());
      case PileKind.freecell:
      case PileKind.tableau:
        return Center(child: _parkMarker());
      case PileKind.waste:
        return null;
    }
  }

  /// A 2x2 cluster of all four suit pips: "suits go home here". Foundations are
  /// not suit-locked, so no single suit is shown. Suit glyphs stay on the system
  /// font for reliable Unicode rendering (per the design language), but that
  /// font renders them as colored glyphs (red hearts/diamonds, black
  /// spades/clubs) on some platforms — [ColorFiltered] flattens them to a
  /// single muted tone so they read as a quiet marker, not a loud suit chart.
  Widget _foundationMarker() {
    final TextStyle glyph = TextStyle(
      color: GamePalette.slotGlyph,
      fontSize: cardSize.width * 0.26,
      height: 1.0,
    );
    Widget row(String left, String right) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(left, style: glyph),
        SizedBox(width: cardSize.width * 0.06),
        Text(right, style: glyph),
      ],
    );
    return ColorFiltered(
      key: foundationSlotMarkerKey,
      colorFilter: const ColorFilter.mode(
        GamePalette.slotGlyph,
        BlendMode.srcIn,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          row('♠', '♥'),
          SizedBox(height: cardSize.width * 0.04),
          row('♦', '♣'),
        ],
      ),
    );
  }

  /// A hollow diamond: a quiet "resting place" for a parked card, or (on an
  /// empty tableau column) for a king-headed run.
  Widget _parkMarker() {
    final double side = cardSize.width * 0.30;
    return Transform.rotate(
      key: parkSlotMarkerKey,
      angle: math.pi / 4,
      child: Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          border: Border.all(color: GamePalette.slotGlyph, width: 2),
          borderRadius: BorderRadius.circular(side * 0.14),
        ),
      ),
    );
  }
}
