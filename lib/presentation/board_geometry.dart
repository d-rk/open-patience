import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../core/card.dart';
import '../core/game_state.dart';
import '../core/pile.dart';
import 'board_metrics.dart';

export 'board_metrics.dart' show BoardLayout, BoardMetrics;

/// Stable identity of a card within a single 52-card deck: `(suit, rank)`,
/// ignoring `faceUp` (which changes on a flip). Used as the animation key so
/// `AnimatedPositioned` can recognise the same card across a move.
@immutable
class CardKey {
  const CardKey(this.suit, this.rank);

  factory CardKey.of(Card card) => CardKey(card.suit, card.rank);

  final Suit suit;
  final int rank;

  ValueKey<String> get widgetKey =>
      ValueKey<String>('card-${suit.index}-$rank');

  @override
  bool operator ==(Object other) =>
      other is CardKey && other.suit == suit && other.rank == rank;

  @override
  int get hashCode => Object.hash(suit, rank);
}

/// One card placed on the board: the card, where it sits (pile + index within
/// the pile), whether it is the interactive top card, and the board-local rect
/// it occupies.
@immutable
class CardPlacement {
  const CardPlacement({
    required this.card,
    required this.pileIndex,
    required this.indexInPile,
    required this.isTop,
    required this.rect,
  });

  final Card card;
  final int pileIndex;
  final int indexInPile;
  final bool isTop;
  final Rect rect;

  CardKey get key => CardKey.of(card);
}

/// An empty pile's slot-marker rect (foundation / free-cell / stock / tableau).
@immutable
class SlotPlacement {
  const SlotPlacement({
    required this.pileIndex,
    required this.kind,
    required this.rect,
  });

  final int pileIndex;
  final PileKind kind;
  final Rect rect;
}

/// The pure, measurement-free resolution of a whole board: every card's
/// board-local [Rect], every empty pile's slot rect, and a drop-target rect per
/// pile. Computed from a [GameState] and the available space via
/// [BoardGeometry.resolve] — no runtime widget measurement, which is what lets
/// card moves animate without layout glitches. Board-local origin `(0,0)` is the
/// top-left of the resolved area. Porting the arithmetic from `board.dart` and
/// `pile_view.dart` into explicit coordinates.
@immutable
class BoardGeometry {
  const BoardGeometry({
    required this.metrics,
    required this.cards,
    required this.slots,
    required this.dropTargets,
  });

  final BoardMetrics metrics;
  final List<CardPlacement> cards;
  final List<SlotPlacement> slots;
  final Map<int, Rect> dropTargets;

  Size get cardSize => metrics.cardSize;

  static const double _wasteStep = 0.16; // matches PileView._wasteFanStep

  /// Resolve every card, slot and drop-target rect for the given board space.
  ///
  /// [cards] is returned in paint order (pile-major: stock/waste/free-cell,
  /// then foundations, then tableau; each pile bottom-to-top).
  static BoardGeometry resolve({
    required GameState game,
    required double width,
    required double height,
    required double shortestSide,
    required bool isLandscape,
    required int wasteVisibleCount,
  }) {
    final List<int> upper = <int>[];
    final List<int> foundations = <int>[];
    final List<int> tableau = <int>[];
    for (int i = 0; i < game.piles.length; i++) {
      switch (game.pileAt(i).kind) {
        case PileKind.stock:
        case PileKind.waste:
        case PileKind.freecell:
          upper.add(i);
        case PileKind.foundation:
          foundations.add(i);
        case PileKind.tableau:
          tableau.add(i);
      }
    }

    int maxPileLength = 1;
    for (final int i in tableau) {
      maxPileLength = math.max(maxPileLength, game.pileAt(i).length);
    }

    final BoardMetrics metrics = BoardMetrics.resolve(
      width: width,
      height: height,
      columns: tableau.length,
      maxPileLength: maxPileLength,
      shortestSide: shortestSide,
      isLandscape: isLandscape,
      sideStackCount: math.max(upper.length, foundations.length),
    );

    final _Builder builder = _Builder(
      game: game,
      metrics: metrics,
      width: width,
      height: height,
      upper: upper,
      foundations: foundations,
      tableau: tableau,
      wasteVisibleCount: wasteVisibleCount,
    );
    switch (metrics.layout) {
      case BoardLayout.portrait:
      case BoardLayout.phoneLandscape:
        builder.stacked();
      case BoardLayout.tabletLandscape:
        builder.tablet(); // implemented in Task 4
    }
    return BoardGeometry(
      metrics: metrics,
      cards: builder.cards,
      slots: builder.slots,
      dropTargets: builder.dropTargets,
    );
  }
}

/// Mutable accumulator that walks the piles and records placements. Kept
/// private: callers only ever see the immutable [BoardGeometry].
class _Builder {
  _Builder({
    required this.game,
    required this.metrics,
    required this.width,
    required this.height,
    required this.upper,
    required this.foundations,
    required this.tableau,
    required this.wasteVisibleCount,
  });

  final GameState game;
  final BoardMetrics metrics;
  final double width;
  final double height;
  final List<int> upper;
  final List<int> foundations;
  final List<int> tableau;
  final int wasteVisibleCount;

  final List<CardPlacement> cards = <CardPlacement>[];
  final List<SlotPlacement> slots = <SlotPlacement>[];
  final Map<int, Rect> dropTargets = <int, Rect>{};

  static const double _pad = BoardMetrics.pad;

  double get _cardW => metrics.cardSize.width;
  double get _cardH => metrics.cardSize.height;

  /// Records a single-card (stock/foundation/free-cell) or empty slot at
  /// [origin].
  void _placeSingleOrSlot(int pileIndex, Offset origin) {
    final Pile pile = game.pileAt(pileIndex);
    final Rect slotRect = origin & metrics.cardSize;
    if (pile.isEmpty) {
      slots.add(
        SlotPlacement(pileIndex: pileIndex, kind: pile.kind, rect: slotRect),
      );
      dropTargets[pileIndex] = slotRect;
      return;
    }
    final int topIndex = pile.length - 1;
    cards.add(
      CardPlacement(
        card: pile.cards[topIndex],
        pileIndex: pileIndex,
        indexInPile: topIndex,
        isTop: true,
        rect: slotRect,
      ),
    );
    dropTargets[pileIndex] = slotRect;
  }

  /// Records the waste's fanned cards (last [wasteVisibleCount] + a backing
  /// card when older draws remain), mirroring PileView._wasteFan.
  void _placeWaste(int pileIndex, Offset origin) {
    final Pile pile = game.pileAt(pileIndex);
    if (pile.isEmpty) {
      final Rect slotRect = origin & metrics.cardSize;
      slots.add(
        SlotPlacement(
          pileIndex: pileIndex,
          kind: PileKind.waste,
          rect: slotRect,
        ),
      );
      dropTargets[pileIndex] = slotRect;
      return;
    }
    final int visible = math.min(wasteVisibleCount, pile.length);
    final double step = _cardW * BoardGeometry._wasteStep;
    final int oldestVisible = pile.length - visible;
    final int topIndex = pile.length - 1;

    if (oldestVisible > 0) {
      // One backing card at the oldest-visible slot (revealed mid-drag).
      cards.add(
        CardPlacement(
          card: pile.cards[oldestVisible - 1],
          pileIndex: pileIndex,
          indexInPile: oldestVisible - 1,
          isTop: false,
          rect: origin & metrics.cardSize,
        ),
      );
    }
    for (int i = 0; i < visible; i++) {
      final int idx = oldestVisible + i;
      final Offset o = origin.translate(step * i, 0);
      cards.add(
        CardPlacement(
          card: pile.cards[idx],
          pileIndex: pileIndex,
          indexInPile: idx,
          isTop: idx == topIndex,
          rect: o & metrics.cardSize,
        ),
      );
    }
    final double fanWidth = _cardW + step * (visible - 1);
    dropTargets[pileIndex] = origin & Size(fanWidth, _cardH);
  }

  /// Records a fanned tableau column at [origin] with the given gaps.
  void _placeTableau(
    int pileIndex,
    Offset origin,
    double upGap,
    double downGap,
  ) {
    final Pile pile = game.pileAt(pileIndex);
    if (pile.isEmpty) {
      final Rect slotRect = origin & metrics.cardSize;
      slots.add(
        SlotPlacement(
          pileIndex: pileIndex,
          kind: PileKind.tableau,
          rect: slotRect,
        ),
      );
      dropTargets[pileIndex] = slotRect;
      return;
    }
    double top = origin.dy;
    double lastTop = top;
    for (int i = 0; i < pile.length; i++) {
      final Card card = pile.cards[i];
      lastTop = top;
      cards.add(
        CardPlacement(
          card: card,
          pileIndex: pileIndex,
          indexInPile: i,
          isTop: i == pile.length - 1,
          rect: Offset(origin.dx, top) & metrics.cardSize,
        ),
      );
      top += card.faceUp ? upGap : downGap;
    }
    dropTargets[pileIndex] = Rect.fromLTWH(
      origin.dx,
      origin.dy,
      _cardW,
      (lastTop - origin.dy) + _cardH,
    );
  }

  double _fanGap(double bottomHeight) {
    final double defaultGap = _cardH * 0.30;
    int maxLen = 1;
    for (final int i in tableau) {
      maxLen = math.max(maxLen, game.pileAt(i).length);
    }
    if (maxLen <= 1) {
      return defaultGap;
    }
    final double fitGap = (bottomHeight - _cardH) / (maxLen - 1);
    return math.max(_cardH * 0.06, math.min(defaultGap, fitGap));
  }

  void stacked() {
    final bool centred = metrics.layout == BoardLayout.phoneLandscape;
    final int cols = tableau.length;
    final double originX;
    final double innerW;
    if (centred) {
      final double contentW = _cardW * cols + _pad * (cols + 1);
      originX = (width - contentW) / 2 + _pad;
      innerW = _cardW * cols + _pad * (cols - 1);
    } else {
      originX = _pad;
      innerW = width - 2 * _pad;
    }
    const double topY = _pad;

    // Top row: upper piles left-aligned, foundations right-aligned.
    double ux = originX;
    for (final int i in upper) {
      if (game.pileAt(i).kind == PileKind.waste) {
        _placeWaste(i, Offset(ux, topY));
      } else {
        _placeSingleOrSlot(i, Offset(ux, topY));
      }
      ux += _cardW + _pad;
    }
    double fx = originX + innerW;
    for (int k = foundations.length - 1; k >= 0; k--) {
      fx -= _cardW;
      _placeSingleOrSlot(foundations[k], Offset(fx, topY));
      fx -= _pad;
    }

    // Tableau row.
    final double tableauTop = topY + _cardH + _pad;
    final double usableHeight = height - 2 * _pad;
    final double bottomHeight = math.max(_cardH, usableHeight - _cardH - _pad);
    final double upGap = _fanGap(bottomHeight);
    final double downGap = upGap * 0.5;
    final double colW = innerW / cols;
    for (int j = 0; j < cols; j++) {
      final double centerX = originX + colW * j + colW / 2;
      final double cardX = centerX - _cardW / 2;
      _placeTableau(tableau[j], Offset(cardX, tableauTop), upGap, downGap);
    }
  }

  void tablet() {
    final int cols = tableau.length;
    final double sideW = metrics.sideColumnWidth;
    const double topY = _pad;
    final double tableauAreaW = (width - 2 * _pad) - _pad - sideW;
    final double colW = tableauAreaW / cols;

    // Tableau on the left, full height.
    final double bottomHeight = math.max(_cardH, height - 2 * _pad);
    final double upGap = _fanGap(bottomHeight);
    final double downGap = upGap * 0.5;
    for (int j = 0; j < cols; j++) {
      final double centerX = _pad + colW * j + colW / 2;
      _placeTableau(
        tableau[j],
        Offset(centerX - _cardW / 2, topY),
        upGap,
        downGap,
      );
    }

    // Right side column: two centered sub-columns (upper left, foundations
    // right). The min-width row (2*cardW + pad) is centred in sideColumnWidth
    // (2*cardW + 3*pad), so it is inset one pad on each side.
    final double sideLeft = _pad + tableauAreaW + _pad;
    final double upperX = sideLeft + _pad;
    final double foundX = upperX + _cardW + _pad;
    for (int i = 0; i < upper.length; i++) {
      final double y = topY + i * (_cardH + _pad);
      final int idx = upper[i];
      if (game.pileAt(idx).kind == PileKind.waste) {
        _placeWaste(idx, Offset(upperX, y));
      } else {
        _placeSingleOrSlot(idx, Offset(upperX, y));
      }
    }
    for (int i = 0; i < foundations.length; i++) {
      final double y = topY + i * (_cardH + _pad);
      _placeSingleOrSlot(foundations[i], Offset(foundX, y));
    }
  }
}
