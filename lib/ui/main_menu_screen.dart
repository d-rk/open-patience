import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/game_registry.dart';
import '../persistence/records_repository.dart';
import '../presentation/bloc/game_bloc.dart';
import 'game_screen.dart';
import 'records_screen.dart';
import 'theme/widgets.dart';
import 'variant_labels.dart';

/// The entry screen: one card per variant with Play, Resume (when a save
/// exists) and Records. Building a game here is just constructing a [GameBloc]
/// and pushing a [GameScreen]; the menu holds no game logic.
class MainMenuScreen extends StatelessWidget {
  const MainMenuScreen({required this.repository, this.autoTick, super.key});

  final RecordsRepository repository;

  /// Forwarded to each [GameScreen]; null in tests to avoid pending timers.
  final Duration? autoTick;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FeltBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const FeltHeader(title: '♠ Open Patience ♥'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    for (final String id in GameRegistry.ids)
                      _VariantCard(
                        variant: id,
                        repository: repository,
                        autoTick: autoTick,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VariantCard extends StatelessWidget {
  const _VariantCard({
    required this.variant,
    required this.repository,
    required this.autoTick,
  });

  final String variant;
  final RecordsRepository repository;
  final Duration? autoTick;

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

  void _newGame(BuildContext context) {
    final int seed = Random().nextInt(1 << 32);
    _open(
      context,
      GameBloc.newGame(variant: variant, repository: repository, seed: seed),
    );
  }

  Future<void> _resume(BuildContext context) async {
    final SavedGame? saved = await repository.loadGame(variant);
    if (!context.mounted) {
      return;
    }
    if (saved == null) {
      _newGame(context);
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

  void _openRecords(BuildContext context) {
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              variantTitle(variant),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            FutureBuilder<bool>(
              future: repository.hasSave(variant),
              builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
                final bool hasSave = snapshot.data ?? false;
                return Wrap(
                  spacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: () => _newGame(context),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('New game'),
                    ),
                    if (hasSave)
                      OutlinedButton.icon(
                        onPressed: () => _resume(context),
                        icon: const Icon(Icons.restore),
                        label: const Text('Resume'),
                      ),
                    TextButton.icon(
                      onPressed: () => _openRecords(context),
                      icon: const Icon(Icons.leaderboard),
                      label: const Text('Records'),
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
