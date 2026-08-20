import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../presentation/bloc/game_bloc.dart';
import '../presentation/bloc/game_bloc_state.dart';
import '../presentation/bloc/game_event.dart';
import 'theme/game_palette.dart';

/// The slim play-screen top bar: a menu button on the left, undo/redo on the
/// right. Undo/redo enablement rebuilds only when it changes.
class TopBar extends StatelessWidget {
  const TopBar({required this.onMenu, super.key});

  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final GameBloc bloc = context.read<GameBloc>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: <Widget>[
          _MenuButton(onMenu: onMenu),
          const Spacer(),
          BlocBuilder<GameBloc, GameBlocState>(
            buildWhen: (GameBlocState p, GameBlocState c) =>
                p.state.canUndo != c.state.canUndo ||
                p.state.canRedo != c.state.canRedo,
            builder: (BuildContext context, GameBlocState state) {
              return Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Undo',
                    color: GamePalette.gold,
                    icon: const Icon(Icons.undo),
                    onPressed: state.state.canUndo
                        ? () => bloc.add(const UndoRequested())
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Redo',
                    color: GamePalette.gold,
                    icon: const Icon(Icons.redo),
                    onPressed: state.state.canRedo
                        ? () => bloc.add(const RedoRequested())
                        : null,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

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
