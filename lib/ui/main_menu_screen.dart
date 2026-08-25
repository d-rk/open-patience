import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/game_catalog.dart';
import '../persistence/records_repository.dart';
import '../presentation/bloc/game_bloc.dart';
import 'debug_deals.dart';
import 'game_options_screen.dart';
import 'game_screen.dart';
import 'theme/game_palette.dart';
import 'theme/widgets.dart';
import 'variant_labels.dart';
import 'widgets/menu_banner.dart';

/// The entry screen: a Continue section (every in-progress deal, one-tap
/// resume) above the list of games. Selecting a game opens its options page.
/// The menu holds no game logic — it only navigates, builds blocs, and
/// reloads its saves after returning from a pushed route so the Continue
/// section always reflects the repository's current state.
class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({required this.repository, this.autoTick, super.key});

  final RecordsRepository repository;

  /// Forwarded to each [GameScreen]; null in tests to avoid pending timers.
  final Duration? autoTick;

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  // Null while the first load is in flight; the resolved list otherwise. Held in
  // state (rather than fed as a Future) so a swipe-to-delete can remove a row
  // synchronously, as Dismissible requires.
  List<SavedGame>? _saves;

  // Tapping the banner logo 10 times in a row reveals the debug "Test win"
  // trigger on any build, not just local debug runs. Session-only: it resets
  // on the next app launch.
  static const int _logoTapsToUnlock = 10;
  static const Duration _logoTapWindow = Duration(seconds: 2);
  int _logoTapCount = 0;
  DateTime? _lastLogoTapAt;
  bool _debugModeUnlocked = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final List<SavedGame> saves = await widget.repository.loadAllSaves();
    if (mounted) {
      setState(() => _saves = saves);
    }
  }

  void _deleteSave(SavedGame saved) {
    // Remove from the model synchronously (Dismissible has already animated the
    // row out), then clear the persisted slot.
    setState(() => _saves?.remove(saved));
    widget.repository.clearSave(saved.variant);
  }

  Future<void> _openGame(BuildContext context, String gameId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GameOptionsScreen(
          gameId: gameId,
          repository: widget.repository,
          autoTick: widget.autoTick,
          debugDeals:
              shouldShowDebugDeals(debugMode: kDebugMode, flavor: appFlavor) ||
              _debugModeUnlocked,
        ),
      ),
    );
    if (mounted) {
      _reload();
    }
  }

  void _onLogoTapped() {
    final DateTime now = DateTime.now();
    final DateTime? lastTap = _lastLogoTapAt;
    if (lastTap == null || now.difference(lastTap) > _logoTapWindow) {
      _logoTapCount = 0;
    }
    _lastLogoTapAt = now;
    _logoTapCount++;
    if (_logoTapCount < _logoTapsToUnlock || _debugModeUnlocked) {
      return;
    }
    setState(() => _debugModeUnlocked = true);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Debug mode enabled')));
  }

  Future<void> _resume(BuildContext context, SavedGame saved) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => BlocProvider<GameBloc>(
          create: (BuildContext context) => GameBloc(
            variant: saved.variant,
            repository: widget.repository,
            seed: saved.seed,
            state: saved.state,
          ),
          child: GameScreen(autoTick: widget.autoTick),
        ),
      ),
    );
    if (mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Landscape phones are short on height; the full-height hero banner and
    // wordmark would crowd the games list off the bottom, so the header
    // shrinks to a compact variant there.
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      body: FeltBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              GestureDetector(
                onTap: _onLogoTapped,
                child: MenuBanner(height: isLandscape ? 84 : 168),
              ),
              GameWordmark(compact: isLandscape),
              Expanded(
                child: MenuWidthLimit(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      _ContinueSection(
                        saves: _saves ?? const <SavedGame>[],
                        onResume: (SavedGame s) => _resume(context, s),
                        onDelete: _deleteSave,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Games',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final Game game in GameCatalog.games)
                        Card(
                          child: ListTile(
                            title: Text(gameTitle(game.id)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openGame(context, game.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const GameSignature(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Continue playing" block: one resume row per in-progress deal, hidden
/// entirely when there are no saves. Each row can be swiped away to discard that
/// game. Dumb — it renders the saves it is handed and forwards resume/delete
/// requests upward.
class _ContinueSection extends StatelessWidget {
  const _ContinueSection({
    required this.saves,
    required this.onResume,
    required this.onDelete,
  });

  final List<SavedGame> saves;
  final void Function(SavedGame) onResume;
  final void Function(SavedGame) onDelete;

  @override
  Widget build(BuildContext context) {
    if (saves.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Continue playing',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final SavedGame saved in saves)
          Dismissible(
            key: ValueKey<String>('continue-${saved.variant}'),
            direction: DismissDirection.endToStart,
            onDismissed: (DismissDirection _) => onDelete(saved),
            // Transparent reveal (just the trash icon over the felt): a coloured
            // panel behind the rounded card let the felt peek at its corners
            // mid-swipe, which read as an artefact.
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: const Icon(Icons.delete, color: GamePalette.cardRed),
            ),
            child: Card(
              child: ListTile(
                title: Text(variantTitle(saved.variant)),
                subtitle: Text(
                  '${formatDuration(saved.state.elapsedSeconds)} · '
                  '${saved.state.moveCount} moves',
                ),
                trailing: TextButton.icon(
                  onPressed: () => onResume(saved),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Resume'),
                ),
                onTap: () => onResume(saved),
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}
