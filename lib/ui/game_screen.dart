import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../presentation/bloc/game_bloc.dart';
import '../presentation/bloc/game_bloc_state.dart';
import '../presentation/bloc/game_event.dart';
import '../presentation/board.dart';
import 'game_menu.dart';
import 'records_screen.dart';
import 'stat_bar.dart';
import 'theme/widgets.dart';
import 'top_bar.dart';
import 'variant_labels.dart';

/// The play screen: a slim top bar, [Board], and a bottom stat bar. It wires
/// the two cross-cutting concerns a dumb board can't own itself — advancing
/// the play timer once a second and persisting on app pause — plus
/// navigating to the records screen the moment the game is won. The
/// [GameBloc] is provided by the caller.
class GameScreen extends StatefulWidget {
  const GameScreen({this.autoTick, super.key});

  /// When set, a [Tick] is dispatched on this interval while the game is in
  /// progress. Left null in widget tests to avoid pending timers.
  final Duration? autoTick;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final Duration? interval = widget.autoTick;
    if (interval != null) {
      _timer = Timer.periodic(interval, (_) {
        if (!mounted) {
          return;
        }
        final GameBloc bloc = context.read<GameBloc>();
        if (bloc.state is GameInProgress) {
          bloc.add(const Tick());
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      context.read<GameBloc>().add(const SaveRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FeltBackground(
        child: SafeArea(
          child: Column(
            children: <Widget>[
              TopBar(
                onMenu: () => showGameMenu(context, context.read<GameBloc>()),
              ),
              Expanded(
                child: BlocListener<GameBloc, GameBlocState>(
                  listenWhen: (GameBlocState previous, GameBlocState current) =>
                      current is GameWon && previous is! GameWon,
                  listener: (BuildContext context, GameBlocState state) {
                    final GameBloc bloc = context.read<GameBloc>();
                    _showWin(context, bloc, state as GameWon);
                  },
                  child: const Board(),
                ),
              ),
              const StatBar(),
            ],
          ),
        ),
      ),
    );
  }

  void _showWin(BuildContext context, GameBloc bloc, GameWon won) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RecordsScreen(
          repository: bloc.repository,
          variant: bloc.variant,
          title: variantTitle(bloc.variant),
        ),
      ),
    );
  }
}
