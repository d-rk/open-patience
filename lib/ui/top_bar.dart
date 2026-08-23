import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../presentation/bloc/game_bloc.dart';
import '../presentation/bloc/game_bloc_state.dart';
import '../presentation/bloc/game_event.dart';
import 'theme/game_palette.dart';

/// The slim play-screen top bar: a menu button on the left, undo/redo on the
/// right. Undo/redo enablement rebuilds only when it changes. An optional
/// [center] widget (the play stats in landscape) is overlaid dead-centre,
/// independent of the side buttons' widths.
class TopBar extends StatelessWidget {
  const TopBar({required this.onMenu, this.center, super.key});

  final VoidCallback onMenu;

  /// Centred content between the menu and undo/redo, e.g. the compact stats in
  /// landscape. Null leaves the middle empty.
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    final GameBloc bloc = context.read<GameBloc>();
    final Widget bar = Row(
      children: <Widget>[
        _MenuButton(onMenu: onMenu),
        const Spacer(),
        BlocBuilder<GameBloc, GameBlocState>(
          buildWhen: (GameBlocState p, GameBlocState c) =>
              p.state.canUndo != c.state.canUndo ||
              p.state.canRedo != c.state.canRedo ||
              _canSolve(p) != _canSolve(c) ||
              p is GameWon != c is GameWon,
          builder: (BuildContext context, GameBlocState state) {
            // A won game keeps its undo/redo history, but neither action
            // should be available once play is over.
            final bool won = state is GameWon;
            return Row(
              children: <Widget>[
                if (_canSolve(state))
                  IconButton(
                    tooltip: 'Solve',
                    color: GamePalette.gold,
                    icon: const Icon(Icons.auto_fix_high),
                    onPressed: () => bloc.add(const AutoSolveRequested()),
                  ),
                IconButton(
                  tooltip: 'Undo',
                  color: GamePalette.gold,
                  icon: const Icon(Icons.undo),
                  onPressed: !won && state.state.canUndo
                      ? () => bloc.add(const UndoRequested())
                      : null,
                ),
                IconButton(
                  tooltip: 'Redo',
                  color: GamePalette.gold,
                  icon: const Icon(Icons.redo),
                  onPressed: !won && state.state.canRedo
                      ? () => bloc.add(const RedoRequested())
                      : null,
                ),
              ],
            );
          },
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: center == null
          ? bar
          : Stack(
              alignment: Alignment.center,
              children: <Widget>[bar, center!],
            ),
    );
  }
}

bool _canSolve(GameBlocState state) =>
    state is GameInProgress && state.canAutoSolve;

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onMenu});

  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GamePalette.gold,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onMenu,
        child: const Tooltip(
          message: 'Menu',
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.menu, color: GamePalette.feltGreenDark),
          ),
        ),
      ),
    );
  }
}
