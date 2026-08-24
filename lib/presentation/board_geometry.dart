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

/// The two kinds of zone tray drawn behind the top-area (or side-column)
/// groups: warm gold behind the foundations (aces build up here), cool felt
/// behind the parking zone (free cells / stock+waste).
enum TrayKind { foundation, parking }

/// A translucent panel drawn *behind* a group of slots — the foundations or the
/// parking zone — to visually bind them together. Its [rect] is the group's
/// bounding box expanded by [BoardMetrics.trayInset] on every side.
@immutable
class TrayPlacement {
  const TrayPlacement({required this.kind, required this.rect});

  final TrayKind kind;
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
    required this.size,
    required this.cards,
    required this.slots,
    required this.trays,
    required this.dropTargets,
  });

  final BoardMetrics metrics;

  /// The resolved board area (the [LayoutBuilder] constraints the geometry was
  /// laid out into). Board-local origin `(0,0)` is its top-left.
  final Size size;

  final List<CardPlacement> cards;
  final List<SlotPlacement> slots;
  final List<TrayPlacement> trays;
  final Map<int, Rect> dropTargets;

  Size get cardSize => metrics.cardSize;

  static const double _wasteStep = 0.16; // matches PileView._wasteFanStep

  /// Resolve every card, slot and drop-target rect for the given board space.
  ///
  /// [cards] is returned in paint order (pile-major: stock/waste/free-cell,
  /// then foundations, then tableau; each pile bottom-to-top).
  ///
  /// [revealFoundationStacks] places every card in a foundation pile (all at
  /// the same rect, bottom-to-top) instead of just its top card. Normal play
  /// never needs to see or animate a buried foundation card, so this defaults
  /// to `false`; the win cascade turns it on so it has a placement for every
  /// card it peels off.
  static BoardGeometry resolve({
    required GameState game,
    required double width,
    required double height,
    required double shortestSide,
    required bool isLandscape,
    required int wasteVisibleCount,
    int openingFanLength = 0,
    bool revealFoundationStacks = false,
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

    // The top area normally sits on one row (free cells / stock+waste on the
    // left, foundations on the right). In portrait, when those groups together
    // would out-number the tableau columns (6-cell FreeCell: 6 + 4 > 8) it
    // splits into two rows — foundations above, free cells below. Landscape has
    // the width to keep them side by side, so it stays on one row. Mirrors the
    // rule the old `board.dart` carried before the geometry rewrite.
    final bool twoRowTop =
        !isLandscape && upper.length + foundations.length > tableau.length;
    final int topRows = twoRowTop ? 2 : 1;
    // The widest single top line, so cards can be sized to fit its width and its
    // zone-tray chrome. One row carries both trays (parking + foundations) side
    // by side; two rows carry one tray each, so the wider line binds.
    final int topRowSlots = twoRowTop
        ? math.max(upper.length, foundations.length)
        : upper.length + foundations.length;
    final int topTrays = twoRowTop ? 1 : 2;

    final BoardMetrics metrics = BoardMetrics.resolve(
      width: width,
      height: height,
      columns: tableau.length,
      maxPileLength: maxPileLength,
      shortestSide: shortestSide,
      isLandscape: isLandscape,
      sideStackCount: math.max(upper.length, foundations.length),
      topRows: topRows,
      topRowSlots: topRowSlots,
      topTrays: topTrays,
      openingFanLength: openingFanLength,
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
      twoRowTop: twoRowTop,
      revealFoundationStacks: revealFoundationStacks,
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
      size: Size(width, height),
      cards: builder.cards,
      slots: builder.slots,
      trays: builder.trays,
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
    required this.twoRowTop,
    required this.revealFoundationStacks,
  });

  final GameState game;
  final BoardMetrics metrics;
  final double width;
  final double height;
  final List<int> upper;
  final List<int> foundations;
  final List<int> tableau;
  final int wasteVisibleCount;

  /// Whether the top area splits into two rows (foundations above, free cells
  /// below) because the two groups together out-number the tableau columns.
  final bool twoRowTop;

  /// See [BoardGeometry.resolve]'s parameter of the same name.
  final bool revealFoundationStacks;

  final List<CardPlacement> cards = <CardPlacement>[];
  final List<SlotPlacement> slots = <SlotPlacement>[];
  final List<TrayPlacement> trays = <TrayPlacement>[];
  final Map<int, Rect> dropTargets = <int, Rect>{};

  static const double _pad = BoardMetrics.pad;
  static const double _trayInset = BoardMetrics.trayInset;

  double get _cardW => metrics.cardSize.width;
  double get _cardH => metrics.cardSize.height;

  /// Records a single-card (stock/foundation/free-cell) or empty slot at
  /// [origin]. Returns the board-local rect it occupies.
  ///
  /// A foundation pile places only its top card, unless
  /// [revealFoundationStacks] is on — then every card in the pile gets its own
  /// placement, all at [origin], bottom-to-top (see [BoardGeometry.resolve]).
  Rect _placeSingleOrSlot(int pileIndex, Offset origin) {
    final Pile pile = game.pileAt(pileIndex);
    final Rect slotRect = origin & metrics.cardSize;
    if (pile.isEmpty) {
      slots.add(
        SlotPlacement(pileIndex: pileIndex, kind: pile.kind, rect: slotRect),
      );
      dropTargets[pileIndex] = slotRect;
      return slotRect;
    }
    final int topIndex = pile.length - 1;
    if (revealFoundationStacks && pile.kind == PileKind.foundation) {
      for (int i = 0; i <= topIndex; i++) {
        cards.add(
          CardPlacement(
            card: pile.cards[i],
            pileIndex: pileIndex,
            indexInPile: i,
            isTop: i == topIndex,
            rect: slotRect,
          ),
        );
      }
    } else {
      cards.add(
        CardPlacement(
          card: pile.cards[topIndex],
          pileIndex: pileIndex,
          indexInPile: topIndex,
          isTop: true,
          rect: slotRect,
        ),
      );
    }
    dropTargets[pileIndex] = slotRect;
    return slotRect;
  }

  /// Records the waste's fanned cards (last [wasteVisibleCount] + a backing
  /// card when older draws remain), mirroring PileView._wasteFan. Returns the
  /// board-local rect the fan occupies.
  Rect _placeWaste(int pileIndex, Offset origin) {
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
      return slotRect;
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
    final Rect fanRect = origin & Size(fanWidth, _cardH);
    dropTargets[pileIndex] = fanRect;
    return fanRect;
  }

  /// Records a fanned tableau column at [origin] with the given gaps.
  ///
  /// [regionBottom] is the y-coordinate of the bottom of the tableau area. The
  /// column's drop target stretches down to it (never shorter than the cards
  /// themselves), so a card released in the empty felt below a short column
  /// still lands on that column — that was clearly the player's intent.
  void _placeTableau(
    int pileIndex,
    Offset origin,
    double upGap,
    double downGap,
    double regionBottom,
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
      dropTargets[pileIndex] = _tableauDropTarget(
        origin,
        slotRect.bottom,
        regionBottom,
      );
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
    dropTargets[pileIndex] = _tableauDropTarget(
      origin,
      lastTop + _cardH,
      regionBottom,
    );
  }

  /// A tableau drop target one card wide, from [origin] down to [regionBottom]
  /// — but never above [cardsBottom] when a long fan overruns the region.
  Rect _tableauDropTarget(
    Offset origin,
    double cardsBottom,
    double regionBottom,
  ) {
    final double bottom = math.max(cardsBottom, regionBottom);
    return Rect.fromLTWH(origin.dx, origin.dy, _cardW, bottom - origin.dy);
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
    // Floor matches the fraction BoardMetrics reserves vertical room for, so a
    // fan compressed to its tightest still leaves a covered card's rank digit
    // peeking out rather than collapsing to an unreadable sliver.
    return math.max(
      _cardH * BoardMetrics.minFanFactor,
      math.min(defaultGap, fitGap),
    );
  }

  /// The width of a horizontal group of [slotCount] slots plus its tray chrome
  /// ([_trayInset] on each side).
  double _horizontalTrayWidth(int slotCount) =>
      slotCount * _cardW + (slotCount - 1) * _pad + 2 * _trayInset;

  /// The width a horizontal run of [slotCount] cards occupies (no tray chrome).
  double _groupWidth(int slotCount) =>
      slotCount * _cardW + (slotCount - 1) * _pad;

  /// Places [indices] left-to-right from ([x], [y]), each [_cardW] + [_pad]
  /// apart, and returns the union of the rects they occupy (null if empty).
  Rect? _placeHorizontalGroup(List<int> indices, double x, double y) {
    Rect? bounds;
    double cx = x;
    for (final int i in indices) {
      final Rect r = game.pileAt(i).kind == PileKind.waste
          ? _placeWaste(i, Offset(cx, y))
          : _placeSingleOrSlot(i, Offset(cx, y));
      bounds = bounds == null ? r : bounds.expandToInclude(r);
      cx += _cardW + _pad;
    }
    return bounds;
  }

  /// Records a [kind] tray wrapping [groupBounds] with [_trayInset] of chrome on
  /// every side. No-op when the group placed nothing (an all-empty board still
  /// places slot markers, so this is only null defensively).
  void _addTray(TrayKind kind, Rect? groupBounds) {
    if (groupBounds == null) {
      return;
    }
    trays.add(TrayPlacement(kind: kind, rect: groupBounds.inflate(_trayInset)));
  }

  void stacked() {
    final bool centred = metrics.layout == BoardLayout.phoneLandscape;
    final int cols = tableau.length;
    final int topRows = twoRowTop ? 2 : 1;
    // A tray-wrapped card row is one card tall plus a tray inset above and
    // below; rows are separated by a pad.
    final double rowHeight = _cardH + 2 * _trayInset;
    final double topAreaHeight = topRows * rowHeight + (topRows - 1) * _pad;

    final double originX;
    final double innerW;
    if (centred) {
      // Centre the content, but widen the frame so both top trays fit beside the
      // tableau — matching the old widget layout, so the parking and foundation
      // trays never overlap when the top row is wider than the tableau.
      final double tableauInnerW = _groupWidth(cols);
      final double topInnerW = twoRowTop
          ? math.max(
              _horizontalTrayWidth(upper.length),
              _horizontalTrayWidth(foundations.length),
            )
          : _horizontalTrayWidth(upper.length) +
                _horizontalTrayWidth(foundations.length);
      innerW = math.max(tableauInnerW, topInnerW);
      originX = (width - (innerW + 2 * _pad)) / 2 + _pad;
    } else {
      originX = _pad;
      innerW = width - 2 * _pad;
    }
    const double topY = _pad;
    const double slotY0 = topY + _trayInset;

    if (twoRowTop) {
      // Two rows: foundations on top, free cells (parking) below — both
      // left-aligned. Portrait-only, when the free cells + foundations would
      // overflow a single row (6-cell FreeCell).
      final Rect? foundBounds = _placeHorizontalGroup(
        foundations,
        originX + _trayInset,
        slotY0,
      );
      final Rect? parkBounds = _placeHorizontalGroup(
        upper,
        originX + _trayInset,
        topY + rowHeight + _pad + _trayInset,
      );
      _addTray(TrayKind.foundation, foundBounds);
      _addTray(TrayKind.parking, parkBounds);
    } else {
      // One row: the parking tray (free cells / stock+waste) left-aligned, the
      // foundation tray right-aligned to the inner edge.
      final Rect? parkBounds = _placeHorizontalGroup(
        upper,
        originX + _trayInset,
        slotY0,
      );
      final double foundStartX =
          originX + innerW - _trayInset - _groupWidth(foundations.length);
      final Rect? foundBounds = _placeHorizontalGroup(
        foundations,
        foundStartX,
        slotY0,
      );
      _addTray(TrayKind.parking, parkBounds);
      _addTray(TrayKind.foundation, foundBounds);
    }

    // Tableau row.
    final double tableauTop = topY + topAreaHeight + _pad;
    final double usableHeight = height - 2 * _pad;
    final double bottomHeight = math.max(
      _cardH,
      usableHeight - topAreaHeight - _pad,
    );
    final double upGap = _fanGap(bottomHeight);
    final double downGap = upGap * 0.5;
    final double colW = innerW / cols;
    final double tableauBottom = tableauTop + bottomHeight;
    for (int j = 0; j < cols; j++) {
      final double centerX = originX + colW * j + colW / 2;
      final double cardX = centerX - _cardW / 2;
      _placeTableau(
        tableau[j],
        Offset(cardX, tableauTop),
        upGap,
        downGap,
        tableauBottom,
      );
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
    final double tableauBottom = topY + bottomHeight;
    for (int j = 0; j < cols; j++) {
      final double centerX = _pad + colW * j + colW / 2;
      _placeTableau(
        tableau[j],
        Offset(centerX - _cardW / 2, topY),
        upGap,
        downGap,
        tableauBottom,
      );
    }

    // Right side column: two tray-wrapped sub-columns (parking left, foundations
    // right). sideColumnWidth = 2*cardW + 3*pad + 4*trayInset holds both trays
    // (each cardW + 2*trayInset wide), a pad between them and a pad inset each
    // side.
    final double sideLeft = _pad + tableauAreaW + _pad;
    final double parkSlotX = sideLeft + _pad + _trayInset;
    final double foundSlotX = parkSlotX + _cardW + 2 * _trayInset + _pad;
    const double slotY0 = topY + _trayInset;

    Rect? parkBounds;
    for (int i = 0; i < upper.length; i++) {
      final double y = slotY0 + i * (_cardH + _pad);
      final int idx = upper[i];
      final Rect r = game.pileAt(idx).kind == PileKind.waste
          ? _placeWaste(idx, Offset(parkSlotX, y))
          : _placeSingleOrSlot(idx, Offset(parkSlotX, y));
      parkBounds = parkBounds == null ? r : parkBounds.expandToInclude(r);
    }
    Rect? foundBounds;
    for (int i = 0; i < foundations.length; i++) {
      final double y = slotY0 + i * (_cardH + _pad);
      final Rect r = _placeSingleOrSlot(foundations[i], Offset(foundSlotX, y));
      foundBounds = foundBounds == null ? r : foundBounds.expandToInclude(r);
    }
    _addTray(TrayKind.parking, parkBounds);
    _addTray(TrayKind.foundation, foundBounds);
  }
}
