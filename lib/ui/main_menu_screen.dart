import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/game_catalog.dart';
import '../persistence/records_repository.dart';
import '../presentation/bloc/game_bloc.dart';
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
  late Future<List<SavedGame>> _savesFuture;

  @override
  void initState() {
    super.initState();
    _savesFuture = widget.repository.loadAllSaves();
  }

  void _reload() {
    setState(() {
      _savesFuture = widget.repository.loadAllSaves();
    });
  }

  Future<void> _openGame(BuildContext context, String gameId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GameOptionsScreen(
          gameId: gameId,
          repository: widget.repository,
          autoTick: widget.autoTick,
        ),
      ),
    );
    if (mounted) {
      _reload();
    }
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
    return Scaffold(
      body: FeltBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const MenuBanner(),
              const GameWordmark(),
              Expanded(
                child: MenuWidthLimit(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      _ContinueSection(
                        savesFuture: _savesFuture,
                        onResume: (SavedGame s) => _resume(context, s),
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
/// entirely when there are no saves. Dumb — it renders the saves it is handed
/// and forwards a resume request upward.
class _ContinueSection extends StatelessWidget {
  const _ContinueSection({required this.savesFuture, required this.onResume});

  final Future<List<SavedGame>> savesFuture;
  final void Function(SavedGame) onResume;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SavedGame>>(
      future: savesFuture,
      builder: (BuildContext context, AsyncSnapshot<List<SavedGame>> snapshot) {
        final List<SavedGame> saves = snapshot.data ?? const <SavedGame>[];
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
              Card(
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
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}
