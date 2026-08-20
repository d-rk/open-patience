import '../core/game_registry.dart';

/// A human-readable title for a variant id, for headers and records screens.
///
/// Lives in its own file (rather than on a screen) so any screen can label a
/// variant without creating cross-screen import cycles.
String variantTitle(String id) {
  switch (id) {
    case GameRegistry.klondikeDraw1:
      return 'Klondike (Draw 1)';
    case GameRegistry.klondikeDraw3:
      return 'Klondike (Draw 3)';
    case GameRegistry.freecell:
      return 'FreeCell';
    default:
      return id;
  }
}
