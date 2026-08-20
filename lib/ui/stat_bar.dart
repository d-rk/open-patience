import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../presentation/bloc/game_bloc.dart';
import '../presentation/bloc/game_bloc_state.dart';
import 'theme/game_palette.dart';
import 'theme/widgets.dart';

/// Bottom-of-screen play stats: elapsed time and move count as pills. Rebuilds
/// only when the shown values change.
class StatBar extends StatelessWidget {
  const StatBar({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GameBloc, GameBlocState>(
      buildWhen: (GameBlocState previous, GameBlocState current) =>
          previous.state.elapsedSeconds != current.state.elapsedSeconds ||
          previous.state.moveCount != current.state.moveCount,
      builder: (BuildContext context, GameBlocState state) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
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
          ),
        );
      },
    );
  }
}
