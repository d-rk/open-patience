import 'package:flutter/material.dart';

import '../persistence/records_repository.dart';
import '../persistence/stats.dart';
import 'theme/game_fonts.dart';
import 'theme/game_palette.dart';
import 'theme/widgets.dart';

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
      body: FeltBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              FeltHeader(
                title: 'Records',
                subtitle: title,
                onBack: () => Navigator.of(context).pop(),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    return FutureBuilder<Stats>(
      future: repository.statsFor(variant),
      builder: (BuildContext context, AsyncSnapshot<Stats> snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final Stats stats = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            MenuWidthLimit(
              maxWidth: 480,
              child: Column(
                children: <Widget>[
                  _WinRateHero(stats: stats),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _StatTile(
                          icon: Icons.style,
                          value: '${stats.gamesPlayed}',
                          label: 'Played',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatTile(
                          icon: Icons.emoji_events,
                          value: '${stats.gamesWon}',
                          label: 'Won',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _StatTile(
                          icon: Icons.timer,
                          value: stats.bestTimeSeconds == null
                              ? '—'
                              : formatDuration(stats.bestTimeSeconds!),
                          label: 'Best time',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatTile(
                          icon: Icons.directions_walk,
                          value: stats.fewestMoves?.toString() ?? '—',
                          label: 'Fewest moves',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _StatTile(
                          icon: Icons.local_fire_department,
                          iconColor: stats.currentStreak > 0
                              ? GamePalette.gold
                              : GamePalette.gold.withValues(alpha: 0.3),
                          value: '${stats.currentStreak}',
                          label: 'Current streak',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _StatTile(
                          icon: Icons.trending_up,
                          value: '${stats.longestStreak}',
                          label: 'Longest streak',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Win rate as a gold progress ring — a pure indicator, nothing drawn on
/// top of it — beside a headline percentage and a won/lost legend. The
/// ring's fill fraction is the win rate, so it stays meaningful without
/// needing to also host text: that combination is what kept breaking (see
/// git history around this file for the abandoned attempts at centering
/// text inside the ring itself).
class _WinRateHero extends StatelessWidget {
  const _WinRateHero({required this.stats});

  static const double _ringSize = 88;
  static const double _ringStroke = 10;

  final Stats stats;

  @override
  Widget build(BuildContext context) {
    final int lost = stats.gamesPlayed - stats.gamesWon;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GamePalette.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _ringSize,
            height: _ringSize,
            child: CircularProgressIndicator(
              value: stats.winPercentage / 100,
              strokeWidth: _ringStroke,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(GamePalette.gold),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${stats.winPercentage.round()}%',
                  style: const TextStyle(
                    color: GamePalette.cardFace,
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                  ),
                ),
                Text(
                  'Win rate',
                  style: TextStyle(
                    color: GamePalette.cardFace.withValues(alpha: 0.75),
                    fontFamily: GameFonts.body,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                _LegendRow(
                  dotColor: GamePalette.gold,
                  text: '${stats.gamesWon} won',
                ),
                const SizedBox(height: 4),
                _LegendRow(
                  dotColor: Colors.white.withValues(alpha: 0.16),
                  dotBorderColor: GamePalette.cardFace.withValues(alpha: 0.4),
                  text: '$lost lost',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A small colored dot beside a label — one row of the win/lost legend.
class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.dotColor,
    required this.text,
    this.dotBorderColor,
  });

  final Color dotColor;
  final Color? dotBorderColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            border: dotBorderColor == null
                ? null
                : Border.all(color: dotBorderColor!),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            color: GamePalette.cardFace.withValues(alpha: 0.7),
            fontFamily: GameFonts.body,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}

/// A single stat as an icon, a large value and a small label.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.iconColor = GamePalette.gold,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: GamePalette.cardFace.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: GamePalette.cardFace,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: GamePalette.cardFace.withValues(alpha: 0.7),
              fontFamily: GameFonts.body,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
