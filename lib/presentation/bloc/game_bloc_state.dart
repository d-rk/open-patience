import 'package:equatable/equatable.dart';

import '../../core/game_state.dart';

/// UI-facing state emitted by the [GameBloc]. Both variants carry an immutable
/// snapshot of the board; widgets rebuild off it via `BlocBuilder`. Equality is
/// value-based (through the snapshot's own [GameState] equality) so an emit that
/// leaves the board unchanged is de-duplicated by `flutter_bloc`.
sealed class GameBlocState extends Equatable {
  const GameBlocState(this.state);

  /// The board snapshot to render. Always a `copy()` taken by the bloc, so it
  /// is safe to compare against the previous state for `buildWhen`.
  final GameState state;

  @override
  List<Object?> get props => <Object?>[state];
}

/// A game still being played. [canAutoSolve] is `true` when the board is
/// trivially (greedily) solvable, which drives the top-bar solve button.
class GameInProgress extends GameBlocState {
  const GameInProgress(super.state, {this.canAutoSolve = false});

  final bool canAutoSolve;

  @override
  List<Object?> get props => <Object?>[state, canAutoSolve];
}

/// A completed win. Carries the final [elapsed] seconds and [moves] so the HUD
/// and records screen can display the result without re-deriving it.
class GameWon extends GameBlocState {
  const GameWon(super.state, {required this.elapsed, required this.moves});

  final int elapsed;
  final int moves;

  @override
  List<Object?> get props => <Object?>[state, elapsed, moves];
}
