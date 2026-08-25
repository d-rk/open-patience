import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/card.dart';
import '../../core/game_registry.dart';
import '../../core/game_rules.dart';
import '../../core/game_state.dart';
import '../../core/games/klondike.dart';
import '../../core/move.dart';
import '../../core/pile.dart';
import '../../core/seed.dart';
import '../../core/solver.dart';
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
    this.autoSolveStep = const Duration(milliseconds: 120),
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
    on<AutoSolveRequested>(_onAutoSolveRequested);
  }

  /// Deals a fresh game and wraps it in a bloc. Convenience for the menu.
  /// [almostWon] is a debug-only shortcut (see [GameState.newGame]) for
  /// testing the win/records flow without playing a full game.
  factory GameBloc.newGame({
    required String variant,
    required RecordsRepository repository,
    required int seed,
    Random? random,
    bool almostWon = false,
    Duration autoSolveStep = const Duration(milliseconds: 120),
  }) {
    final GameState state = GameState.newGame(
      GameRegistry.rulesFor(variant),
      seed: seed,
      almostWon: almostWon,
    );
    return GameBloc(
      variant: variant,
      repository: repository,
      seed: seed,
      state: state,
      random: random,
      autoSolveStep: autoSolveStep,
    );
  }

  final String variant;
  final RecordsRepository repository;
  final GameRules rules;
  final Random _random;

  /// Delay between moves while the auto-solver cascade plays out.
  final Duration autoSolveStep;

  bool _solving = false;

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
    return GameInProgress(
      state.copy(),
      canAutoSolve: solveGreedy(state, rules) != null,
    );
  }

  Future<void> _onMoveRequested(
    MoveRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    if (_solving || state is GameWon) {
      return;
    }
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
    if (_solving || state is GameWon) {
      return;
    }
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
    if (_solving || state is GameWon) {
      return;
    }
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

  Future<void> _onUndoRequested(
    UndoRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    if (_solving || state is GameWon) {
      return;
    }
    if (!_state.canUndo) {
      return;
    }
    _state.undo();
    // Undo can move the board out of a won state, so re-derive the snapshot
    // rather than assuming in-progress.
    emit(_snapshotOf(_state, rules));
    await _persist();
  }

  Future<void> _onRedoRequested(
    RedoRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    if (_solving || state is GameWon) {
      return;
    }
    if (!_state.canRedo) {
      return;
    }
    _state.redo();
    emit(_snapshotOf(_state, rules));
    await _persist();
  }

  Future<void> _onNewDealRequested(
    NewDealRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    if (_solving) {
      return;
    }
    _seed = event.seed ?? randomSeed(_random);
    _state = GameState.newGame(rules, seed: _seed);
    await repository.clearSave(variant);
    emit(_snapshotOf(_state, rules));
  }

  Future<void> _onRestartDealRequested(
    RestartDealRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    if (_solving) {
      return;
    }
    _state = GameState.newGame(rules, seed: _seed);
    // The prior deal's autosave is now stale — drop it so the reset deal is
    // not resumable to its abandoned progress.
    await repository.clearSave(variant);
    emit(_snapshotOf(_state, rules));
  }

  Future<void> _onSaveRequested(
    SaveRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    // Never persist a completed game as resumable.
    if (_state.isWon(rules)) {
      return;
    }
    await repository.saveGame(variant: variant, seed: _seed, state: _state);
  }

  Future<void> _onAutoSolveRequested(
    AutoSolveRequested event,
    Emitter<GameBlocState> emit,
  ) async {
    if (_solving || state is GameWon) {
      return;
    }
    final List<Move>? solution = solveGreedy(_state, rules);
    if (solution == null) {
      return;
    }
    _solving = true;
    try {
      for (final Move move in solution) {
        // The play route may have been popped mid-cascade, closing the bloc
        // while we were suspended on the delay below; emitting on a done
        // emitter throws, so bail cleanly instead.
        if (emit.isDone) {
          return;
        }
        _state.applyMove(move);
        if (_state.isWon(rules)) {
          final int elapsed = _state.elapsedSeconds;
          final int moves = _state.moveCount;
          await repository.recordWin(
            variant: variant,
            timeSeconds: elapsed,
            moves: moves,
          );
          await repository.clearSave(variant);
          if (emit.isDone) {
            return;
          }
          emit(GameWon(_state.copy(), elapsed: elapsed, moves: moves));
          return;
        }
        emit(_snapshotOf(_state, rules));
        await Future<void>.delayed(autoSolveStep);
      }
    } finally {
      _solving = false;
    }
  }

  void _onTick(Tick event, Emitter<GameBlocState> emit) {
    if (state is GameWon) {
      return;
    }
    _state.tick();
    emit(_snapshotOf(_state, rules));
  }

  /// After a successful move, emit — recording the win once on the transition
  /// into the won state and clearing the resumable save.
  Future<void> _emitAfterMove(Emitter<GameBlocState> emit) async {
    if (_state.isWon(rules)) {
      final int elapsed = _state.elapsedSeconds;
      final int moves = _state.moveCount;
      // Block other handlers for the awaits below: they'd otherwise see a
      // not-yet-won `_state` and could mutate it (e.g. undo the winning move)
      // before the GameWon below is emitted.
      _solving = true;
      try {
        await repository.recordWin(
          variant: variant,
          timeSeconds: elapsed,
          moves: moves,
        );
        await repository.clearSave(variant);
      } finally {
        _solving = false;
      }
      emit(GameWon(_state.copy(), elapsed: elapsed, moves: moves));
    } else {
      emit(_snapshotOf(_state, rules));
      await _persist();
    }
  }

  /// Persists the current in-progress game so leaving the play screen (by any
  /// path) always leaves a resumable save, or clears the slot once the game is
  /// won. Called after every state change that leaves the board resumable.
  Future<void> _persist() async {
    if (_state.isWon(rules)) {
      await repository.clearSave(variant);
    } else {
      await repository.saveGame(variant: variant, seed: _seed, state: _state);
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
