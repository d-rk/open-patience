import 'package:open_patience/l10n/app_localizations.dart';

import '../core/game_catalog.dart';
import '../core/game_registry.dart';

/// A human-readable full title for a variant id (headers, records, resume rows).
String variantTitle(AppLocalizations l10n, String id) {
  switch (id) {
    case GameRegistry.klondikeDraw1:
      return l10n.fullKlondikeDraw1;
    case GameRegistry.klondikeDraw3:
      return l10n.fullKlondikeDraw3;
    case GameRegistry.freecell:
      return l10n.fullFreecell;
    case GameRegistry.freecellCells2:
      return l10n.fullFreecellCells2;
    case GameRegistry.freecellCells6:
      return l10n.fullFreecellCells6;
    default:
      return id;
  }
}

/// The display name of a game (title screen and options header).
String gameTitle(AppLocalizations l10n, String gameId) {
  switch (gameId) {
    case GameCatalog.klondike:
      return l10n.klondike;
    case GameCatalog.freecell:
      return l10n.freecell;
    default:
      return gameId;
  }
}

/// A short label for a variant row on a game's options page.
String variantShortLabel(AppLocalizations l10n, String id) {
  switch (id) {
    case GameRegistry.klondikeDraw1:
      return l10n.shortKlondikeDraw1;
    case GameRegistry.klondikeDraw3:
      return l10n.shortKlondikeDraw3;
    case GameRegistry.freecell:
      return l10n.shortFreecell;
    case GameRegistry.freecellCells2:
      return l10n.shortFreecellCells2;
    case GameRegistry.freecellCells6:
      return l10n.shortFreecellCells6;
    default:
      return id;
  }
}

/// A one-line descriptor under a variant's short label.
String variantDescriptor(AppLocalizations l10n, String id) {
  switch (id) {
    case GameRegistry.klondikeDraw1:
      return l10n.descriptorKlondikeDraw1;
    case GameRegistry.klondikeDraw3:
      return l10n.descriptorKlondikeDraw3;
    case GameRegistry.freecell:
      return l10n.descriptorFreecell;
    case GameRegistry.freecellCells2:
      return l10n.descriptorFreecellCells2;
    case GameRegistry.freecellCells6:
      return l10n.descriptorFreecellCells6;
    default:
      return '';
  }
}
