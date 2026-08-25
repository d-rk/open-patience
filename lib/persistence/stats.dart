import 'package:equatable/equatable.dart';

/// A single completed win: when it happened and how it went. Immutable.
class WinRecord extends Equatable {
  const WinRecord({
    required this.timestamp,
    required this.timeSeconds,
    required this.moves,
  });

  factory WinRecord.fromJson(Map<String, dynamic> json) => WinRecord(
    timestamp: DateTime.parse(json['timestamp'] as String),
    timeSeconds: json['timeSeconds'] as int,
    moves: json['moves'] as int,
  );

  final DateTime timestamp;
  final int timeSeconds;
  final int moves;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'timestamp': timestamp.toIso8601String(),
    'timeSeconds': timeSeconds,
    'moves': moves,
  };

  @override
  List<Object?> get props => <Object?>[timestamp, timeSeconds, moves];

  @override
  bool get stringify => true;
}

/// Per-variant records: a running win count plus a capped leaderboard of the
/// fastest wins. Immutable value object: [recordWin] returns an updated
/// copy, which keeps the leaderboard math (ranking, capping) easy to test in
/// isolation from storage.
class Stats extends Equatable {
  const Stats({this.totalWins = 0, this.bestWins = const <WinRecord>[]});

  factory Stats.empty() => const Stats();

  factory Stats.fromJson(Map<String, dynamic> json) => Stats(
    totalWins: json['totalWins'] as int,
    bestWins: (json['bestWins'] as List<dynamic>)
        .map((dynamic e) => WinRecord.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  /// How many of the fastest wins are kept on the leaderboard.
  static const int maxBestWins = 10;

  final int totalWins;

  /// The fastest wins so far, sorted ascending by time (ties broken by fewer
  /// moves), capped at [maxBestWins]. `bestWins.first` is the best win ever;
  /// the list may be empty or shorter than the cap before enough wins exist.
  final List<WinRecord> bestWins;

  /// A copy reflecting one more win: increments [totalWins] unconditionally,
  /// and inserts a record for [timestamp]/[timeSeconds]/[moves] into
  /// [bestWins] if it ranks among the fastest [maxBestWins] — a win that
  /// doesn't crack the leaderboard still counts toward the total.
  Stats recordWin({
    required int timeSeconds,
    required int moves,
    required DateTime timestamp,
  }) {
    if (timeSeconds < 0 || moves < 0) {
      throw ArgumentError('timeSeconds and moves must be non-negative');
    }
    final List<WinRecord> updated =
        <WinRecord>[
          ...bestWins,
          WinRecord(
            timestamp: timestamp,
            timeSeconds: timeSeconds,
            moves: moves,
          ),
        ]..sort((WinRecord a, WinRecord b) {
          final int byTime = a.timeSeconds.compareTo(b.timeSeconds);
          return byTime != 0 ? byTime : a.moves.compareTo(b.moves);
        });
    return Stats(
      totalWins: totalWins + 1,
      bestWins: updated.take(maxBestWins).toList(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'totalWins': totalWins,
    'bestWins': bestWins.map((WinRecord w) => w.toJson()).toList(),
  };

  @override
  List<Object?> get props => <Object?>[totalWins, bestWins];

  @override
  bool get stringify => true;
}
