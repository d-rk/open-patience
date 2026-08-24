import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../presentation/bloc/game_bloc.dart';
import '../presentation/bloc/game_bloc_state.dart';
import '../presentation/bloc/game_event.dart';
import '../presentation/board.dart';
import 'game_menu.dart';
import 'records_screen.dart';
import 'stat_bar.dart';
import 'theme/game_fonts.dart';
import 'theme/game_motion.dart';
import 'theme/game_palette.dart';
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
  bool _menuOpen = false;

  /// The won state, once the bloc reports it — non-null for as long as the
  /// win overlay (cascade + "You Win!" banner) is showing. Null again the
  /// instant navigation to [RecordsScreen] fires.
  GameWon? _wonState;

  /// Whether a tap is currently honored to dismiss the win overlay. The
  /// cascade otherwise runs forever as a reward the player can linger on, so
  /// this flips true only after
  /// [GameMotion.winCascadeMinimumBeforeDismiss] has elapsed since [_wonState]
  /// was set.
  bool _cascadeDismissible = false;

  /// Fires [_cascadeDismissible] once the win overlay's minimum look has
  /// elapsed. Cancelled in [dispose] so a win screen left before the timer
  /// fires (e.g. the app backgrounded and the route torn down) never leaves a
  /// dangling callback.
  Timer? _cascadeDismissTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Hide the system bars during play. On Android this stops the edge-swipe
    // back gesture from stealing a card drag (and bouncing to the menu): the
    // swipe now peeks the bars back instead of navigating. `immersiveSticky`
    // re-hides them automatically after the peek and after an app resume.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final Duration? interval = widget.autoTick;
    if (interval != null) {
      _timer = Timer.periodic(interval, (_) {
        if (!mounted) {
          return;
        }
        final GameBloc bloc = context.read<GameBloc>();
        if (bloc.state is GameInProgress && !_menuOpen) {
          bloc.add(const Tick());
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cascadeDismissTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Restore the normal edge-to-edge chrome so the menu and records screens
    // get their system bars back.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
    // Landscape is short on height, so the stats ride in the otherwise-empty
    // centre of the top bar instead of claiming a bottom row of their own.
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      body: FeltBackground(
        child: SafeArea(
          child: Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  TopBar(
                    onMenu: () async {
                      setState(() => _menuOpen = true);
                      await showGameMenu(context, context.read<GameBloc>());
                      if (mounted) {
                        setState(() => _menuOpen = false);
                      }
                    },
                    center: isLandscape ? const StatBar(compact: true) : null,
                  ),
                  Expanded(
                    child: BlocListener<GameBloc, GameBlocState>(
                      listenWhen:
                          (GameBlocState previous, GameBlocState current) =>
                              current is GameWon && previous is! GameWon,
                      listener: _onGameWon,
                      child: const Board(),
                    ),
                  ),
                  if (!isLandscape) const StatBar(),
                ],
              ),
              if (_wonState != null) _winOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  /// Reacts to the bloc reporting a win. Under reduce-motion — where the
  /// board plays no cascade at all — navigation stays instant, matching the
  /// pre-cascade behaviour. Otherwise the cascade is a reward the player can
  /// linger on for as long as they like: it shows the win overlay and starts
  /// the minimum-look timer that later makes a tap dismissible (see
  /// [_cascadeDismissible]).
  void _onGameWon(BuildContext context, GameBlocState state) {
    final GameWon won = state as GameWon;
    if (MediaQuery.of(context).disableAnimations) {
      _navigateToRecords(context, context.read<GameBloc>());
      return;
    }
    setState(() {
      _wonState = won;
      _cascadeDismissible = false;
    });
    _cascadeDismissTimer?.cancel();
    _cascadeDismissTimer = Timer(GameMotion.winCascadeMinimumBeforeDismiss, () {
      setState(() => _cascadeDismissible = true);
    });
  }

  /// A full-screen, tap-anywhere layer shown for as long as [_wonState] is
  /// set: the "You Win!" banner over the still-bouncing cascade, and (once
  /// [_cascadeDismissible]) the gesture that ends it. `HitTestBehavior.opaque`
  /// on a [Positioned.fill] means the whole area is tappable regardless of
  /// where the banner itself paints.
  Widget _winOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _cascadeDismissible
            ? () => _navigateToRecords(context, context.read<GameBloc>())
            : null,
        child: const Center(child: _WinBanner()),
      ),
    );
  }

  /// Pushes the records screen. A completed game has nothing left to resume,
  /// so leaving its records screen should land back on the main menu rather
  /// than reopen the finished board underneath — hence pushAndRemoveUntil
  /// down to the app root instead of a plain push.
  void _navigateToRecords(BuildContext context, GameBloc bloc) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RecordsScreen(
          repository: bloc.repository,
          variant: bloc.variant,
          title: variantTitle(bloc.variant),
        ),
      ),
      (Route<void> route) => route.isFirst,
    );
  }
}

/// The "You Win!" banner shown over the win cascade: fades and scales in,
/// then stays — the player controls how long they linger, so it never fades
/// back out on its own.
class _WinBanner extends StatelessWidget {
  const _WinBanner();

  static const List<Shadow> _shadows = <Shadow>[
    Shadow(color: Color(0x66000000), offset: Offset(0, 2), blurRadius: 8),
  ];

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (BuildContext context, double t, Widget? child) {
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.7 + 0.3 * t, child: child),
        );
      },
      child: const Text(
        'You Win!',
        style: TextStyle(
          fontFamily: GameFonts.display,
          color: GamePalette.gold,
          fontSize: 48,
          letterSpacing: 1,
          shadows: _shadows,
        ),
      ),
    );
  }
}
