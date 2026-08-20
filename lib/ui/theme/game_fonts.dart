/// Font family names for the game's typography — the single source of truth so
/// widgets never hardcode a family string. The families are bundled as local
/// OFL assets (see `pubspec.yaml` / `assets/fonts/`); nothing is fetched at
/// runtime, which keeps the F-Droid build offline and reproducible.
class GameFonts {
  GameFonts._();

  /// Characterful display face for titles and headers (Lilita One).
  static const String display = 'LilitaOne';

  /// Clean, readable face for all body / UI text (Quicksand).
  static const String body = 'Quicksand';

  /// Rounded, legible face for card rank labels (Fredoka).
  static const String card = 'Fredoka';
}
