import 'package:flutter/material.dart';

import '../persistence/records_repository.dart';
import '../persistence/stats.dart';
import 'hud.dart';

/// Per-variant records / leaderboard. Reads [Stats] from the repository and
/// renders them read-only. No game logic — just a view of stored results.
class RecordsScreen extends StatelessWidget {
  const RecordsScreen({
    required this.repository,
    required this.variant,
    required this.title,
    super.key,
  });

  final RecordsRepository repository;
  final String variant;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$title — Records')),
      body: FutureBuilder<Stats>(
        future: repository.statsFor(variant),
        builder: (BuildContext context, AsyncSnapshot<Stats> snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final Stats stats = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _RecordTile(label: 'Games played', value: '${stats.gamesPlayed}'),
              _RecordTile(label: 'Games won', value: '${stats.gamesWon}'),
              _RecordTile(
                label: 'Win rate',
                value: '${stats.winPercentage.toStringAsFixed(1)}%',
              ),
              _RecordTile(
                label: 'Best time',
                value: stats.bestTimeSeconds == null
                    ? '—'
                    : Hud.formatDuration(stats.bestTimeSeconds!),
              ),
              _RecordTile(
                label: 'Fewest moves',
                value: stats.fewestMoves?.toString() ?? '—',
              ),
              _RecordTile(
                label: 'Current streak',
                value: '${stats.currentStreak}',
              ),
              _RecordTile(
                label: 'Longest streak',
                value: '${stats.longestStreak}',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
