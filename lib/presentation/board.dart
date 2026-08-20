import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/game_state.dart';
import '../core/pile.dart';
import 'bloc/game_bloc.dart';
import 'bloc/game_bloc_state.dart';
import 'bloc/game_event.dart';
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

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final int columns = math.max(tableau.length, 1);
            final double cardWidth = math.max(
              24,
              (constraints.maxWidth - _pad) / columns - _pad,
            );
            final double cardHeight = cardWidth * CardView.aspectRatio;
            final Size cardSize = Size(cardWidth, cardHeight);
            final double topRowHeight = cardHeight + _pad;
            final double bottomHeight = math.max(
              cardHeight,
              constraints.maxHeight - topRowHeight - _pad * 2,
            );
            final double fanGap = _fanGap(
              game,
              tableau,
              cardHeight,
              bottomHeight,
            );

            return Padding(
              padding: const EdgeInsets.all(_pad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    height: topRowHeight,
                    child: _topRow(context, game, upper, foundations, cardSize),
                  ),
                  const SizedBox(height: _pad),
                  Expanded(
                    child: _tableauRow(
                      context,
                      game,
                      tableau,
                      cardSize,
                      fanGap,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
