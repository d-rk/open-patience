import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/game_catalog.dart';
import '../persistence/records_repository.dart';
import '../presentation/bloc/game_bloc.dart';
import 'game_screen.dart';
import 'records_screen.dart';
import 'theme/widgets.dart';
import 'variant_labels.dart';

/// The per-game page: one row per variant, each with Play (new deal), Resume
/// (when a save exists) and Records. Holds no game logic — it constructs a
/// [GameBloc] and pushes a [GameScreen], exactly like the old menu cards did.
class GameOptionsScreen extends StatelessWidget {
  const GameOptionsScreen({
    required this.gameId,
    required this.repository,
    this.autoTick,
    this.debugDeals = false,
    super.key,
  });

  final String gameId;
  final RecordsRepository repository;
  final Duration? autoTick;

  /// Shows a per-variant "test win" trigger that opens a near-won board — one
  /// move per foundation away from a win — for testing the win/records flow.
  /// Wired to `appFlavor == 'testing'` at the app root, so it never appears
  /// in a production build.
  final bool debugDeals;

  void _open(BuildContext context, GameBloc bloc) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => BlocProvider<GameBloc>(
          create: (BuildContext context) => bloc,
          child: GameScreen(autoTick: autoTick),
        ),
      ),
    );
  }

  void _play(BuildContext context, String variant) {
    final int seed = Random().nextInt(1 << 32);
    _open(
      context,
      GameBloc.newGame(variant: variant, repository: repository, seed: seed),
    );
  }

  void _playAlmostWon(BuildContext context, String variant) {
    final int seed = Random().nextInt(1 << 32);
    _open(
      context,
      GameBloc.newGame(
        variant: variant,
        repository: repository,
        seed: seed,
        almostWon: true,
      ),
    );
  }

  Future<void> _resume(BuildContext context, String variant) async {
    final SavedGame? saved = await repository.loadGame(variant);
    if (!context.mounted) {
      return;
    }
    if (saved == null) {
      _play(context, variant);
      return;
    }
    _open(
      context,
      GameBloc(
        variant: variant,
        repository: repository,
        seed: saved.seed,
        state: saved.state,
      ),
    );
  }

  void _openRecords(BuildContext context, String variant) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RecordsScreen(
          repository: repository,
          variant: variant,
          title: variantTitle(variant),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Game game = GameCatalog.games.firstWhere((Game g) => g.id == gameId);
    return Scaffold(
      body: FeltBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FeltHeader(
                title: gameTitle(gameId),
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: MenuWidthLimit(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      for (final String variant in game.variantIds)
                        _VariantRow(
                          variant: variant,
                          hasSave: repository.hasSave(variant),
                          onPlay: () => _play(context, variant),
                          onResume: () => _resume(context, variant),
                          onRecords: () => _openRecords(context, variant),
                          onPlayAlmostWon: debugDeals
                              ? () => _playAlmostWon(context, variant)
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VariantRow extends StatelessWidget {
  const _VariantRow({
    required this.variant,
    required this.hasSave,
    required this.onPlay,
    required this.onResume,
    required this.onRecords,
    this.onPlayAlmostWon,
  });

  final String variant;
  final Future<bool> hasSave;
  final VoidCallback onPlay;
  final VoidCallback onResume;
  final VoidCallback onRecords;

  /// Null hides the "test win" trigger entirely (see [GameOptionsScreen.debugDeals]).
  final VoidCallback? onPlayAlmostWon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              variantShortLabel(variant),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(variantDescriptor(variant)),
            const SizedBox(height: 12),
            FutureBuilder<bool>(
              future: hasSave,
              builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
                final bool saved = snapshot.data ?? false;
                return Wrap(
                  spacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: onPlay,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Play'),
                    ),
                    if (saved)
                      OutlinedButton.icon(
                        onPressed: onResume,
                        icon: const Icon(Icons.restore),
                        label: const Text('Resume'),
                      ),
                    TextButton.icon(
                      onPressed: onRecords,
                      icon: const Icon(Icons.leaderboard),
                      label: const Text('Records'),
                    ),
                    if (onPlayAlmostWon != null)
                      OutlinedButton.icon(
                        onPressed: onPlayAlmostWon,
                        icon: const Icon(Icons.bug_report),
                        label: const Text('Test win'),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
