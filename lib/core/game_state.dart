import 'dart:math';

import 'package:equatable/equatable.dart';

import 'card.dart';
import 'deck.dart';
import 'game_rules.dart';
import 'move.dart';
import 'pile.dart';

/// The game-agnostic board state: every [Pile], the undo/redo history, the
/// move counter and the elapsed timer. It applies and reverts [Move]s, but
/// holds no rules — legality and win checks are delegated to a [GameRules]
/// passed in at call time, which keeps this class free of any variant identity.
///
/// Equality (via [Equatable]) is defined over the *observable board*:
/// [piles], [moveCount] and [elapsedSeconds]. The undo/redo stacks are history
/// metadata and are deliberately excluded, so an undo that returns the board
/// to a prior configuration compares equal to a snapshot taken before the
/// move — exactly what the undo tests assert. The stacks are still serialized,
/// so a resumed game keeps its history.
///
/// Uses [Equatable] as a mixin for props-based value equality — exactly what
/// the undo/round-trip tests rely on. This class is intentionally *mutable*
/// (moves are applied and reverted in place), which is why the `@immutable`
/// contract Equatable carries is explicitly ignored here.
// ignore: must_be_immutable
class GameState with Equatable {
  GameState({
    required List<Pile> piles,
    int moveCount = 0,
    int elapsedSeconds = 0,
    List<Move> undoStack = const <Move>[],
    List<Move> redoStack = const <Move>[],
  }) : _piles = List<Pile>.of(piles),
       _moveCount = moveCount,
       _elapsedSeconds = elapsedSeconds,
       _undoStack = List<Move>.of(undoStack),
       _redoStack = List<Move>.of(redoStack);

  /// Deals a fresh game for [rules] using a deterministic shuffle from [seed].
  /// When [almostWon] is set, ignores [seed] and deals [GameRules.dealAlmostWon]
  /// instead — a debug-only shortcut for testing the win/records flow.
  factory GameState.newGame(
    GameRules rules, {
    required int seed,
    bool almostWon = false,
  }) {
    if (almostWon) {
      return GameState(piles: rules.dealAlmostWon());
    }
    final Deck deck = Deck.standard()..shuffle(Random(seed));
    return GameState(piles: rules.deal(deck));
  }

  factory GameState.fromJson(Map<String, dynamic> json) {
    List<Move> decodeMoves(String key) {
      final List<dynamic> raw = json[key] as List<dynamic>;
      return raw
          .map((dynamic m) => Move.fromJson(m as Map<String, dynamic>))
          .toList();
    }

    final List<dynamic> rawPiles = json['piles'] as List<dynamic>;
    return GameState(
      piles: rawPiles
          .map((dynamic p) => Pile.fromJson(p as Map<String, dynamic>))
          .toList(),
      moveCount: json['moveCount'] as int,
      elapsedSeconds: json['elapsedSeconds'] as int,
      undoStack: decodeMoves('undo'),
      redoStack: decodeMoves('redo'),
    );
  }

  final List<Pile> _piles;
  int _moveCount;
  int _elapsedSeconds;
  final List<Move> _undoStack;
  final List<Move> _redoStack;

  /// An immutable view of the piles in canonical index order.
  List<Pile> get piles => List<Pile>.unmodifiable(_piles);

  int get moveCount => _moveCount;

  int get elapsedSeconds => _elapsedSeconds;

  bool get canUndo => _undoStack.isNotEmpty;

  bool get canRedo => _redoStack.isNotEmpty;

  int get undoCount => _undoStack.length;

  int get redoCount => _redoStack.length;

  Pile pileAt(int index) => _piles[index];

  /// Attempts [requested] against [rules]. On a legal move it mutates the
  /// board, records the resolved (side-effect-carrying) move on the undo
  /// stack, clears the redo stack and increments the move count, returning
  /// `true`. An illegal move is a no-op returning `false` — illegal input is
  /// expected here, never an exception.
  bool tryMove(Move requested, GameRules rules) {
    if (requested.fromPile == requested.toPile || requested.cards.isEmpty) {
      return false;
    }
    final bool legal = rules.isLegalMove(
      this,
      requested.fromPile,
      requested.cards,
      requested.toPile,
    );
    if (!legal) {
      return false;
    }
    applyMove(requested);
    return true;
  }

  /// Applies [move] unconditionally, recording it for undo, clearing the redo
  /// stack and incrementing the move count. This bypasses legality checks, so
  /// the caller vouches for the move — it exists for rules-generated system
  /// moves such as a Klondike stock draw or waste recycle, which target the
  /// stock/waste piles that [tryMove]'s player-move legality intentionally
  /// rejects.
  void applyMove(Move move) {
    final Move resolved = _applyMove(move);
    _undoStack.add(resolved);
    _redoStack.clear();
    _moveCount++;
  }

  /// Reverts the most recent move, restoring the exact prior board and move
  /// count. No-op when there is nothing to undo.
  void undo() {
    if (_undoStack.isEmpty) {
      return;
    }
    final Move move = _undoStack.removeLast();
    _revertMove(move);
    _redoStack.add(move);
    _moveCount--;
  }

  /// Re-applies the most recently undone move. No-op when there is nothing to
  /// redo.
  void redo() {
    if (_redoStack.isEmpty) {
      return;
    }
    final Move move = _redoStack.removeLast();
    _applyMove(move);
    _undoStack.add(move);
    _moveCount++;
  }

  bool isWon(GameRules rules) => rules.isWon(this);

  /// Advances the elapsed timer. The timer is not part of undo/redo — a player
  /// undoing a move does not turn back the clock.
  void tick([int seconds = 1]) {
    if (seconds < 0) {
      throw ArgumentError.value(seconds, 'seconds', 'must be non-negative');
    }
    _elapsedSeconds += seconds;
  }

  set elapsedSeconds(int value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'must be non-negative');
    }
    _elapsedSeconds = value;
  }

  /// A deep, independent copy of this state (including its history stacks).
  GameState copy() {
    return GameState(
      piles: _piles,
      moveCount: _moveCount,
      elapsedSeconds: _elapsedSeconds,
      undoStack: _undoStack,
      redoStack: _redoStack,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'piles': _piles.map((Pile p) => p.toJson()).toList(),
    'moveCount': _moveCount,
    'elapsedSeconds': _elapsedSeconds,
    'undo': _undoStack.map((Move m) => m.toJson()).toList(),
    'redo': _redoStack.map((Move m) => m.toJson()).toList(),
  };

  /// Applies [move] to the board and returns it with [Move.flipUnderCard]
  /// resolved. Reused verbatim by redo: re-applying an already-resolved move
  /// on the same board reproduces the same flip, so the value round-trips.
  Move _applyMove(Move move) {
    final int n = move.cards.length;
    _piles[move.fromPile] = _piles[move.fromPile].removeTop(n);
    _piles[move.toPile] = _piles[move.toPile].addAll(move.cards);

    bool flipped = false;
    final Pile source = _piles[move.fromPile];
    if (source.kind == PileKind.tableau &&
        source.isNotEmpty &&
        !source.topCard!.faceUp) {
      _piles[move.fromPile] = source.flipTopUp();
      flipped = true;
    }
    return move.copyWith(flipUnderCard: flipped);
  }

  void _revertMove(Move move) {
    final int n = move.cards.length;
    if (move.flipUnderCard) {
      _piles[move.fromPile] = _piles[move.fromPile].flipTopDown();
    }
    _piles[move.toPile] = _piles[move.toPile].removeTop(n);
    final List<Card> sourceCards = move.flipMovedCards
        ? move.cards
              .map((Card c) => c.faceUp ? c.faceDownCard : c.faceUpCard)
              .toList()
        : move.cards;
    _piles[move.fromPile] = _piles[move.fromPile].addAll(sourceCards);
  }

  @override
  List<Object?> get props => <Object?>[_piles, _moveCount, _elapsedSeconds];

  @override
  bool get stringify => false;
}
