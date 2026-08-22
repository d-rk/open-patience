import 'package:flutter/material.dart';

import '../ui/theme/game_palette.dart';
import 'board_geometry.dart' show TrayKind;

/// The translucent panel drawn *behind* a group of slots — warm gold for the
/// foundations (aces build up here), cool felt for the parking zone (free cells
/// / stock+waste). Purely decorative: it is placed by [BoardGeometry] as a
/// [TrayPlacement] rect and painted beneath the cards, so it never intercepts
/// input. Fills its positioned rect exactly; the border draws at that edge.
class ZoneTray extends StatelessWidget {
  const ZoneTray({required this.kind, super.key});

  final TrayKind kind;

  @override
  Widget build(BuildContext context) {
    final bool foundation = kind == TrayKind.foundation;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: foundation
            ? GamePalette.foundationTrayFill
            : GamePalette.parkingTrayFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: foundation
              ? GamePalette.foundationTrayBorder
              : GamePalette.parkingTrayBorder,
        ),
      ),
    );
  }
}
