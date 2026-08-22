import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../presentation/bloc/game_bloc.dart';
import '../presentation/bloc/game_bloc_state.dart';
import 'theme/game_palette.dart';
import 'theme/widgets.dart';

/// Play stats: elapsed time and move count as pills. Rebuilds only when the
/// shown values change. Sits in its own bottom bar in portrait; in landscape it
/// tucks into the top bar with [compact] set, which drops the vertical padding
/// so the pills line up with the menu and undo/redo buttons.
class StatBar extends StatelessWidget {
  const StatBar({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GameBloc, GameBlocState>(
      buildWhen: (GameBlocState previous, GameBlocState current) =>
          previous.state.elapsedSeconds != current.state.elapsedSeconds ||
          previous.state.moveCount != current.state.moveCount,
      builder: (BuildContext context, GameBlocState state) {
        final Widget pills = Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            GamePill(
              icon: Icons.timer_outlined,
              label: formatDuration(state.state.elapsedSeconds),
            ),
            const SizedBox(width: 12),
            GamePill(
              icon: Icons.swap_vert,
              label: '${state.state.moveCount} moves',
            ),
          ],
        );
        if (compact) {
          return pills;
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: pills,
        );
      },
    );
  }
}
