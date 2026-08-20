import 'dart:math' as math;

import 'package:flutter/material.dart' hide Card;

import '../core/card.dart';
import '../core/pile.dart';
import '../ui/theme/game_palette.dart';
import 'card_view.dart';

/// Keys for the role markers on empty slots, so tests (and future callers) can
/// find them without reaching into glyph internals.
const Key foundationSlotMarkerKey = Key('foundationSlotMarker');
const Key parkSlotMarkerKey = Key('parkSlotMarker');

/// Renders one [Pile] and forwards input as callbacks. Tableau piles fan their
/// cards vertically; stock/foundation/free-cell piles stack (only the top card
/// is shown and interactive); the waste pile fans its last [wasteVisibleCount]
/// draws horizontally (see [_wasteFan]). The whole pile area is a
/// [DragTarget], so a dropped card is routed to [onDrop] with no legality
/// decision made here.
class PileView extends StatelessWidget {
  const PileView({
    required this.pile,
    required this.pileIndex,
    required this.cardSize,
    this.faceUpGap,
    this.faceDownGap,
    this.wasteVisibleCount = 1,
    this.onCardTap,
    this.onCardDoubleTap,
    this.onPileTap,
    this.onDrop,
    super.key,
  });

  final Pile pile;
  final int pileIndex;
  final Size cardSize;
  final double? faceUpGap;
  final double? faceDownGap;

  /// How many of the waste pile's most recent draws are fanned out and
  /// visible at rest — the variant's draw count (1 or 3). Ignored for every
  /// other pile kind.
  final int wasteVisibleCount;

  /// Tap on the interactive (top) card, by its index within the pile.
  final void Function(int cardIndex)? onCardTap;

  /// Double-tap on the interactive (top) card, by its index within the pile.
  final void Function(int cardIndex)? onCardDoubleTap;

  /// Tap on the pile itself (used by the stock to draw/recycle).
  final VoidCallback? onPileTap;

  /// A card was dropped on this pile.
  final void Function(CardDragData data)? onDrop;

  bool get _isTableau => pile.kind == PileKind.tableau;

  double get _upGap => faceUpGap ?? cardSize.height * 0.30;
  double get _downGap => faceDownGap ?? cardSize.height * 0.14;

  @override
  Widget build(BuildContext context) {
    final Widget content = _content();
    if (onDrop == null) {
      return content;
    }
    return DragTarget<CardDragData>(
      onWillAcceptWithDetails: (DragTargetDetails<CardDragData> details) =>
          details.data.fromPile != pileIndex,
      onAcceptWithDetails: (DragTargetDetails<CardDragData> details) =>
          onDrop!(details.data),
      builder: (BuildContext context, _, _) => content,
    );
  }

  Widget _content() {
    if (pile.isEmpty) {
      return _placeholder();
    }
    if (_isTableau) {
      return _fanned();
    }
    return _stacked();
  }

  /// An empty pile: a subtle outlined slot that still accepts drops and taps.
  /// Foundations and free cells carry a role-distinguishing wash and ghost
  /// marker so a player can tell aces-here from park-here at a glance.
  Widget _placeholder() {
    final Widget slot = Container(
      width: cardSize.width,
      height: cardSize.height,
      decoration: BoxDecoration(
        color: _slotFill,
        borderRadius: BorderRadius.circular(cardSize.width * 0.12),
        border: Border.all(color: GamePalette.pileSlotOutline, width: 1.5),
      ),
      child: _slotMarker(),
    );
    if (onPileTap == null) {
      return slot;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPileTap,
      child: slot,
    );
  }

  Color? get _slotFill {
    switch (pile.kind) {
      case PileKind.foundation:
        return GamePalette.foundationSlotFill;
      case PileKind.freecell:
        return GamePalette.freecellSlotFill;
      case PileKind.stock:
      case PileKind.waste:
      case PileKind.tableau:
        return null;
    }
  }

  Widget? _slotMarker() {
    switch (pile.kind) {
      case PileKind.stock:
        return const Center(
          child: Icon(Icons.refresh, color: GamePalette.gold),
        );
      case PileKind.foundation:
        return Center(child: _foundationMarker());
      case PileKind.freecell:
      case PileKind.tableau:
        return Center(child: _parkMarker());
      case PileKind.waste:
        return null;
    }
  }

  /// A 2x2 cluster of all four suit pips: "suits go home here". Foundations are
  /// not suit-locked, so no single suit is shown. Suit glyphs stay on the system
  /// font for reliable Unicode rendering (per the design language), but that
  /// font renders them as colored glyphs (red hearts/diamonds, black
  /// spades/clubs) on some platforms — [ColorFiltered] flattens them to a
  /// single muted tone so they read as a quiet marker, not a loud suit chart.
  Widget _foundationMarker() {
    final TextStyle glyph = TextStyle(
      color: GamePalette.slotGlyph,
      fontSize: cardSize.width * 0.26,
      height: 1.0,
    );
    Widget row(String left, String right) => Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(left, style: glyph),
        SizedBox(width: cardSize.width * 0.06),
        Text(right, style: glyph),
      ],
    );
    return ColorFiltered(
      key: foundationSlotMarkerKey,
      colorFilter: const ColorFilter.mode(
        GamePalette.slotGlyph,
        BlendMode.srcIn,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          row('♠', '♥'),
          SizedBox(height: cardSize.width * 0.04),
          row('♦', '♣'),
        ],
      ),
    );
  }

  /// A hollow diamond: a quiet "resting place" for a parked card, or (on an
  /// empty tableau column) for a king-headed run.
  Widget _parkMarker() {
    final double side = cardSize.width * 0.30;
    return Transform.rotate(
      key: parkSlotMarkerKey,
      angle: math.pi / 4,
      child: Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          border: Border.all(color: GamePalette.slotGlyph, width: 2),
          borderRadius: BorderRadius.circular(side * 0.14),
        ),
      ),
    );
  }

  Widget _stacked() {
    final Card top = pile.topCard!;
    final int topIndex = pile.length - 1;

    // The stock is tapped, never dragged: show a back and forward the tap.
    if (pile.kind == PileKind.stock) {
      final Widget back = CardFace(card: top.faceDownCard, size: cardSize);
      if (onPileTap == null) {
        return back;
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPileTap,
        child: back,
      );
    }

    if (pile.kind == PileKind.waste) {
      return _wasteFan(topIndex);
    }

    return CardView(
      card: top,
      size: cardSize,
      dragData: CardDragData(fromPile: pileIndex, cardIndex: topIndex),
      onTap: onCardTap == null ? null : () => onCardTap!(topIndex),
      onDoubleTap: onCardDoubleTap == null
          ? null
          : () => onCardDoubleTap!(topIndex),
    );
  }

  /// A slight fraction of the card width between fanned waste cards — enough
  /// to read each covered card's corner without the tableau's full vertical
  /// fan.
  static const double _wasteFanStep = 0.16;

  /// The waste pile: the last [wasteVisibleCount] draws, fanned with a slight
  /// horizontal offset so a multi-card draw is fully readable (only the most
  /// recent — [topIndex] — is interactive), plus, when older draws remain
  /// underneath, one hidden backing card in the same spot as the oldest
  /// visible card. That backing card is fully covered at rest; it only shows
  /// once the real card above it lifts away mid-drag, which is what makes a
  /// single-card waste correctly reveal the previous draw while dragging.
  Widget _wasteFan(int topIndex) {
    final int visible = math.min(wasteVisibleCount, pile.length);
    final double step = cardSize.width * _wasteFanStep;
    final int oldestVisibleIndex = pile.length - visible;

    final List<Widget> children = <Widget>[
      if (oldestVisibleIndex > 0)
        Positioned(
          left: 0,
          child: CardFace(
            card: pile.cards[oldestVisibleIndex - 1],
            size: cardSize,
          ),
        ),
      for (int i = 0; i < visible; i++)
        Positioned(
          left: step * i,
          child: _wasteCard(oldestVisibleIndex + i, topIndex),
        ),
    ];

    return SizedBox(
      width: cardSize.width + step * (visible - 1),
      height: cardSize.height,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }

  Widget _wasteCard(int cardIndex, int topIndex) {
    final Card card = pile.cards[cardIndex];
    if (cardIndex != topIndex) {
      return CardFace(card: card, size: cardSize);
    }
    return CardView(
      card: card,
      size: cardSize,
      dragData: CardDragData(fromPile: pileIndex, cardIndex: cardIndex),
      onTap: onCardTap == null ? null : () => onCardTap!(cardIndex),
      onDoubleTap: onCardDoubleTap == null
          ? null
          : () => onCardDoubleTap!(cardIndex),
    );
  }

  Widget _fanned() {
    final List<Widget> children = <Widget>[];
    double top = 0;
    double lastTop = 0;
    for (int i = 0; i < pile.length; i++) {
      final Card card = pile.cards[i];
      final bool isTop = i == pile.length - 1;
      lastTop = top;
      children.add(
        Positioned(
          top: top,
          left: 0,
          child: CardView(
            card: card,
            size: cardSize,
            dragData: card.faceUp
                ? CardDragData(fromPile: pileIndex, cardIndex: i)
                : null,
            dragStack: card.faceUp ? pile.cards.sublist(i) : null,
            onTap: isTop && card.faceUp && onCardTap != null
                ? () => onCardTap!(i)
                : null,
            onDoubleTap: isTop && card.faceUp && onCardDoubleTap != null
                ? () => onCardDoubleTap!(i)
                : null,
          ),
        ),
      );
      top += card.faceUp ? _upGap : _downGap;
    }
    return SizedBox(
      width: cardSize.width,
      height: lastTop + cardSize.height,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }
}
