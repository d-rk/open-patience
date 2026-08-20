import 'package:equatable/equatable.dart';

/// Per-variant records. Immutable value object: [recordWin] and [recordLoss]
/// return updated copies, which keeps the records math easy to test in
/// isolation from any storage.
class Stats extends Equatable {
  const Stats({
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.bestTimeSeconds,
    this.fewestMoves,
    this.currentStreak = 0,
    this.longestStreak = 0,
  });

  factory Stats.empty() => const Stats();

  factory Stats.fromJson(Map<String, dynamic> json) {
    return Stats(
      gamesPlayed: json['gamesPlayed'] as int,
      gamesWon: json['gamesWon'] as int,
      bestTimeSeconds: json['bestTimeSeconds'] as int?,
      fewestMoves: json['fewestMoves'] as int?,
      currentStreak: json['currentStreak'] as int,
      longestStreak: json['longestStreak'] as int,
    );
  }

  final int gamesPlayed;
  final int gamesWon;

  /// Best (lowest) winning time in seconds, or `null` before the first win.
  final int? bestTimeSeconds;

  /// Fewest moves in a win, or `null` before the first win.
  final int? fewestMoves;
  final int currentStreak;
  final int longestStreak;

  /// Win rate as a percentage in `0..100`; `0` when no games have been played.
  double get winPercentage =>
      gamesPlayed == 0 ? 0 : gamesWon * 100 / gamesPlayed;

  /// A copy updated for a win of [timeSeconds] and [moves]: increments played
  /// and won, lowers best time / fewest moves when beaten, extends the current
  /// streak and raises the longest streak when the current one overtakes it.
  Stats recordWin({required int timeSeconds, required int moves}) {
    if (timeSeconds < 0 || moves < 0) {
      throw ArgumentError('timeSeconds and moves must be non-negative');
    }
    final int nextStreak = currentStreak + 1;
    return Stats(
      gamesPlayed: gamesPlayed + 1,
      gamesWon: gamesWon + 1,
      bestTimeSeconds: bestTimeSeconds == null
          ? timeSeconds
          : (timeSeconds < bestTimeSeconds! ? timeSeconds : bestTimeSeconds),
      fewestMoves: fewestMoves == null
          ? moves
          : (moves < fewestMoves! ? moves : fewestMoves),
      currentStreak: nextStreak,
      longestStreak: nextStreak > longestStreak ? nextStreak : longestStreak,
    );
  }

  /// A copy updated for a loss: increments played and resets the current
  /// streak; best records and longest streak are untouched.
  Stats recordLoss() {
    return Stats(
      gamesPlayed: gamesPlayed + 1,
      gamesWon: gamesWon,
      bestTimeSeconds: bestTimeSeconds,
      fewestMoves: fewestMoves,
      currentStreak: 0,
      longestStreak: longestStreak,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'gamesPlayed': gamesPlayed,
    'gamesWon': gamesWon,
    'bestTimeSeconds': bestTimeSeconds,
    'fewestMoves': fewestMoves,
    'currentStreak': currentStreak,
    'longestStreak': longestStreak,
  };

  @override
  List<Object?> get props => <Object?>[
    gamesPlayed,
    gamesWon,
    bestTimeSeconds,
    fewestMoves,
    currentStreak,
    longestStreak,
  ];

  @override
  bool get stringify => true;
}
