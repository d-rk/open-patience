// Generates tools/video/demo_save.json — the near-finished Klondike deal the
// gameplay video (tools/video/capture_gameplay.py) is recorded from.
//
// This script is the single source of truth for that file; never hand-edit the
// JSON. It imports only lib/core and lib/persistence (both Flutter-free), so it
// runs under plain `dart run` with no Flutter binding:
//
//     dart run tools/video/make_demo_save.dart
//
// Output is deterministic: the seed scan starts at a fixed seed, the move
// prefix is a pure function of the greedy solution, and the stats timestamps
// are hard-coded — so re-running reproduces the file byte for byte.
//
// A full run scans on the order of 48,000 seeds and takes about 80 seconds —
// the committed fixture landed on seed 48238. That is expected, not a hang.
import 'dart:convert';
import 'dart:io';

import 'package:open_patience/core/game_registry.dart';
import 'package:open_patience/core/game_rules.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/move.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/core/solver.dart';
import 'package:open_patience/persistence/stats.dart';

const String _variant = GameRegistry.klondikeDraw1;

/// Where the seed scan starts. Fixed, so the output is reproducible.
const int _firstSeed = 1;

/// Give up rather than spin forever if a rules change makes greedily solvable
/// deals vanish — a loud failure beats a silent hang.
const int _maxSeedsScanned = 200000;

/// Replay the solution until at least this many cards sit on the foundations.
/// Half the deck: the board still shows plenty of tableau, and the remaining
/// solve is a long, photogenic cascade.
const int _minFoundationCards = 26;

/// What the HUD timer should read on resume (3:34) — a plausible session
/// rather than 0:00.
const int _elapsedSeconds = 214;

/// Prior wins, so the records screen the video ends on is populated.
/// Timestamps are fixed (never DateTime.now()) to keep the output reproducible.
final List<WinRecord> _priorWins = <WinRecord>[
  WinRecord(
    timestamp: DateTime.utc(2026, 8, 29, 20, 14),
    timeSeconds: 187,
    moves: 132,
  ),
  WinRecord(
    timestamp: DateTime.utc(2026, 9, 1, 7, 42),
    timeSeconds: 231,
    moves: 148,
  ),
  WinRecord(
    timestamp: DateTime.utc(2026, 9, 3, 21, 5),
    timeSeconds: 264,
    moves: 156,
  ),
];
// Kept internally consistent with _priorWins: recordWin() never lets
// totalWins outrun the leaderboard while bestWins is still under
// Stats.maxBestWins, so a mismatched value here would show up on the
// records screen as an impossible stats state (a total higher than the
// number of leaderboard rows the app could ever produce for it).
final int _totalWins = _priorWins.length;

void main() {
  final GameRules rules = GameRegistry.rulesFor(_variant);

  final int seed = _findGreedilySolvableSeed(rules);
  final GameState state = GameState.newGame(rules, seed: seed);
  final List<Move> solution = solveGreedy(state, rules)!;

  final int played = _replayUntilFoundationsReach(state, solution);
  state.elapsedSeconds = _elapsedSeconds;

  final Map<String, dynamic> fixture = <String, dynamic>{
    '$_savePrefix$_variant': <String, dynamic>{
      'variant': _variant,
      'seed': seed,
      'state': state.toJson(),
    },
    '$_statsPrefix$_variant': Stats(
      totalWins: _totalWins,
      bestWins: _priorWins,
    ).toJson(),
  };

  final File out = File('tools/video/demo_save.json');
  out.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(fixture)}\n',
  );

  stdout.writeln('seed             : $seed');
  stdout.writeln('solution length  : ${solution.length} moves');
  stdout.writeln('replayed         : $played moves');
  stdout.writeln('on foundations   : ${_foundationCards(state)} cards');
  stdout.writeln('remaining solve  : ${solution.length - played} moves');
  stdout.writeln('wrote            : ${out.path}');
}

/// Most Klondike deals cannot be finished by the greedy solver from the
/// opening; scan until one can. That deal is the only kind whose *prefix*
/// states are all still greedily solvable, which is what makes the Solve
/// button live the moment the video resumes the save.
int _findGreedilySolvableSeed(GameRules rules) {
  for (int seed = _firstSeed; seed < _firstSeed + _maxSeedsScanned; seed++) {
    final GameState candidate = GameState.newGame(rules, seed: seed);
    if (solveGreedy(candidate, rules) != null) {
      return seed;
    }
  }
  throw StateError(
    'No greedily solvable $_variant deal in $_maxSeedsScanned seeds from '
    '$_firstSeed — the rules or the solver changed.',
  );
}

/// Applies solution moves to [state] in order until the foundations hold at
/// least [_minFoundationCards]. Returns how many moves were applied.
int _replayUntilFoundationsReach(GameState state, List<Move> solution) {
  for (int i = 0; i < solution.length; i++) {
    if (_foundationCards(state) >= _minFoundationCards) {
      return i;
    }
    state.applyMove(solution[i]);
  }
  throw StateError(
    'Solution ended with only ${_foundationCards(state)} cards on the '
    'foundations; expected at least $_minFoundationCards.',
  );
}

int _foundationCards(GameState state) => state.piles
    .where((Pile p) => p.kind == PileKind.foundation)
    .fold<int>(0, (int sum, Pile p) => sum + p.length);

// Mirrors SharedPrefsRecordsRepository's key layout. Duplicated as plain
// constants rather than imported, because that class pulls in
// package:shared_preferences, which needs a Flutter binding this CLI does not
// have. test/unit/demo_save_test.dart loads the output *through* the real
// repository, so a drift between the two fails the suite.
const String _savePrefix = 'save:';
const String _statsPrefix = 'stats:';
