import 'package:equatable/equatable.dart';

/// Intents dispatched by the widget tree. Every player gesture becomes one of
/// these; the [GameBloc] is the only thing that turns them into `core/` calls.
/// Widgets never decide legality — they describe *what was touched*, and the
/// bloc resolves the rest through `GameRules`/`GameState`.
sealed class GameEvent extends Equatable {
  const GameEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

/// A drag-and-drop move: take the cards from [cardIndex] to the top of
/// [fromPile] and drop them on [toPile]. The bloc slices the actual cards out
/// of the current state and asks the rules whether it is legal.
class MoveRequested extends GameEvent {
  const MoveRequested({
    required this.fromPile,
    required this.toPile,
    required this.cardIndex,
  });

  final int fromPile;
  final int toPile;
  final int cardIndex;

  @override
  List<Object?> get props => <Object?>[fromPile, toPile, cardIndex];
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
