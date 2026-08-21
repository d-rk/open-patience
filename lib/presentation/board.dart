import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/game_rules.dart';
import '../core/game_state.dart';
import '../core/games/klondike.dart';
import '../core/pile.dart';
import '../ui/theme/game_motion.dart';
import 'bloc/game_bloc.dart';
import 'bloc/game_bloc_state.dart';
import 'bloc/game_event.dart';
import 'board_geometry.dart';
import 'card_view.dart';
import 'drag_scope.dart';
import 'slot_placeholder.dart';

/// The responsive board. Reads the current [GameState] from the [GameBloc] and
/// resolves every card, slot and drop-target rect for the available space via
/// [BoardGeometry], then paints them into a single positioned [Stack]: one
/// [Positioned] card per placement, one [Positioned] [SlotPlaceholder] per empty
/// pile, and one [Positioned] [DragTarget] hit region per pile. It owns no state
/// and no rules: every gesture is forwarded straight to the bloc as a
/// [GameEvent]. Rebuilds are scoped to *board* changes (piles), so the
/// once-a-second timer tick never repaints it.
class Board extends StatefulWidget {
  const Board({super.key});

  @override
  State<Board> createState() => _BoardState();
}

class _BoardState extends State<Board> {
  @override
  Widget build(BuildContext context) {
    return DragScopeHost(child: _board());
  }

  Widget _board() {
    return BlocBuilder<GameBloc, GameBlocState>(
      buildWhen: (GameBlocState previous, GameBlocState current) =>
          !listEquals(previous.state.piles, current.state.piles),
      builder: (BuildContext context, GameBlocState blocState) {
        final GameState game = blocState.state;
        final MediaQueryData media = MediaQuery.of(context);
        final bool isLandscape = media.orientation == Orientation.landscape;
        final double shortestSide = media.size.shortestSide;
        final int wasteVisibleCount = _wasteVisibleCount(context);
        final bool reduceMotion = media.disableAnimations;
        final Duration moveDuration = GameMotion.resolve(
          GameMotion.move,
          reduceMotion: reduceMotion,
        );

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final BoardGeometry geometry = BoardGeometry.resolve(
              game: game,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              shortestSide: shortestSide,
              isLandscape: isLandscape,
              wasteVisibleCount: wasteVisibleCount,
            );
            return _stack(context, game, geometry, moveDuration);
          },
        );
      },
    );
  }

  /// Paints the whole board as one [Stack], bottom to top: the empty-pile slot
  /// markers first, then every card in [BoardGeometry.cards] paint order
  /// (pile-major, bottom-to-top per pile), then the invisible per-pile
  /// drop-target hit regions on top.
  ///
  /// The drop targets sit *above* the cards deliberately. A [DragTarget]
  /// defaults to [HitTestBehavior.translucent] and its child here is an empty
  /// [SizedBox.expand], so it adds itself to the hit-test path (making the pile
  /// discoverable mid-drag) while still returning `false` — the Stack keeps
  /// testing the cards beneath it, so taps and drag-starts on cards work
  /// unchanged. Placing them *below* the cards instead would let an opaque card
  /// swallow the hit before the [DragScope]'s `IgnorePointer` demotes it a frame
  /// later, so a single-move drop onto an occupied pile would be missed.
  Widget _stack(
    BuildContext context,
    GameState game,
    BoardGeometry geometry,
    Duration moveDuration,
  ) {
    final Size cardSize = geometry.cardSize;
    final List<Widget> children = <Widget>[
      for (final SlotPlacement slot in geometry.slots)
        _positionedSlot(context, slot, cardSize),
      for (final CardPlacement placement in geometry.cards)
        _positionedCard(context, placement, game, cardSize, moveDuration),
      for (final MapEntry<int, Rect> entry in geometry.dropTargets.entries)
        _positionedDropTarget(context, entry.key, entry.value),
    ];
    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _positionedDropTarget(BuildContext context, int pileIndex, Rect rect) {
    return Positioned.fromRect(
      rect: rect,
      child: DragTarget<CardDragData>(
        onWillAcceptWithDetails: (DragTargetDetails<CardDragData> details) =>
            details.data.fromPile != pileIndex,
        onAcceptWithDetails: (DragTargetDetails<CardDragData> details) =>
            _drop(context, details.data, details.offset, pileIndex),
        builder: (BuildContext context, _, _) => const SizedBox.expand(),
      ),
    );
  }

  Widget _positionedSlot(
    BuildContext context,
    SlotPlacement slot,
    Size cardSize,
  ) {
    return Positioned.fromRect(
      rect: slot.rect,
      child: SlotPlaceholder(
        kind: slot.kind,
        cardSize: cardSize,
        onTap: slot.kind == PileKind.stock
            ? () => context.read<GameBloc>().add(
                TapMoveRequested(fromPile: slot.pileIndex),
              )
            : null,
      ),
    );
  }

  Widget _positionedCard(
    BuildContext context,
    CardPlacement placement,
    GameState game,
    Size cardSize,
    Duration moveDuration,
  ) {
    final Pile pile = game.pileAt(placement.pileIndex);
    return AnimatedPositioned(
      key: placement.key.widgetKey,
      duration: moveDuration,
      curve: GameMotion.moveCurve,
      left: placement.rect.left,
      top: placement.rect.top,
      width: placement.rect.width,
      height: placement.rect.height,
      child: _cardWidgetFor(context, placement, pile, cardSize),
    );
  }

  /// Replicates `PileView`'s per-kind card interactivity:
  /// - **stock:** a face-down back forwarding the recycle/draw tap;
  /// - **waste:** the top card is an interactive [CardView], older fanned cards
  ///   (and the hidden backing card) are plain [CardFace]s;
  /// - **foundation / free cell:** the (only) top card is interactive;
  /// - **tableau:** face-up cards are draggable (the whole run rides along),
  ///   with tap/double-tap only on the top face-up card; face-down cards are
  ///   plain [CardFace]s.
  Widget _cardWidgetFor(
    BuildContext context,
    CardPlacement placement,
    Pile pile,
    Size cardSize,
  ) {
    final int idx = placement.pileIndex;
    final int cardIndex = placement.indexInPile;
    switch (pile.kind) {
      case PileKind.stock:
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              context.read<GameBloc>().add(TapMoveRequested(fromPile: idx)),
          child: CardFace(card: placement.card.faceDownCard, size: cardSize),
        );
      case PileKind.waste:
        if (!placement.isTop) {
          return CardFace(card: placement.card, size: cardSize);
        }
        return CardView(
          card: placement.card,
          size: cardSize,
          dragData: CardDragData(fromPile: idx, cardIndex: cardIndex),
          onTap: () => _tap(context, idx, cardIndex),
          onDoubleTap: () => _doubleTap(context, idx, cardIndex),
        );
      case PileKind.foundation:
      case PileKind.freecell:
        return CardView(
          card: placement.card,
          size: cardSize,
          dragData: CardDragData(fromPile: idx, cardIndex: cardIndex),
          onTap: () => _tap(context, idx, cardIndex),
          onDoubleTap: () => _doubleTap(context, idx, cardIndex),
        );
      case PileKind.tableau:
        if (!placement.card.faceUp) {
          return CardFace(card: placement.card, size: cardSize);
        }
        return CardView(
          card: placement.card,
          size: cardSize,
          dragData: CardDragData(fromPile: idx, cardIndex: cardIndex),
          dragStack: pile.cards.sublist(cardIndex),
          onTap: placement.isTop ? () => _tap(context, idx, cardIndex) : null,
          onDoubleTap: placement.isTop
              ? () => _doubleTap(context, idx, cardIndex)
              : null,
        );
    }
  }

  /// The active variant's draw count (1 or 3), or 1 for variants (e.g.
  /// FreeCell) that have no waste pile at all.
  int _wasteVisibleCount(BuildContext context) {
    final GameRules rules = context.read<GameBloc>().rules;
    return rules is KlondikeRules ? rules.drawCount : 1;
  }

  void _tap(BuildContext context, int pileIndex, int cardIndex) {
    context.read<GameBloc>().add(
      TapMoveRequested(fromPile: pileIndex, cardIndex: cardIndex),
    );
  }

  void _doubleTap(BuildContext context, int pileIndex, int cardIndex) {
    context.read<GameBloc>().add(
      DoubleTapRequested(fromPile: pileIndex, cardIndex: cardIndex),
    );
  }

  /// Routes a dropped card to the [GameBloc]. [globalDrop] is the drop's global
  /// offset (from `DragTarget.onAcceptWithDetails`); it is unused until Task 10
  /// consumes it for the landing animation.
  void _drop(
    BuildContext context,
    CardDragData data,
    Offset globalDrop,
    int toPile,
  ) {
    context.read<GameBloc>().add(
      MoveRequested(
        fromPile: data.fromPile,
        toPile: toPile,
        cardIndex: data.cardIndex,
      ),
    );
  }
}
