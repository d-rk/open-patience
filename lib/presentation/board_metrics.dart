import 'dart:math' as math;
import 'dart:ui';

/// Which of the three responsive arrangements the board should use.
enum BoardLayout {
  /// Top row (stock/waste/foundations) above the tableau. Any device, portrait.
  portrait,

  /// Same stacked arrangement as portrait, but card size is capped to the short
  /// landscape height and the board is centred with side margins.
  phoneLandscape,

  /// Tableau on the left taking the full height; stock/waste/foundations move
  /// to a right-hand side column. Wide (>= 600dp) devices in landscape.
  tabletLandscape,
}

/// Pure, Flutter-free (widget-free) sizing math for the [Board]. Given the
/// available space and the deal's shape, it picks the [BoardLayout] and a card
/// size that is *fit-to-height*: small enough that the longest tableau fan can
/// never overflow the viewport. Extracted from the widget so the arithmetic is
/// unit-testable in milliseconds.
class BoardMetrics {
  const BoardMetrics({
    required this.layout,
    required this.cardSize,
    required this.sideColumnWidth,
  });

  /// Padding between/around slots, mirrored by the [Board] widget.
  static const double pad = 6;

  /// Card height / width. Matches `CardView.aspectRatio`.
  static const double aspect = 1.4;

  /// The minimum fan gap as a fraction of card height; a fan compressed to this
  /// still separates cards enough to read. Used to reserve vertical room.
  static const double minFanFactor = 0.06;

  /// Material's phone/tablet boundary, measured on the shorter screen edge.
  static const double tabletBreakpoint = 600;

  /// Never shrink a card narrower than this — below it, cards are unreadable
  /// and untappable, so we accept clipping instead.
  static const double minCardWidth = 24;

  final BoardLayout layout;
  final Size cardSize;

  /// Width reserved for the right-hand column in [BoardLayout.tabletLandscape];
  /// `0` for the stacked layouts.
  final double sideColumnWidth;

  /// Resolve the layout and card size for the given board space.
  ///
  /// [sideStackCount] is the number of slots the tallest side-column stack holds
  /// in tablet landscape (free cells or foundations, whichever is taller). Cards
  /// are shrunk so that stack fits the height too, not just the tableau fan.
  factory BoardMetrics.resolve({
    required double width,
    required double height,
    required int columns,
    required int maxPileLength,
    required double shortestSide,
    required bool isLandscape,
    int sideStackCount = 4,
  }) {
    final int cols = math.max(columns, 1);
    final int fanLen = math.max(maxPileLength, 1);
    final BoardLayout layout = !isLandscape
        ? BoardLayout.portrait
        : (shortestSide >= tabletBreakpoint
              ? BoardLayout.tabletLandscape
              : BoardLayout.phoneLandscape);

    // Vertical budget: how tall a card can be before the longest fan stops
    // fitting. The stacked layouts carry a top row above the tableau (two card
    // heights); the tablet layout gives the tableau the full height (one).
    final double fanUnits = minFanFactor * (fanLen - 1);
    double heightCardHeight = layout == BoardLayout.tabletLandscape
        ? (height - 2 * pad) / (1 + fanUnits)
        : (height - 3 * pad) / (2 + fanUnits);
    // In tablet landscape the side column stacks its slots vertically; the
    // tallest stack must fit the height too, or a short fan would size cards too
    // tall for the four free cells / foundations to sit in one column.
    if (layout == BoardLayout.tabletLandscape) {
      final int rows = math.max(sideStackCount, 1);
      final double sideCardHeight = (height - (rows + 1) * pad) / rows;
      heightCardHeight = math.min(heightCardHeight, sideCardHeight);
    }
    final double widthFromHeight = heightCardHeight / aspect;

    // Horizontal budget for a card.
    final double widthFromWidth = layout == BoardLayout.tabletLandscape
        // tableau (cols cards) + side column (2 cards) share the width, with a
        // pad after every slot; solved in closed form for the card width.
        ? (width - pad * (cols + 4)) / (cols + 2)
        : (width - pad) / cols - pad;

    final double cardWidth = math.max(
      minCardWidth,
      math.min(widthFromWidth, widthFromHeight),
    );
    final double cardHeight = cardWidth * aspect;
    final double sideColumnWidth = layout == BoardLayout.tabletLandscape
        ? 2 * cardWidth + 3 * pad
        : 0;

    return BoardMetrics(
      layout: layout,
      cardSize: Size(cardWidth, cardHeight),
      sideColumnWidth: sideColumnWidth,
    );
  }
}
