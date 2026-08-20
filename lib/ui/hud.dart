import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../presentation/bloc/game_bloc.dart';
import '../presentation/bloc/game_bloc_state.dart';
import '../presentation/bloc/game_event.dart';

/// The heads-up display: elapsed timer, move counter and the undo / redo /
/// restart / new-deal controls. Purely presentational — every button dispatches
/// a [GameEvent]. Its rebuilds are scoped to the values it shows, so it repaints
/// on a timer tick or a move but not on unrelated board churn.
class Hud extends StatelessWidget {
  const Hud({super.key});

  static String formatDuration(int seconds) {
    final int minutes = seconds ~/ 60;
    final int secs = seconds % 60;
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = secs.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<GameBloc, GameBlocState>(
      buildWhen: (GameBlocState previous, GameBlocState current) =>
          previous.runtimeType != current.runtimeType ||
          previous.state.elapsedSeconds != current.state.elapsedSeconds ||
          previous.state.moveCount != current.state.moveCount ||
          previous.state.canUndo != current.state.canUndo ||
          previous.state.canRedo != current.state.canRedo,
      builder: (BuildContext context, GameBlocState state) {
        final GameBloc bloc = context.read<GameBloc>();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: <Widget>[
              _Stat(
                icon: Icons.timer_outlined,
                label: formatDuration(state.state.elapsedSeconds),
              ),
              const SizedBox(width: 16),
              _Stat(
                icon: Icons.swap_vert,
                label: '${state.state.moveCount} moves',
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Undo',
                icon: const Icon(Icons.undo),
                onPressed: state.state.canUndo
                    ? () => bloc.add(const UndoRequested())
                    : null,
              ),
              IconButton(
                tooltip: 'Redo',
                icon: const Icon(Icons.redo),
                onPressed: state.state.canRedo
                    ? () => bloc.add(const RedoRequested())
                    : null,
              ),
              IconButton(
                tooltip: 'Restart deal',
                icon: const Icon(Icons.replay),
                onPressed: () => bloc.add(const RestartDealRequested()),
              ),
              IconButton(
                tooltip: 'New deal',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => bloc.add(const NewDealRequested()),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 20),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
