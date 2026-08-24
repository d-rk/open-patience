import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/presentation/board_metrics.dart';

/// The minimal vertical footprint a stacked (portrait / phone-landscape) board
/// needs: outer padding, the top row (one card tall), the gap below it, and the
/// tableau's longest fan compressed to its minimum gap. If the resolved card
/// height keeps this within the viewport, the board cannot overflow vertically.
double _stackedFootprint(double cardHeight, int maxPileLength) {
  final double minGap = BoardMetrics.minFanFactor * cardHeight;
  return 3 * BoardMetrics.pad + cardHeight * 2 + minGap * (maxPileLength - 1);
}

/// The tablet-landscape footprint: the tableau owns the full height (no top row
/// stacked above it), so only one card height plus the compressed fan.
double _tabletFootprint(double cardHeight, int maxPileLength) {
  final double minGap = BoardMetrics.minFanFactor * cardHeight;
  return 2 * BoardMetrics.pad + cardHeight + minGap * (maxPileLength - 1);
}

/// The tablet side column stacks [rows] slots vertically, [pad] apart, inside
/// the outer padding. If the resolved card height keeps this within the
/// viewport, the side column cannot overflow vertically.
double _sideColumnFootprint(double cardHeight, int rows) {
  return 2 * BoardMetrics.pad +
      rows * cardHeight +
      (rows - 1) * BoardMetrics.pad;
}

/// The stacked footprint for a two-row top area (foundations over free cells):
/// two tray rows, each a card tall plus tray chrome, a gap between them and
/// below, the outer padding, and the compressed tableau fan.
double _twoRowTopFootprint(double cardHeight, int maxPileLength) {
  final double minGap = BoardMetrics.minFanFactor * cardHeight;
  return 4 * BoardMetrics.pad +
      4 * BoardMetrics.trayPad +
      3 * cardHeight +
      minGap * (maxPileLength - 1);
}

void main() {
  group('layout selection', () {
    test('portrait orientation is always the portrait layout', () {
      final BoardMetrics m = BoardMetrics.resolve(
        width: 400,
        height: 800,
        columns: 7,
        maxPileLength: 13,
        shortestSide: 400,
        isLandscape: false,
      );
      expect(m.layout, BoardLayout.portrait);
      expect(m.sideColumnWidth, 0);
    });

    test('landscape on a phone-sized device is the phone-landscape layout', () {
      final BoardMetrics m = BoardMetrics.resolve(
        width: 800,
        height: 360,
        columns: 7,
        maxPileLength: 13,
        shortestSide: 360,
        isLandscape: true,
      );
      expect(m.layout, BoardLayout.phoneLandscape);
      expect(m.sideColumnWidth, 0);
    });

    test('landscape at/above 600dp shortest side is the tablet layout', () {
      final BoardMetrics m = BoardMetrics.resolve(
        width: 1200,
        height: 800,
        columns: 7,
        maxPileLength: 13,
        shortestSide: 800,
        isLandscape: true,
      );
      expect(m.layout, BoardLayout.tabletLandscape);
      expect(m.sideColumnWidth, greaterThan(0));
    });

    test('exactly 600dp shortest side counts as a tablet', () {
      final BoardMetrics m = BoardMetrics.resolve(
        width: 1024,
        height: 600,
        columns: 7,
        maxPileLength: 13,
        shortestSide: 600,
        isLandscape: true,
      );
      expect(m.layout, BoardLayout.tabletLandscape);
    });
  });

  group('fit-to-height sizing', () {
    test('phone landscape shrinks cards so the fan cannot overflow', () {
      const double height = 340;
      final BoardMetrics m = BoardMetrics.resolve(
        width: 900,
        height: height,
        columns: 7,
        maxPileLength: 19, // a long Klondike fan
        shortestSide: 360,
        isLandscape: true,
      );
      expect(
        _stackedFootprint(m.cardSize.height, 19),
        lessThanOrEqualTo(height + 0.5),
      );
      expect(m.cardSize.width, greaterThan(0));
      expect(
        m.cardSize.height,
        closeTo(m.cardSize.width * BoardMetrics.aspect, 0.01),
      );
    });

    test('portrait stays width-driven when height is plentiful', () {
      const double width = 420;
      const int columns = 7;
      final BoardMetrics m = BoardMetrics.resolve(
        width: width,
        height: 1000,
        columns: columns,
        maxPileLength: 13,
        shortestSide: 420,
        isLandscape: false,
      );
      // Card width fills a tableau column within the true content width
      // (inside the board's outer padding on both edges).
      const double widthBudget =
          (width - 2 * BoardMetrics.pad) / columns - BoardMetrics.pad;
      expect(m.cardSize.width, closeTo(widthBudget, 0.5));
    });

    test('a single-row FreeCell top (8 slots) fits the width', () {
      // Classic FreeCell: 4 free cells + 4 foundations share one top row of 8
      // slots in two trays, above 8 tableau columns. The card must be small
      // enough that the top row does not overflow (the old bug).
      const double width = 400;
      final BoardMetrics m = BoardMetrics.resolve(
        width: width,
        height: 900,
        columns: 8,
        maxPileLength: 8,
        shortestSide: 400,
        isLandscape: false,
        topRows: 1,
        topRowSlots: 8,
        topTrays: 2,
      );
      const double contentWidth = width - 2 * BoardMetrics.pad;
      final double topRowWidth =
          8 * m.cardSize.width +
          6 * BoardMetrics.pad + // pads between the 8 slots (across - trays)
          2 * 2 * BoardMetrics.trayPad; // two trays, horizontal chrome each
      expect(topRowWidth, lessThanOrEqualTo(contentWidth + 0.5));
    });

    test('a 6-cell FreeCell top uses two rows that fit width and height', () {
      const double width = 400;
      const double height = 800;
      final BoardMetrics m = BoardMetrics.resolve(
        width: width,
        height: height,
        columns: 8,
        maxPileLength: 7,
        shortestSide: 400,
        isLandscape: false,
        topRows: 2,
        topRowSlots: 6, // the free-cell row is the taller line
        topTrays: 1,
      );
      expect(
        _twoRowTopFootprint(m.cardSize.height, 7),
        lessThanOrEqualTo(height + 0.5),
      );
      const double contentWidth = width - 2 * BoardMetrics.pad;
      final double topLineWidth =
          6 * m.cardSize.width +
          5 * BoardMetrics.pad +
          2 * BoardMetrics.trayPad;
      expect(topLineWidth, lessThanOrEqualTo(contentWidth + 0.5));
    });

    test(
      'tablet landscape fits the full-height tableau and the side column',
      () {
        const double width = 1200;
        const double height = 780;
        const int columns = 7;
        final BoardMetrics m = BoardMetrics.resolve(
          width: width,
          height: height,
          columns: columns,
          maxPileLength: 19,
          shortestSide: 800,
          isLandscape: true,
        );
        expect(
          _tabletFootprint(m.cardSize.height, 19),
          lessThanOrEqualTo(height + 0.5),
        );
        // The tableau plus the side column must fit the width.
        final double tableauWidth =
            columns * (m.cardSize.width + BoardMetrics.pad);
        expect(
          tableauWidth + m.sideColumnWidth,
          lessThanOrEqualTo(width + 0.5),
        );
      },
    );

    test(
      'tablet landscape shrinks cards so the side stack cannot overflow',
      () {
        // A short tableau fan leaves the tableau budget generous, so the
        // four-tall side column (free cells / foundations) is what must bind.
        const double height = 520;
        final BoardMetrics m = BoardMetrics.resolve(
          width: 1200,
          height: height,
          columns: 8,
          maxPileLength: 5,
          shortestSide: 800,
          isLandscape: true,
          sideStackCount: 4,
        );
        expect(
          _sideColumnFootprint(m.cardSize.height, 4),
          lessThanOrEqualTo(height + 0.5),
        );
      },
    );

    test('a short fan is capped to the opening-deal card size', () {
      // Phone landscape, near a win: only two cards left in the tallest
      // tableau column. Without a cap the height budget would balloon the
      // cards; with an opening reference of 7 they must size exactly as the
      // opening deal (7-long fan) did, never larger.
      const double width = 900;
      const double height = 340;
      final BoardMetrics opening = BoardMetrics.resolve(
        width: width,
        height: height,
        columns: 7,
        maxPileLength: 7,
        shortestSide: 360,
        isLandscape: true,
      );
      final BoardMetrics nearWin = BoardMetrics.resolve(
        width: width,
        height: height,
        columns: 7,
        maxPileLength: 2,
        shortestSide: 360,
        isLandscape: true,
        openingFanLength: 7,
      );
      expect(nearWin.cardSize.width, closeTo(opening.cardSize.width, 0.01));
      expect(nearWin.cardSize.height, closeTo(opening.cardSize.height, 0.01));
    });

    test('a fan longer than the opening reference is not capped', () {
      // A built descending run can exceed the opening 7; the card must keep
      // shrinking to fit it, exactly as it would with no reference at all.
      const double width = 900;
      const double height = 340;
      final BoardMetrics capped = BoardMetrics.resolve(
        width: width,
        height: height,
        columns: 7,
        maxPileLength: 15,
        shortestSide: 360,
        isLandscape: true,
        openingFanLength: 7,
      );
      final BoardMetrics uncapped = BoardMetrics.resolve(
        width: width,
        height: height,
        columns: 7,
        maxPileLength: 15,
        shortestSide: 360,
        isLandscape: true,
      );
      expect(capped.cardSize.width, closeTo(uncapped.cardSize.width, 0.01));
    });

    test('card width never collapses below the readable minimum', () {
      final BoardMetrics m = BoardMetrics.resolve(
        width: 120,
        height: 90,
        columns: 7,
        maxPileLength: 19,
        shortestSide: 90,
        isLandscape: true,
      );
      expect(m.cardSize.width, greaterThanOrEqualTo(BoardMetrics.minCardWidth));
    });
  });
}
