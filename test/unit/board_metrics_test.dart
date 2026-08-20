import 'package:flutter_test/flutter_test.dart';
import 'package:solitaire/presentation/board_metrics.dart';

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
      const double widthBudget =
          (width - BoardMetrics.pad) / columns - BoardMetrics.pad;
      expect(m.cardSize.width, closeTo(widthBudget, 0.5));
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
