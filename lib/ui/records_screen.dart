import 'package:flutter/material.dart';

import '../persistence/records_repository.dart';
import '../persistence/stats.dart';
import 'theme/game_fonts.dart';
import 'theme/game_palette.dart';
import 'theme/widgets.dart';

const List<String> _monthAbbr = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A short date for a leaderboard row: `Today` for the current calendar day
/// (local time), otherwise `MMM d` (e.g. `Aug 20`).
String _formatWinDate(DateTime timestamp) {
  final DateTime now = DateTime.now();
  final bool isToday =
      timestamp.year == now.year &&
      timestamp.month == now.month &&
      timestamp.day == now.day;
  return isToday
      ? 'Today'
      : '${_monthAbbr[timestamp.month - 1]} ${timestamp.day}';
}

/// Per-variant records / leaderboard. Reads [Stats] from the repository and
/// renders them read-only. No game logic — just a view of stored results.
class RecordsScreen extends StatelessWidget {
  const RecordsScreen({
    required this.repository,
    required this.variant,
    required this.title,
    this.justWonTimeSeconds,
    this.justWonMoves,
    super.key,
  });

  final RecordsRepository repository;
  final String variant;
  final String title;

  /// Set only when this screen was pushed straight from a win, so that win
  /// can be called out and located on the leaderboard. Both null otherwise.
  final int? justWonTimeSeconds;
  final int? justWonMoves;

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
        final int justWonRank = _justWonRank(stats);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            MenuWidthLimit(
              maxWidth: 480,
              child: Column(
                children: <Widget>[
                  if (justWonTimeSeconds != null &&
                      justWonMoves != null) ...<Widget>[
                    _WinBanner(
                      timeSeconds: justWonTimeSeconds!,
                      moves: justWonMoves!,
                      rank: justWonRank,
                    ),
                    const SizedBox(height: 12),
                  ],
                  _TotalWinsHero(stats: stats),
                  const SizedBox(height: 12),
                  if (stats.bestWins.isEmpty)
                    const _EmptyLeaderboard()
                  else
                    _LeaderboardTable(
                      stats: stats,
                      highlightedIndex: justWonRank == 0 ? -1 : justWonRank - 1,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// The 1-based rank of the just-won run within [stats.bestWins], or `0` if
  /// there was no just-won run or it did not place.
  int _justWonRank(Stats stats) {
    if (justWonTimeSeconds == null || justWonMoves == null) {
      return 0;
    }
    final int index = stats.bestWins.indexWhere(
      (WinRecord w) =>
          w.timeSeconds == justWonTimeSeconds && w.moves == justWonMoves,
    );
    return index == -1 ? 0 : index + 1;
  }
}

/// A celebratory banner named for the just-completed win. Shows a rank chip
/// only when [rank] places within the leaderboard (`rank > 0`).
class _WinBanner extends StatelessWidget {
  const _WinBanner({
    required this.timeSeconds,
    required this.moves,
    required this.rank,
  });

  final int timeSeconds;
  final int moves;
  final int rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: GamePalette.gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GamePalette.gold),
      ),
      child: Row(
        children: <Widget>[
          const Text('🎉', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  color: GamePalette.cardFace,
                  fontFamily: GameFonts.body,
                  fontSize: 13,
                ),
                children: <InlineSpan>[
                  const TextSpan(text: 'You won in '),
                  TextSpan(
                    text: formatDuration(timeSeconds),
                    style: const TextStyle(
                      color: GamePalette.gold,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  TextSpan(text: ' · $moves moves'),
                ],
              ),
            ),
          ),
          if (rank > 0)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: GamePalette.gold,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '#$rank BEST',
                style: const TextStyle(
                  color: GamePalette.feltGreenDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Trophy hero: total wins as the headline number, with the fastest win's
/// time and move count called out beside it. Shows `—` before any win.
class _TotalWinsHero extends StatelessWidget {
  const _TotalWinsHero({required this.stats});

  final Stats stats;

  @override
  Widget build(BuildContext context) {
    final WinRecord? best = stats.bestWins.isEmpty
        ? null
        : stats.bestWins.first;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GamePalette.gold.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: <Widget>[
          const Text('🏆', style: TextStyle(fontSize: 32)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${stats.totalWins}',
                  key: const Key('totalWins'),
                  style: const TextStyle(
                    color: GamePalette.cardFace,
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                  ),
                ),
                Text(
                  'Total wins',
                  style: TextStyle(
                    color: GamePalette.cardFace.withValues(alpha: 0.75),
                    fontFamily: GameFonts.body,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                best == null ? '—' : formatDuration(best.timeSeconds),
                key: const Key('bestWinTime'),
                style: const TextStyle(
                  color: GamePalette.gold,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              Text(
                best == null ? 'Best win' : '${best.moves} moves · best',
                key: const Key('bestWinMoves'),
                style: TextStyle(
                  color: GamePalette.cardFace.withValues(alpha: 0.7),
                  fontFamily: GameFonts.body,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Placeholder shown before the player has won a single game.
class _EmptyLeaderboard extends StatelessWidget {
  const _EmptyLeaderboard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: GamePalette.cardFace.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(
          'Win a game to start your leaderboard.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: GamePalette.cardFace.withValues(alpha: 0.7),
            fontFamily: GameFonts.body,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// The fastest-10 table: rank, time, moves and date, one row per
/// [Stats.bestWins] entry. [highlightedIndex] (0-based, or `-1` for none)
/// gets a gold highlight and a `NEW` tag on its rank.
class _LeaderboardTable extends StatelessWidget {
  const _LeaderboardTable({
    required this.stats,
    required this.highlightedIndex,
  });

  final Stats stats;
  final int highlightedIndex;

  static const List<Color> _rankColors = <Color>[
    GamePalette.gold, // 1st
    GamePalette.silver, // 2nd
    GamePalette.bronze, // 3rd
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GamePalette.cardFace.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < stats.bestWins.length; i++)
            _LeaderboardRow(
              rank: i + 1,
              record: stats.bestWins[i],
              rankColor: i < _rankColors.length
                  ? _rankColors[i]
                  : GamePalette.cardFace,
              highlighted: i == highlightedIndex,
              isFirst: i == 0,
            ),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({
    required this.rank,
    required this.record,
    required this.rankColor,
    required this.highlighted,
    required this.isFirst,
  });

  final int rank;
  final WinRecord record;
  final Color rankColor;
  final bool highlighted;
  final bool isFirst;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: highlighted ? GamePalette.gold.withValues(alpha: 0.18) : null,
        border: Border(
          top: isFirst
              ? BorderSide.none
              : BorderSide(color: GamePalette.cardFace.withValues(alpha: 0.08)),
          left: highlighted
              ? const BorderSide(color: GamePalette.gold, width: 3)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              key: ValueKey<String>('rank-$rank'),
              style: TextStyle(color: rankColor, fontWeight: FontWeight.w800),
            ),
          ),
          if (highlighted)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: GamePalette.gold,
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Text(
                'NEW',
                style: TextStyle(
                  color: GamePalette.feltGreenDark,
                  fontWeight: FontWeight.w800,
                  fontSize: 9,
                ),
              ),
            ),
          Expanded(
            child: Text(
              formatDuration(record.timeSeconds),
              key: ValueKey<String>('time-$rank'),
              style: const TextStyle(
                color: GamePalette.cardFace,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${record.moves} moves',
              key: ValueKey<String>('moves-$rank'),
              style: TextStyle(
                color: GamePalette.cardFace.withValues(alpha: 0.7),
                fontFamily: GameFonts.body,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            _formatWinDate(record.timestamp),
            key: ValueKey<String>('date-$rank'),
            style: TextStyle(
              color: GamePalette.cardFace.withValues(alpha: 0.55),
              fontFamily: GameFonts.body,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
