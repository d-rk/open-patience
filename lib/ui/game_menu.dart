import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../persistence/settings_repository.dart';
import '../presentation/bloc/game_bloc.dart';
import '../presentation/bloc/game_bloc_state.dart';
import '../presentation/bloc/game_event.dart';
import 'theme/game_fonts.dart';
import 'theme/game_palette.dart';
import 'theme/widgets.dart';
import 'variant_labels.dart';

/// Opens the in-game menu: variant title + live stats banner over Restart,
/// Shuffle and Exit actions. Each action dismisses the dialog first.
Future<void> showGameMenu(
  BuildContext context,
  GameBloc bloc, {
  SettingsRepository? settings,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      return MenuWidthLimit(
        maxWidth: 380,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: GamePalette.gold, width: 3),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _Banner(bloc: bloc),
              // The banner stays fixed; the actions below scroll if a short
              // landscape phone can't fit them all at once (the full-width
              // Sound tile pushes this past a short viewport's height).
              Flexible(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: GameActionTile(
                                icon: Icons.replay,
                                label: 'Restart Deal',
                                background: GamePalette.feltGreenMid,
                                foreground: GamePalette.cardFace,
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
                                label: 'New Deal',
                                background: GamePalette.feltGreenMid,
                                foreground: GamePalette.cardFace,
                                onPressed: () {
                                  Navigator.of(dialogContext).pop();
                                  bloc.add(const NewDealRequested());
                                },
                              ),
                            ),
                          ],
                        ),
                        if (settings != null) ...<Widget>[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: _SoundTile(settings: settings),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Divider(color: GamePalette.gold.withValues(alpha: 0.4)),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: GameActionTile(
                            icon: Icons.logout,
                            label: 'Exit to menu',
                            background: GamePalette.feltGreenDark,
                            foreground: GamePalette.gold,
                            onPressed: () {
                              Navigator.of(dialogContext).pop(); // close dialog
                              Navigator.of(
                                context,
                              ).pop(); // leave the play screen
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
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
              fontFamily: GameFonts.display,
              color: GamePalette.gold,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 2),
          BlocBuilder<GameBloc, GameBlocState>(
            bloc: bloc,
            builder: (BuildContext context, GameBlocState state) {
              return Text(
                '${formatDuration(state.state.elapsedSeconds)} · '
                '${formatMoves(state.state.moveCount)}',
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

/// Toggles sound effects in place — the dialog stays open so the player sees
/// the new state.
class _SoundTile extends StatefulWidget {
  const _SoundTile({required this.settings});

  final SettingsRepository settings;

  @override
  State<_SoundTile> createState() => _SoundTileState();
}

class _SoundTileState extends State<_SoundTile> {
  @override
  Widget build(BuildContext context) {
    final bool on = widget.settings.soundEnabled;
    return GameActionTile(
      icon: on ? Icons.volume_up : Icons.volume_off,
      label: on ? 'Sound: On' : 'Sound: Off',
      background: GamePalette.feltGreenMid,
      foreground: GamePalette.cardFace,
      onPressed: () async {
        await widget.settings.setSoundEnabled(!on);
        if (mounted) {
          setState(() {});
        }
      },
    );
  }
}
