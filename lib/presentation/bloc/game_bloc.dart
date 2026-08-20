import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/card.dart';
import '../../core/game_registry.dart';
import '../../core/game_rules.dart';
import '../../core/game_state.dart';
import '../../core/games/klondike.dart';
import '../../core/move.dart';
import '../../core/pile.dart';
import '../../persistence/records_repository.dart';
import 'game_bloc_state.dart';
import 'game_event.dart';

/// The state-management seam between the widget tree and the pure `core/`
/// engine. It owns the active [GameRules] (via the registry), the working
/// [GameState] and the deal [seed], and it delegates every decision to
/// `GameState`/`GameRules` — it holds no rules of its own. Widgets dispatch
/// [GameEvent]s; the bloc translates them into engine calls and re-exposes the
/// board as [GameBlocState].
class GameBloc extends Bloc<GameEvent, GameBlocState> {
  GameBloc({
    required this.variant,
    required this.repository,
    required int seed,
    required GameState state,
    Random? random,
  }) : rules = GameRegistry.rulesFor(variant),
       _seed = seed,
       _state = state,
       _random = random ?? Random(),
       super(_snapshotOf(state, GameRegistry.rulesFor(variant))) {
    on<MoveRequested>(_onMoveRequested);
    on<TapMoveRequested>(_onTapMoveRequested);
    on<DoubleTapRequested>(_onDoubleTapRequested);
    on<UndoRequested>(_onUndoRequested);
    on<RedoRequested>(_onRedoRequested);
    on<NewDealRequested>(_onNewDealRequested);
    on<RestartDealRequested>(_onRestartDealRequested);
    on<SaveRequested>(_onSaveRequested);
    on<Tick>(_onTick);
  }

  /// Deals a fresh game and wraps it in a bloc. Convenience for the menu.
  factory GameBloc.newGame({
    required String variant,
    required RecordsRepository repository,
    required int seed,
    Random? random,
  }) {
    final GameState state = GameState.newGame(
      GameRegistry.rulesFor(variant),
      seed: seed,
    );
    return GameBloc(
      variant: variant,
      repository: repository,
      seed: seed,
      state: state,
      random: random,
    );
  }

  final String variant;
  final RecordsRepository repository;
  final GameRules rules;
  final Random _random;

  int _seed;
  GameState _state;

  /// The seed of the current deal — needed to restart the same deal.
  int get seed => _seed;

  static GameBlocState _snapshotOf(GameState state, GameRules rules) {
    if (state.isWon(rules)) {
      return GameWon(
        state.copy(),
        elapsed: state.elapsedSeconds,
        moves: state.moveCount,
      );
    }
    return GameInProgress(state.copy());
  }

  Future<void> _onMoveRequested(
    MoveRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    final Pile source = _state.pileAt(event.fromPile);
    if (event.cardIndex < 0 || event.cardIndex >= source.length) {
      return;
    }
    final List<Card> cards = source.cards.sublist(event.cardIndex);
    final Move move = Move(
      fromPile: event.fromPile,
      toPile: event.toPile,
      cards: cards,
    );
    if (_state.tryMove(move, rules)) {
      await _emitAfterMove(emit);
    }
  }

  Future<void> _onTapMoveRequested(
    TapMoveRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    final Pile source = _state.pileAt(event.fromPile);

    // A tap on the stock draws (or, once exhausted, recycles). What a stock tap
    // *means* lives entirely in the rules' builders — the bloc only routes.
    if (source.kind == PileKind.stock) {
      final GameRules currentRules = rules;
      if (currentRules is KlondikeRules) {
        final Move? move =
            currentRules.buildDraw(_state) ?? currentRules.buildRecycle(_state);
        if (move != null) {
          _state.applyMove(move);
          await _emitAfterMove(emit);
        }
      }
      return;
    }

    if (source.isEmpty) {
      return;
    }
    final int index = event.cardIndex ?? source.length - 1;
    if (index < 0 || index >= source.length) {
      return;
    }
    final List<int> targets = rules.autoTargets(
      _state,
      event.fromPile,
      cardIndex: index,
    );
    if (targets.isEmpty) {
      return;
    }
    final int toPile = _preferredTarget(targets);
    final Move move = Move(
      fromPile: event.fromPile,
      toPile: toPile,
      cards: source.cards.sublist(index),
    );
    if (_state.tryMove(move, rules)) {
      await _emitAfterMove(emit);
    }
  }

  Future<void> _onDoubleTapRequested(
    DoubleTapRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    final Pile source = _state.pileAt(event.fromPile);
    if (source.isEmpty) {
      return;
    }
    final int index = event.cardIndex ?? source.length - 1;
    if (index < 0 || index >= source.length) {
      return;
    }
    final List<int> foundations = rules
        .autoTargets(_state, event.fromPile, cardIndex: index)
        .where((int to) => _state.pileAt(to).kind == PileKind.foundation)
        .toList();
    if (foundations.isEmpty) {
      return;
    }
    final Move move = Move(
      fromPile: event.fromPile,
      toPile: foundations.first,
      cards: source.cards.sublist(index),
    );
    if (_state.tryMove(move, rules)) {
      await _emitAfterMove(emit);
    }
  }

  void _onUndoRequested(UndoRequested event, Emitter<GameBlocState> emit) {
    if (!_state.canUndo) {
      return;
    }
    _state.undo();
    // Undo can move the board out of a won state, so re-derive the snapshot
    // rather than assuming in-progress.
    emit(_snapshotOf(_state, rules));
  }

  void _onRedoRequested(RedoRequested event, Emitter<GameBlocState> emit) {
    if (!_state.canRedo) {
      return;
    }
    _state.redo();
    emit(_snapshotOf(_state, rules));
  }

  Future<void> _onNewDealRequested(
    NewDealRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    _seed = event.seed ?? _random.nextInt(1 << 32);
    _state = GameState.newGame(rules, seed: _seed);
    await repository.clearSave(variant);
    emit(GameInProgress(_state.copy()));
  }

  void _onRestartDealRequested(
    RestartDealRequested event,
    Emitter<GameBlocState> emit,
  ) {
    _state = GameState.newGame(rules, seed: _seed);
    emit(GameInProgress(_state.copy()));
  }

  Future<void> _onSaveRequested(
    SaveRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    await repository.saveGame(variant: variant, seed: _seed, state: _state);
  }

  void _onTick(Tick event, Emitter<GameBlocState> emit) {
    if (state is GameWon) {
      return;
    }
    _state.tick();
    emit(GameInProgress(_state.copy()));
  }

  /// After a successful move, emit — recording the win once on the transition
  /// into the won state and clearing the resumable save.
  Future<void> _emitAfterMove(Emitter<GameBlocState> emit) async {
    if (_state.isWon(rules)) {
      final int elapsed = _state.elapsedSeconds;
      final int moves = _state.moveCount;
      await repository.recordResult(
        variant: variant,
        won: true,
        timeSeconds: elapsed,
        moves: moves,
      );
      await repository.clearSave(variant);
      emit(GameWon(_state.copy(), elapsed: elapsed, moves: moves));
    } else {
      emit(GameInProgress(_state.copy()));
    }
  }

  /// Prefer a foundation destination for tap-to-move (advancing the game),
  /// otherwise the first legal target.
  int _preferredTarget(List<int> targets) {
    for (final int to in targets) {
      if (_state.pileAt(to).kind == PileKind.foundation) {
        return to;
      }
    }
    return targets.first;
  }
}
