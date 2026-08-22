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

  /// Internal padding of a zone tray (the translucent panel behind the free
  /// cells / foundations). Reserved here so trays never squeeze the fan.
  static const double trayPad = 4;

  /// A zone tray's border width. A bordered [BoxDecoration] insets its child by
  /// the border on every side, so the reserved chrome is [trayPad] + [trayBorder].
  static const double trayBorder = 1;

  /// The total inset a zone tray adds on each side (padding + border).
  static const double trayInset = trayPad + trayBorder;

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
  ///
  /// The stacked layouts carry a top area above the tableau of [topRows] tray
  /// rows (1 normally; 2 when the free cells + foundations would overflow a
  /// single row, as in 6-cell FreeCell). [topRowSlots] is the number of slots on
  /// the widest single top line and [topTrays] the number of trays on it — both
  /// let the card be sized so the top area fits the width. Left at their
  /// defaults, the top area imposes no extra constraint (used by tests that only
  /// exercise the tableau budget).
  factory BoardMetrics.resolve({
    required double width,
    required double height,
    required int columns,
    required int maxPileLength,
    required double shortestSide,
    required bool isLandscape,
    int sideStackCount = 4,
    int topRows = 1,
    int topRowSlots = 0,
    int topTrays = 0,
  }) {
    final int cols = math.max(columns, 1);
    final int fanLen = math.max(maxPileLength, 1);
    final BoardLayout layout = !isLandscape
        ? BoardLayout.portrait
        : (shortestSide >= tabletBreakpoint
              ? BoardLayout.tabletLandscape
              : BoardLayout.phoneLandscape);

    // Vertical budget: how tall a card can be before the longest fan stops
    // fitting. The stacked layouts carry the top area above the tableau
    // ([topRows] card heights, plus tray chrome); the tablet layout gives the
    // tableau the full height (one).
    final double fanUnits = minFanFactor * (fanLen - 1);
    double heightCardHeight;
    if (layout == BoardLayout.tabletLandscape) {
      heightCardHeight = (height - 2 * pad) / (1 + fanUnits);
      // The side column stacks its slots vertically; the tallest stack (inside
      // its tray) must fit the height too, or a short fan would size cards too
      // tall for the free cells / foundations to sit in one column.
      final int rows = math.max(sideStackCount, 1);
      final double sideCardHeight =
          (height - (rows + 1) * pad - 2 * trayInset) / rows;
      heightCardHeight = math.min(heightCardHeight, sideCardHeight);
    } else {
      final int rows = math.max(topRows, 1);
      final double trayReserve = topTrays > 0 ? 2 * rows * trayInset : 0;
      heightCardHeight =
          (height - (rows + 2) * pad - trayReserve) / (rows + 1 + fanUnits);
    }
    final double widthFromHeight = heightCardHeight / aspect;

    // Horizontal budget for a card.
    double widthFromWidth;
    if (layout == BoardLayout.tabletLandscape) {
      // tableau (cols cards) + side column (2 cards + tray chrome) share the
      // width, with a pad after every slot; solved in closed form for the card.
      widthFromWidth = (width - pad * (cols + 4) - 4 * trayInset) / (cols + 2);
    } else {
      final double contentWidth = width - 2 * pad;
      widthFromWidth = contentWidth / cols - pad;
      if (topRowSlots > 0) {
        // The widest top line: topRowSlots cards, its inter-slot pads, and the
        // horizontal chrome of its trays, must fit the content width.
        final double topWidth =
            (contentWidth -
                topTrays * 2 * trayInset -
                (topRowSlots - topTrays) * pad) /
            topRowSlots;
        widthFromWidth = math.min(widthFromWidth, topWidth);
      }
    }

    final double cardWidth = math.max(
      minCardWidth,
      math.min(widthFromWidth, widthFromHeight),
    );
    final double cardHeight = cardWidth * aspect;
    final double sideColumnWidth = layout == BoardLayout.tabletLandscape
        ? 2 * cardWidth + 3 * pad + 4 * trayInset
        : 0;

    return BoardMetrics(
      layout: layout,
      cardSize: Size(cardWidth, cardHeight),
      sideColumnWidth: sideColumnWidth,
    );
  }
}
