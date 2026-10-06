import 'package:equatable/equatable.dart';

import '../../core/card.dart';

/// Intents dispatched by the widget tree. Every player gesture becomes one of
/// these; the [GameBloc] is the only thing that turns them into `core/` calls.
/// Widgets never decide legality — they describe *what was touched*, and the
/// bloc resolves the rest through `GameRules`/`GameState`.
sealed class GameEvent extends Equatable {
  const GameEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// A drag-and-drop move: drop [cards] — the run the player picked up, which
/// must still be the top of [fromPile] — on [toPile]. Naming the cards rather
/// than a position means a drop can never move cards other than the ones
/// dragged, even if the board changed while they were in the air. The bloc
/// asks the rules whether the move is legal.
class MoveRequested extends GameEvent {
  const MoveRequested({
    required this.fromPile,
    required this.toPile,
    required this.cards,
  });

  final int fromPile;
  final int toPile;
  final List<Card> cards;

  @override
  List<Object?> get props => <Object?>[fromPile, toPile, cards];
}

/// Tap-to-move: send the card (group) at [cardIndex] — the top card when
/// `null` — of [fromPile] to its resolved destination. A tap on the stock pile
/// draws/recycles. All destinations come from `GameRules.autoTargets`.
class TapMoveRequested extends GameEvent {
  const TapMoveRequested({required this.fromPile, this.cardIndex});

  final int fromPile;
  final int? cardIndex;

  @override
  List<Object?> get props => <Object?>[fromPile, cardIndex];
}

/// Double-tap-to-foundation: send the card at [cardIndex] (top when `null`) of
/// [fromPile] to a foundation if the rules allow it.
class DoubleTapRequested extends GameEvent {
  const DoubleTapRequested({required this.fromPile, this.cardIndex});

  final int fromPile;
  final int? cardIndex;

  @override
  List<Object?> get props => <Object?>[fromPile, cardIndex];
}

/// Undo the most recent move.
class UndoRequested extends GameEvent {
  const UndoRequested();
}

/// Redo the most recently undone move.
class RedoRequested extends GameEvent {
  const RedoRequested();
}

/// Deal a brand-new game. A `null` [seed] picks a fresh random deal; an
/// explicit seed makes the deal reproducible (used by tests).
class NewDealRequested extends GameEvent {
  const NewDealRequested({this.seed});

  final int? seed;

  @override
  List<Object?> get props => <Object?>[seed];
}

/// Re-deal the *same* seed — restart the current deal from scratch.
class RestartDealRequested extends GameEvent {
  const RestartDealRequested();
}

/// Persist the in-progress game via the records repository (e.g. on app pause).
class SaveRequested extends GameEvent {
  const SaveRequested();
}

/// One second of wall-clock time elapsed — advances the play timer.
class Tick extends GameEvent {
  const Tick();
}

/// Play the board out to a win via the auto-solver. A no-op unless the board
/// is trivially solvable.
class AutoSolveRequested extends GameEvent {
  const AutoSolveRequested();
}
