import '../core/game_catalog.dart';
import '../core/game_registry.dart';

/// A human-readable full title for a variant id (headers, records, resume rows).
String variantTitle(String id) {
  switch (id) {
    case GameRegistry.klondikeDraw1:
      return 'Klondike (Draw 1)';
    case GameRegistry.klondikeDraw3:
      return 'Klondike (Draw 3)';
    case GameRegistry.freecell:
      return 'FreeCell';
    case GameRegistry.freecellCells2:
      return 'FreeCell (2 cells)';
    case GameRegistry.freecellCells6:
      return 'FreeCell (6 cells)';
    default:
      return id;
  }
}

/// The display name of a game (title screen and options header).
String gameTitle(String gameId) {
  switch (gameId) {
    case GameCatalog.klondike:
      return 'Klondike';
    case GameCatalog.freecell:
      return 'FreeCell';
    default:
      return gameId;
  }
}

/// A short label for a variant row on a game's options page.
String variantShortLabel(String id) {
  switch (id) {
    case GameRegistry.klondikeDraw1:
      return 'Draw 1';
    case GameRegistry.klondikeDraw3:
      return 'Draw 3';
    case GameRegistry.freecell:
      return 'Classic · 4 cells';
    case GameRegistry.freecellCells2:
      return '2 cells · hard';
    case GameRegistry.freecellCells6:
      return '6 cells · relaxed';
    default:
      return id;
  }
}

/// A one-line descriptor under a variant's short label.
String variantDescriptor(String id) {
  switch (id) {
    case GameRegistry.klondikeDraw1:
      return 'Turn one card at a time';
    case GameRegistry.klondikeDraw3:
      return 'Turn three at a time';
    case GameRegistry.freecell:
      return 'Standard FreeCell';
    case GameRegistry.freecellCells2:
      return 'Fewer cells, tighter play';
    case GameRegistry.freecellCells6:
      return 'Extra room, easier';
    default:
      return '';
  }
}
