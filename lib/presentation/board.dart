import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/game_state.dart';
import '../core/pile.dart';
import 'bloc/game_bloc.dart';
import 'bloc/game_bloc_state.dart';
import 'bloc/game_event.dart';
import 'board_metrics.dart';
import 'card_view.dart';
import 'pile_view.dart';

/// The responsive board. Reads the current [GameState] from the [GameBloc] and
/// lays the piles out for the available space (phone → tablet) via
/// [LayoutBuilder]. It owns no state and no rules: every gesture is forwarded
/// straight to the bloc as a [GameEvent]. Rebuilds are scoped to *board*
/// changes (piles), so the once-a-second timer tick never repaints it.
class Board extends StatelessWidget {
  const Board({super.key});

  static const double _pad = 6;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GameBloc, GameBlocState>(
      buildWhen: (GameBlocState previous, GameBlocState current) =>
          !listEquals(previous.state.piles, current.state.piles),
      builder: (BuildContext context, GameBlocState blocState) {
        final GameState game = blocState.state;
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

        final MediaQueryData media = MediaQuery.of(context);
        final bool isLandscape = media.orientation == Orientation.landscape;
        final double shortestSide = media.size.shortestSide;
        int maxPileLength = 1;
        for (final int index in tableau) {
          maxPileLength = math.max(maxPileLength, game.pileAt(index).length);
        }

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final BoardMetrics metrics = BoardMetrics.resolve(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              columns: tableau.length,
              maxPileLength: maxPileLength,
              shortestSide: shortestSide,
              isLandscape: isLandscape,
              sideStackCount: math.max(upper.length, foundations.length),
            );

            switch (metrics.layout) {
              case BoardLayout.portrait:
              case BoardLayout.phoneLandscape:
                return _stackedLayout(
                  context,
                  game,
                  upper,
                  foundations,
                  tableau,
                  metrics.cardSize,
                  constraints,
                  centred: metrics.layout == BoardLayout.phoneLandscape,
                );
              case BoardLayout.tabletLandscape:
                return _sideColumnLayout(
                  context,
                  game,
                  upper,
                  foundations,
                  tableau,
                  metrics.cardSize,
                  constraints,
                  metrics.sideColumnWidth,
                );
            }
          },
        );
      },
    );
  }

  /// Portrait and phone-landscape share the stacked arrangement: the top row of
  /// stock/waste/foundations above the tableau. The card size is already
  /// fit-to-height, so the fan cannot overflow; the vertical chrome here mirrors
  /// the budget [BoardMetrics] reserves. In phone landscape the content is
  /// centred so the freed width becomes symmetric margins rather than stretched
  /// gaps between columns.
  Widget _stackedLayout(
    BuildContext context,
    GameState game,
    List<int> upper,
    List<int> foundations,
    List<int> tableau,
    Size cardSize,
    BoxConstraints constraints, {
    required bool centred,
  }) {
    final double usableHeight = constraints.maxHeight - _pad * 2;
    final double bottomHeight = math.max(
      cardSize.height,
      usableHeight - cardSize.height - _pad,
    );
    final double fanGap = _fanGap(game, tableau, cardSize.height, bottomHeight);

    final Widget content = Padding(
      padding: const EdgeInsets.all(_pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: cardSize.height,
            child: _topRow(context, game, upper, foundations, cardSize),
          ),
          const SizedBox(height: _pad),
          Expanded(
            child: _tableauRow(context, game, tableau, cardSize, fanGap),
          ),
        ],
      ),
    );

    if (!centred) {
      return content;
    }
    final double contentWidth =
        cardSize.width * tableau.length + _pad * (tableau.length + 1);
    return Center(
      child: SizedBox(width: contentWidth, child: content),
    );
  }

  /// Tablet landscape: the tableau takes the full height on the left while
  /// stock/waste/foundations move to a right-hand column, so wide screens buy
  /// longer, more readable fans instead of oversized cards.
  Widget _sideColumnLayout(
    BuildContext context,
    GameState game,
    List<int> upper,
    List<int> foundations,
    List<int> tableau,
    Size cardSize,
    BoxConstraints constraints,
    double sideColumnWidth,
  ) {
    final double bottomHeight = math.max(
      cardSize.height,
      constraints.maxHeight - _pad * 2,
    );
    final double fanGap = _fanGap(game, tableau, cardSize.height, bottomHeight);

    return Padding(
      padding: const EdgeInsets.all(_pad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: _tableauRow(context, game, tableau, cardSize, fanGap),
          ),
          const SizedBox(width: _pad),
          SizedBox(
            width: sideColumnWidth,
            child: _sideColumn(context, game, upper, foundations, cardSize),
          ),
        ],
      ),
    );
  }

  /// The right-hand column for tablet landscape: two clean vertical stacks side
  /// by side — the upper piles (free cells / stock+waste) on the left, the
  /// foundations on the far right — so a player can tell park-here from aces-here
  /// at a glance instead of reading a mixed grid.
  Widget _sideColumn(
    BuildContext context,
    GameState game,
    List<int> upper,
    List<int> foundations,
    Size cardSize,
  ) {
    return Align(
      alignment: Alignment.topCenter,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _sideStack(context, game, upper, cardSize),
          const SizedBox(width: _pad),
          _sideStack(context, game, foundations, cardSize),
        ],
      ),
    );
  }

  /// One vertical stack of slots within the side column, [_pad] apart.
  Widget _sideStack(
    BuildContext context,
    GameState game,
    List<int> indices,
    Size cardSize,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < indices.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(height: _pad),
          _slot(context, game, indices[i], cardSize),
        ],
      ],
    );
  }

  double _fanGap(
    GameState game,
    List<int> tableau,
    double cardHeight,
    double bottomHeight,
  ) {
    final double defaultGap = cardHeight * 0.30;
    int maxLen = 1;
    for (final int index in tableau) {
      maxLen = math.max(maxLen, game.pileAt(index).length);
    }
    if (maxLen <= 1) {
      return defaultGap;
    }
    final double fitGap = (bottomHeight - cardHeight) / (maxLen - 1);
    return math.max(cardHeight * 0.06, math.min(defaultGap, fitGap));
  }

  Widget _topRow(
    BuildContext context,
    GameState game,
    List<int> upper,
    List<int> foundations,
    Size cardSize,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final int index in upper) ...<Widget>[
          _slot(context, game, index, cardSize),
          const SizedBox(width: _pad),
        ],
        const Spacer(),
        for (final int index in foundations) ...<Widget>[
          const SizedBox(width: _pad),
          _slot(context, game, index, cardSize),
        ],
      ],
    );
  }

  Widget _tableauRow(
    BuildContext context,
    GameState game,
    List<int> tableau,
    Size cardSize,
    double fanGap,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final int index in tableau)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pad / 2),
              child: Align(
                alignment: Alignment.topCenter,
                child: PileView(
                  pile: game.pileAt(index),
                  pileIndex: index,
                  cardSize: cardSize,
                  faceUpGap: fanGap,
                  faceDownGap: fanGap * 0.5,
                  onCardTap: (int cardIndex) => _tap(context, index, cardIndex),
                  onCardDoubleTap: (int cardIndex) =>
                      _doubleTap(context, index, cardIndex),
                  onDrop: (CardDragData data) => _drop(context, data, index),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _slot(BuildContext context, GameState game, int index, Size cardSize) {
    final Pile pile = game.pileAt(index);
    return SizedBox(
      width: cardSize.width,
      child: PileView(
        pile: pile,
        pileIndex: index,
        cardSize: cardSize,
        onCardTap: (int cardIndex) => _tap(context, index, cardIndex),
        onCardDoubleTap: (int cardIndex) =>
            _doubleTap(context, index, cardIndex),
        onPileTap: pile.kind == PileKind.stock
            ? () => context.read<GameBloc>().add(
                TapMoveRequested(fromPile: index),
              )
            : null,
        onDrop: (CardDragData data) => _drop(context, data, index),
      ),
    );
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

  void _drop(BuildContext context, CardDragData data, int toPile) {
    context.read<GameBloc>().add(
      MoveRequested(
        fromPile: data.fromPile,
        toPile: toPile,
        cardIndex: data.cardIndex,
      ),
    );
  }
}
