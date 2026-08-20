import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../presentation/bloc/game_bloc.dart';
import '../presentation/bloc/game_bloc_state.dart';
import '../presentation/bloc/game_event.dart';
import 'theme/game_palette.dart';
import 'theme/widgets.dart';
import 'variant_labels.dart';

/// Opens the in-game menu: variant title + live stats banner over Restart,
/// Shuffle and Exit actions. Each action dismisses the dialog first.
Future<void> showGameMenu(BuildContext context, GameBloc bloc) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: GamePalette.gold, width: 3),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _Banner(bloc: bloc),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: GameActionTile(
                          icon: Icons.replay,
                          label: 'Restart',
                          background: GamePalette.actionRestartBg,
                          foreground: GamePalette.actionRestartFg,
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            bloc.add(const RestartDealRequested());
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GameActionTile(
                          icon: Icons.shuffle,
                          label: 'Shuffle',
                          background: GamePalette.actionShuffleBg,
                          foreground: GamePalette.actionShuffleFg,
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            bloc.add(const NewDealRequested());
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: GameActionTile(
                      icon: Icons.logout,
                      label: 'Exit to menu',
                      background: GamePalette.actionExitBg,
                      foreground: GamePalette.actionExitFg,
                      onPressed: () {
                        Navigator.of(dialogContext).pop(); // close dialog
                        Navigator.of(context).pop(); // leave the play screen
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.bloc});

  final GameBloc bloc;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[GamePalette.feltGreenMid, GamePalette.feltGreenLight],
        ),
      ),
      child: Column(
        children: <Widget>[
          Text(
            variantTitle(bloc.variant),
            style: const TextStyle(
              color: GamePalette.gold,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          BlocBuilder<GameBloc, GameBlocState>(
            bloc: bloc,
            builder: (BuildContext context, GameBlocState state) {
              return Text(
                '${formatDuration(state.state.elapsedSeconds)} · '
                '${state.state.moveCount} moves',
                style: TextStyle(
                  color: GamePalette.cardFace.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
