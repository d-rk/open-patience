# Records Win Leaderboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace loss tracking on the Records screen with a local top-10
fastest-wins leaderboard, and call out the just-completed win when the
screen is reached straight from a win.

**Architecture:** `Stats` becomes an ever-incrementing `totalWins` counter
plus a `bestWins` list of `WinRecord` (timestamp/time/moves) capped at the
10 fastest. `RecordsRepository.recordResult(won: ...)` becomes
`recordWin(...)`. `GameBloc` and `MainMenuScreen` drop their loss-recording
call sites entirely. `RecordsScreen` gets a new hero + table layout plus an
optional "just won" banner wired from `GameScreen`.

**Tech Stack:** Flutter (latest stable), Dart, `flutter_bloc`,
`shared_preferences`, `equatable`, `flutter_test`/`bloc_test`.

**Spec:** `docs/superpowers/specs/2026-08-25-records-leaderboard-design.md`

## Global Constraints

- TDD mandatory: write the failing test before any production code change,
  per task (RED → GREEN → REFACTOR).
- `core/` and `persistence/` must have zero `package:flutter` imports —
  verified per task with `grep -rl "package:flutter" lib/core lib/persistence`
  (expect no output).
- Explicit static types on all public APIs; no `dynamic`.
- `dart format` clean (2-space indent, trailing commas on multi-line
  collections/parameter lists) before each commit.
- `Stats.recordWin` takes `timestamp` as a required parameter — it never
  calls `DateTime.now()` itself, so it stays a pure, deterministically
  testable value object. Only the repository (an already-impure boundary)
  supplies the real clock.
- `bestWins` is capped at `Stats.maxBestWins` (10) by the capping logic
  inside `Stats.recordWin` itself, not just at render time.
- Every new happy-path interaction gets a widget test (empty state, win
  banner, highlighted leaderboard row).

---

## Task 1: `WinRecord` + rewritten `Stats` (`persistence/stats.dart`)

**Files:**
- Modify: `lib/persistence/stats.dart` (full rewrite)
- Test: `test/unit/stats_test.dart` (full rewrite)

**Interfaces:**
- Produces:
  - `class WinRecord extends Equatable { WinRecord({required DateTime timestamp, required int timeSeconds, required int moves}); factory WinRecord.fromJson(Map<String, dynamic> json); Map<String, dynamic> toJson(); }`
  - `class Stats extends Equatable { const Stats({int totalWins = 0, List<WinRecord> bestWins = const <WinRecord>[]}); factory Stats.empty(); factory Stats.fromJson(Map<String, dynamic> json); static const int maxBestWins = 10; final int totalWins; final List<WinRecord> bestWins; Stats recordWin({required int timeSeconds, required int moves, required DateTime timestamp}); Map<String, dynamic> toJson(); }`
- Consumes: nothing (this is the base layer for the whole change).

- [ ] **Step 1: Write the failing test file**

Replace the entire contents of `test/unit/stats_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/persistence/stats.dart';

void main() {
  group('WinRecord', () {
    test('json round-trips to an equal record', () {
      final WinRecord w = WinRecord(
        timestamp: DateTime(2026, 8, 20, 14, 32),
        timeSeconds: 123,
        moves: 87,
      );
      expect(WinRecord.fromJson(w.toJson()), equals(w));
    });
  });

  group('Stats math', () {
    test('empty stats have zero wins and no leaderboard entries', () {
      const Stats s = Stats();
      expect(s.totalWins, 0);
      expect(s.bestWins, isEmpty);
    });

    test(
      'recordWin always increments totalWins, even off the leaderboard',
      () {
        Stats s = const Stats();
        s = s.recordWin(
          timeSeconds: 100,
          moves: 50,
          timestamp: DateTime(2026, 1, 1),
        );
        s = s.recordWin(
          timeSeconds: 90,
          moves: 40,
          timestamp: DateTime(2026, 1, 2),
        );
        expect(s.totalWins, 2);
      },
    );

    test('bestWins is sorted fastest-first, ties broken by fewer moves', () {
      Stats s = const Stats();
      s = s.recordWin(
        timeSeconds: 100,
        moves: 50,
        timestamp: DateTime(2026, 1, 1),
      );
      s = s.recordWin(
        timeSeconds: 80,
        moves: 60,
        timestamp: DateTime(2026, 1, 2),
      );
      s = s.recordWin(
        timeSeconds: 80,
        moves: 45,
        timestamp: DateTime(2026, 1, 3),
      );
      expect(s.bestWins.map((WinRecord w) => w.moves).toList(), <int>[
        45,
        60,
        50,
      ]);
    });

    test('bestWins is capped at maxBestWins, keeping only the fastest', () {
      Stats s = const Stats();
      for (int i = 0; i < Stats.maxBestWins; i++) {
        s = s.recordWin(
          timeSeconds: 100 + i,
          moves: 50,
          timestamp: DateTime(2026, 1, 1),
        );
      }
      expect(s.bestWins.length, Stats.maxBestWins);
      expect(s.totalWins, Stats.maxBestWins);

      // A slower win doesn't grow or change the list.
      s = s.recordWin(
        timeSeconds: 999,
        moves: 50,
        timestamp: DateTime(2026, 1, 2),
      );
      expect(s.bestWins.length, Stats.maxBestWins);
      expect(s.bestWins.any((WinRecord w) => w.timeSeconds == 999), isFalse);
      expect(s.totalWins, Stats.maxBestWins + 1);

      // A faster win evicts the current slowest.
      final int slowestBefore = s.bestWins.last.timeSeconds;
      s = s.recordWin(
        timeSeconds: 50,
        moves: 50,
        timestamp: DateTime(2026, 1, 3),
      );
      expect(s.bestWins.length, Stats.maxBestWins);
      expect(s.bestWins.first.timeSeconds, 50);
      expect(
        s.bestWins.any((WinRecord w) => w.timeSeconds == slowestBefore),
        isFalse,
      );
    });

    test('recordWin rejects negative time or moves', () {
      const Stats s = Stats();
      expect(
        () => s.recordWin(
          timeSeconds: -1,
          moves: 0,
          timestamp: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
      expect(
        () => s.recordWin(
          timeSeconds: 0,
          moves: -1,
          timestamp: DateTime(2026, 1, 1),
        ),
        throwsArgumentError,
      );
    });

    test('json round-trips to equal stats', () {
      final Stats s = const Stats()
          .recordWin(
            timeSeconds: 45,
            moves: 33,
            timestamp: DateTime(2026, 8, 20),
          )
          .recordWin(
            timeSeconds: 60,
            moves: 20,
            timestamp: DateTime(2026, 8, 21),
          );
      expect(Stats.fromJson(s.toJson()), equals(s));
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/unit/stats_test.dart`
Expected: FAIL — `WinRecord` is undefined and `Stats` has no `recordWin`
with a `timestamp` parameter (current `Stats` predates this shape).

- [ ] **Step 3: Write the minimal implementation**

Replace the entire contents of `lib/persistence/stats.dart` with:

```dart
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/unit/stats_test.dart`
Expected: PASS (all tests green).

- [ ] **Step 5: Verify the Flutter-free boundary still holds**

Run: `grep -rl "package:flutter" lib/core lib/persistence`
Expected: no output.

- [ ] **Step 6: Format and commit**

```bash
dart format lib/persistence/stats.dart test/unit/stats_test.dart
git add lib/persistence/stats.dart test/unit/stats_test.dart
git commit -m "feat(records): replace loss-aware Stats with a win leaderboard model"
```

---

## Task 2: Repository interface — `recordResult` → `recordWin`

**Files:**
- Modify: `lib/persistence/records_repository.dart:22-30`
- Modify: `lib/persistence/shared_prefs_records_repository.dart:19-35`
- Test: `test/unit/persistence_test.dart:1-53`

**Interfaces:**
- Consumes: `Stats.recordWin({required int timeSeconds, required int moves, required DateTime timestamp})` from Task 1.
- Produces: `abstract Future<void> recordWin({required String variant, required int timeSeconds, required int moves})` on `RecordsRepository`, implemented by `SharedPrefsRecordsRepository`. This is what `GameBloc` (Task 3) and any repository fake call.

- [ ] **Step 1: Write the failing tests**

In `test/unit/persistence_test.dart`, add `import 'dart:convert';` as the
first import, then replace the `test('recordResult persists and
accumulates per variant', ...)` block (currently lines 26-47) with:

```dart
    test('recordWin persists and accumulates per variant', () async {
      await repo.recordWin(variant: 'freecell', timeSeconds: 90, moves: 60);
      await repo.recordWin(variant: 'freecell', timeSeconds: 70, moves: 55);
      final Stats s = await repo.statsFor('freecell');
      expect(s.totalWins, 2);
      expect(s.bestWins.first.timeSeconds, 70);
      // Other variants are unaffected.
      expect(await repo.statsFor('klondike-draw1'), Stats.empty());
    });

    test('corrupt stats blob degrades to empty rather than throwing', () async {
      await prefs.setString('stats:freecell', 'not json');
      expect(await repo.statsFor('freecell'), Stats.empty());
    });

    test(
      'old pre-leaderboard stats blob degrades to empty rather than '
      'throwing',
      () async {
        await prefs.setString(
          'stats:freecell',
          jsonEncode(<String, dynamic>{
            'gamesPlayed': 5,
            'gamesWon': 3,
            'bestTimeSeconds': 120,
            'fewestMoves': 80,
            'currentStreak': 1,
            'longestStreak': 2,
          }),
        );
        expect(await repo.statsFor('freecell'), Stats.empty());
      },
    );
```

(This replaces the old `'recordResult persists...'` test and the
already-present `'corrupt stats blob...'` test, and adds the new
old-shape-migration test — leave everything after this group, i.e. the
`SharedPrefsRecordsRepository save/resume` group, untouched.)

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/unit/persistence_test.dart`
Expected: FAIL — `recordWin` is not defined on `SharedPrefsRecordsRepository`.

- [ ] **Step 3: Update the repository interface**

In `lib/persistence/records_repository.dart`, replace:

```dart
  /// Records a finished game against [variant]'s stats. [timeSeconds] and
  /// [moves] are only consulted for a win.
  Future<void> recordResult({
    required String variant,
    required bool won,
    required int timeSeconds,
    required int moves,
  });
```

with:

```dart
  /// Records a win for [variant] with [timeSeconds] and [moves].
  Future<void> recordWin({
    required String variant,
    required int timeSeconds,
    required int moves,
  });
```

- [ ] **Step 4: Update the shared_preferences implementation**

In `lib/persistence/shared_prefs_records_repository.dart`, replace:

```dart
  @override
  Future<void> recordResult({
    required String variant,
    required bool won,
    required int timeSeconds,
    required int moves,
  }) async {
    final Stats current = await statsFor(variant);
    final Stats updated = won
        ? current.recordWin(timeSeconds: timeSeconds, moves: moves)
        : current.recordLoss();
    await _prefs.setString(
      '$statsPrefix$variant',
      jsonEncode(updated.toJson()),
    );
  }
```

with:

```dart
  @override
  Future<void> recordWin({
    required String variant,
    required int timeSeconds,
    required int moves,
  }) async {
    final Stats current = await statsFor(variant);
    final Stats updated = current.recordWin(
      timeSeconds: timeSeconds,
      moves: moves,
      timestamp: DateTime.now(),
    );
    await _prefs.setString(
      '$statsPrefix$variant',
      jsonEncode(updated.toJson()),
    );
  }
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/unit/persistence_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify the Flutter-free boundary still holds**

Run: `grep -rl "package:flutter" lib/core lib/persistence`
Expected: no output.

- [ ] **Step 7: Format and commit**

```bash
dart format lib/persistence/records_repository.dart lib/persistence/shared_prefs_records_repository.dart test/unit/persistence_test.dart
git add lib/persistence/records_repository.dart lib/persistence/shared_prefs_records_repository.dart test/unit/persistence_test.dart
git commit -m "feat(records): rename RecordsRepository.recordResult to recordWin"
```

**Note:** this task intentionally leaves `lib/presentation/bloc/game_bloc.dart`
and `lib/ui/main_menu_screen.dart` calling the now-deleted `recordResult` —
the project will not compile between this task and Task 3. That's expected
and resolved by the next task; do not attempt to make this task compile in
isolation.

---

## Task 3: `GameBloc` — drop loss recording, rename win calls

**Files:**
- Modify: `lib/presentation/bloc/game_bloc.dart:240-267` (call sites), `:269-285` (delete method), `:322-327`, `:362-367` (rename calls)
- Test: `test/unit/game_bloc_test.dart` (fake repo + assertions)

**Interfaces:**
- Consumes: `RecordsRepository.recordWin({required String variant, required int timeSeconds, required int moves})` from Task 2.
- Produces: no new public interface — `GameBloc`'s public API (events, states) is unchanged; only its internal repository calls change.

- [ ] **Step 1: Update the fake repository and win-call assertions in the test file**

In `test/unit/game_bloc_test.dart`, replace the `_FakeRepo.recordResult`
override:

```dart
  @override
  Future<void> recordResult({
    required String variant,
    required bool won,
    required int timeSeconds,
    required int moves,
  }) async {
    calls.add('record:$variant:$won:$timeSeconds:$moves');
  }
```

with:

```dart
  @override
  Future<void> recordWin({
    required String variant,
    required int timeSeconds,
    required int moves,
  }) async {
    calls.add('record:$variant:$timeSeconds:$moves');
  }
```

Then update the three surviving win-call assertions:

- Line `expect(repo.calls, contains('record:klondike-draw1:true:123:1'));`
  → `expect(repo.calls, contains('record:klondike-draw1:123:1'));`
- Line `(String c) => c.startsWith('record:klondike-draw1:true'),`
  (appears twice, in the `AutoSolveRequested` group) →
  `(String c) => c.startsWith('record:klondike-draw1:'),`

Then replace those same four loss-tracking `blocTest` blocks (they sit
together in the `NewDealRequested / RestartDealRequested` group, right
after the `'restart re-deals the same seed'` test and before the group's
closing `});`) with two tests that prove discarding an in-progress game no
longer touches `recordWin` at all:

```dart
    blocTest<GameBloc, GameBlocState>(
      'a new deal discards an in-progress game without recording anything, '
      'just clearing the save',
      build: () => _bloc(_FakeRepo(), _klondikeBoard(moveCount: 3)),
      act: (GameBloc bloc) => bloc.add(const NewDealRequested(seed: 7)),
      verify: (GameBloc bloc) {
        final _FakeRepo repo = bloc.repository as _FakeRepo;
        expect(repo.calls.any((String c) => c.startsWith('record:')), isFalse);
        expect(repo.calls, contains('clear:klondike-draw1'));
      },
    );

    blocTest<GameBloc, GameBlocState>(
      'restarting an in-progress game discards it without recording '
      'anything, just clearing the save',
      build: () => _bloc(_FakeRepo(), _klondikeBoard(moveCount: 2), seed: 44),
      act: (GameBloc bloc) => bloc.add(const RestartDealRequested()),
      verify: (GameBloc bloc) {
        final _FakeRepo repo = bloc.repository as _FakeRepo;
        expect(repo.calls.any((String c) => c.startsWith('record:')), isFalse);
        expect(repo.calls, contains('clear:klondike-draw1'));
      },
    );
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/unit/game_bloc_test.dart`
Expected: FAIL to compile — `GameBloc` still calls the deleted
`repository.recordResult(...)` with a `won:` argument, and still has the
loss-recording call sites the test file no longer exercises (this is a
compile failure, which counts as "fails for the right reason": the
production code hasn't caught up to the interface rename yet).

- [ ] **Step 3: Remove loss recording from `GameBloc`**

In `lib/presentation/bloc/game_bloc.dart`, in `_onNewDealRequested`, delete
the line `await _recordAbandonedLossIfAny();`. In `_onRestartDealRequested`,
delete the same line. Then delete the entire `_recordAbandonedLossIfAny`
method (including its doc comment), i.e. remove:

```dart
  /// Records a loss for the game about to be discarded by a new deal or
  /// restart — but only if the player actually made a move. An untouched
  /// fresh deal getting re-dealt isn't a loss, just changing your mind
  /// before you started. A won game is never here in the first place (the
  /// screen navigates away on a win), but the check is cheap insurance
  /// against double-counting it as a loss too.
  Future<void> _recordAbandonedLossIfAny() async {
    if (_state.moveCount == 0 || _state.isWon(rules)) {
      return;
    }
    await repository.recordResult(
      variant: variant,
      won: false,
      timeSeconds: _state.elapsedSeconds,
      moves: _state.moveCount,
    );
  }
```

- [ ] **Step 4: Rename the two win call sites**

In `_onAutoSolveRequested`, replace:

```dart
          await repository.recordResult(
            variant: variant,
            won: true,
            timeSeconds: elapsed,
            moves: moves,
          );
```

with:

```dart
          await repository.recordWin(
            variant: variant,
            timeSeconds: elapsed,
            moves: moves,
          );
```

In `_emitAfterMove`, replace:

```dart
        await repository.recordResult(
          variant: variant,
          won: true,
          timeSeconds: elapsed,
          moves: moves,
        );
```

with:

```dart
        await repository.recordWin(
          variant: variant,
          timeSeconds: elapsed,
          moves: moves,
        );
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `flutter test test/unit/game_bloc_test.dart`
Expected: PASS.

- [ ] **Step 6: Verify the Flutter-free boundary still holds**

Run: `grep -rl "package:flutter" lib/core lib/persistence`
Expected: no output. (`game_bloc.dart` is in `presentation/`, so it's
allowed to import Flutter — this check is a fixed guard for `core`/`persistence`.)

- [ ] **Step 7: Format and commit**

```bash
dart format lib/presentation/bloc/game_bloc.dart test/unit/game_bloc_test.dart
git add lib/presentation/bloc/game_bloc.dart test/unit/game_bloc_test.dart
git commit -m "feat(records): stop recording losses on new-deal/restart in GameBloc"
```

---

## Task 4: `MainMenuScreen` — drop loss recording on swipe-delete

**Files:**
- Modify: `lib/ui/main_menu_screen.dart:62-77`
- Test: `test/widget/main_menu_test.dart:139-187`

**Interfaces:**
- Consumes: `RecordsRepository.recordWin(...)` (unused by this file after this task — `MainMenuScreen` never calls it).
- Produces: nothing new; `_deleteSave` keeps its existing `void` signature and caller.

- [ ] **Step 1: Update the test file**

In `test/widget/main_menu_test.dart`, delete the two tests titled
`'swiping away a Continue row with moves played records it as a loss'`
(lines 139-165) and `'swiping away an untouched Continue row does not
record a loss'` (lines 167-187). Leave the earlier test in the same group
(`'swiping away a Continue row removes it and clears the save'`, ending at
line 137) and the later `'no Continue section when nothing is in
progress'` test untouched — the file's `Stats` import may become unused
once these two tests are gone; if so, remove the now-unused
`import 'package:open_patience/persistence/stats.dart';` line too (check
with `grep -n "Stats" test/widget/main_menu_test.dart` after deleting).

- [ ] **Step 2: Run the test to verify the remaining tests still fail for the right reason**

Run: `flutter test test/widget/main_menu_test.dart`
Expected: FAIL to compile — `main_menu_screen.dart` still calls the deleted
`repository.recordResult(...)`.

- [ ] **Step 3: Remove the loss-recording block from `_deleteSave`**

In `lib/ui/main_menu_screen.dart`, replace:

```dart
  void _deleteSave(SavedGame saved) {
    // Remove from the model synchronously (Dismissible has already animated the
    // row out), then clear the persisted slot.
    setState(() => _saves?.remove(saved));
    // An untouched fresh deal being discarded isn't a loss — only a save with
    // at least one move on it was actually attempted.
    if (saved.state.moveCount > 0) {
      widget.repository.recordResult(
        variant: saved.variant,
        won: false,
        timeSeconds: saved.state.elapsedSeconds,
        moves: saved.state.moveCount,
      );
    }
    widget.repository.clearSave(saved.variant);
  }
```

with:

```dart
  void _deleteSave(SavedGame saved) {
    // Remove from the model synchronously (Dismissible has already animated the
    // row out), then clear the persisted slot.
    setState(() => _saves?.remove(saved));
    widget.repository.clearSave(saved.variant);
  }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widget/main_menu_test.dart`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
dart format lib/ui/main_menu_screen.dart test/widget/main_menu_test.dart
git add lib/ui/main_menu_screen.dart test/widget/main_menu_test.dart
git commit -m "feat(records): stop recording losses when a Continue save is swiped away"
```

---

## Task 5: Redesign `RecordsScreen` — hero, table, empty state, win banner

**Files:**
- Modify: `lib/ui/records_screen.dart` (full rewrite)
- Test: `test/widget/records_screen_test.dart` (full rewrite)

**Interfaces:**
- Consumes: `Stats`/`WinRecord` from Task 1; `RecordsRepository.statsFor` (unchanged).
- Produces:
  ```dart
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
    final int? justWonTimeSeconds;
    final int? justWonMoves;
  }
  ```
  `justWonTimeSeconds`/`justWonMoves` are consumed by Task 6
  (`GameScreen._navigateToRecords`); every other current call site
  (`GameOptionsScreen._openRecords`) is unaffected since both new
  parameters are optional and default to `null`.

- [ ] **Step 1: Write the failing test file**

Replace the entire contents of `test/widget/records_screen_test.dart` with:

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/persistence/stats.dart';
import 'package:open_patience/ui/records_screen.dart';
import 'package:open_patience/ui/theme/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPrefsRecordsRepository> _repoWith(Stats stats) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    '${SharedPrefsRecordsRepository.statsPrefix}klondike-draw1': jsonEncode(
      stats.toJson(),
    ),
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return SharedPrefsRecordsRepository(prefs);
}

Future<void> _pump(
  WidgetTester tester,
  Stats stats, {
  int? justWonTimeSeconds,
  int? justWonMoves,
}) async {
  final SharedPrefsRecordsRepository repo = await _repoWith(stats);
  await tester.pumpWidget(
    MaterialApp(
      home: RecordsScreen(
        repository: repo,
        variant: 'klondike-draw1',
        title: 'Klondike',
        justWonTimeSeconds: justWonTimeSeconds,
        justWonMoves: justWonMoves,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _textAt(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey<String>(key))).data!;

void main() {
  testWidgets('shows total wins and the best win badge', (
    WidgetTester tester,
  ) async {
    final DateTime day1 = DateTime(2026, 8, 20);
    Stats stats = const Stats();
    stats = stats.recordWin(timeSeconds: 200, moves: 90, timestamp: day1);
    stats = stats.recordWin(timeSeconds: 102, moves: 63, timestamp: day1);
    await _pump(tester, stats);

    expect(_textAt(tester, 'totalWins'), '2');
    expect(_textAt(tester, 'bestWinTime'), '01:42');
    expect(_textAt(tester, 'bestWinMoves'), '63 moves · best');
  });

  testWidgets('header title is just "Records", with the variant as a subtitle '
      '(so it fits on a narrow phone)', (WidgetTester tester) async {
    await _pump(
      tester,
      const Stats().recordWin(
        timeSeconds: 90,
        moves: 40,
        timestamp: DateTime(2026, 8, 1),
      ),
    );

    expect(find.text('Records'), findsOneWidget);
    expect(find.text('Klondike'), findsOneWidget);
    expect(find.text('Klondike — Records'), findsNothing);
  });

  testWidgets(
    'lists every best win in fastest-first order with time, moves and date',
    (WidgetTester tester) async {
      final DateTime day1 = DateTime(2026, 8, 20);
      final DateTime day2 = DateTime(2026, 8, 12);
      Stats stats = const Stats();
      stats = stats.recordWin(timeSeconds: 115, moves: 71, timestamp: day2);
      stats = stats.recordWin(timeSeconds: 102, moves: 63, timestamp: day1);
      await _pump(tester, stats);

      expect(_textAt(tester, 'rank-1'), '1');
      expect(_textAt(tester, 'time-1'), '01:42');
      expect(_textAt(tester, 'moves-1'), '63 moves');
      expect(_textAt(tester, 'date-1'), 'Aug 20');

      expect(_textAt(tester, 'rank-2'), '2');
      expect(_textAt(tester, 'time-2'), '01:55');
      expect(_textAt(tester, 'moves-2'), '71 moves');
      expect(_textAt(tester, 'date-2'), 'Aug 12');
    },
  );

  testWidgets('shows a placeholder before any game has been won', (
    WidgetTester tester,
  ) async {
    await _pump(tester, Stats.empty());

    expect(_textAt(tester, 'totalWins'), '0');
    expect(_textAt(tester, 'bestWinTime'), '—');
    expect(find.text('Win a game to start your leaderboard.'), findsOneWidget);
  });

  testWidgets(
    'a just-won game that places on the leaderboard shows the banner with '
    'a rank chip and tags its row NEW',
    (WidgetTester tester) async {
      final DateTime today = DateTime.now();
      Stats stats = const Stats();
      stats = stats.recordWin(timeSeconds: 102, moves: 63, timestamp: today);
      stats = stats.recordWin(timeSeconds: 115, moves: 71, timestamp: today);
      await _pump(tester, stats, justWonTimeSeconds: 115, justWonMoves: 71);

      expect(find.text('You won in 01:55 · 71 moves'), findsOneWidget);
      expect(find.text('#2 BEST'), findsOneWidget);
      expect(find.text('NEW'), findsOneWidget);
    },
  );

  testWidgets(
    'a just-won game outside the top 10 shows the banner without a rank '
    'chip and highlights nothing',
    (WidgetTester tester) async {
      final DateTime today = DateTime.now();
      final Stats stats = const Stats().recordWin(
        timeSeconds: 102,
        moves: 63,
        timestamp: today,
      );
      await _pump(tester, stats, justWonTimeSeconds: 400, justWonMoves: 140);

      expect(find.text('You won in 06:40 · 140 moves'), findsOneWidget);
      expect(find.textContaining('BEST'), findsNothing);
      expect(find.text('NEW'), findsNothing);
    },
  );

  testWidgets('content width is capped so it does not stretch on tablet', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const Stats().recordWin(
        timeSeconds: 90,
        moves: 40,
        timestamp: DateTime(2026, 8, 1),
      ),
    );

    expect(find.byType(MenuWidthLimit), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widget/records_screen_test.dart`
Expected: FAIL — `RecordsScreen` has no `justWonTimeSeconds`/
`justWonMoves` parameters yet, and none of the new keys/text exist.

- [ ] **Step 3: Write the minimal implementation**

Replace the entire contents of `lib/ui/records_screen.dart` with:

```dart
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
                      highlightedIndex: justWonRank == 0
                          ? -1
                          : justWonRank - 1,
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
                style: TextStyle(
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
              padding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
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
    Color(0xFFD6D6D6), // 2nd
    Color(0xFFCD7F32), // 3rd
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
              : BorderSide(
                  color: GamePalette.cardFace.withValues(alpha: 0.08),
                ),
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
              padding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 1,
              ),
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widget/records_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
dart format lib/ui/records_screen.dart test/widget/records_screen_test.dart
git add lib/ui/records_screen.dart test/widget/records_screen_test.dart
git commit -m "feat(records): redesign the records screen as a fastest-wins leaderboard"
```

---

## Task 6: Wire the just-won banner from `GameScreen`

**Files:**
- Modify: `lib/ui/game_screen.dart:150-198`
- Test: `test/widget/game_widget_test.dart:226-252`

**Interfaces:**
- Consumes: `RecordsScreen({..., int? justWonTimeSeconds, int? justWonMoves})` from Task 5; `GameWon.elapsed`/`GameWon.moves` (existing, `lib/presentation/bloc/game_bloc_state.dart:34`).
- Produces: nothing new — this is the last task, wiring the two prior
  pieces together end to end.

- [ ] **Step 1: Update the win-navigation test**

In `test/widget/game_widget_test.dart`, in the test titled `'winning
navigates to the records screen and records the win'`, replace:

```dart
    expect(find.byType(RecordsScreen), findsOneWidget);
    expect(find.text('Win rate'), findsOneWidget);
    final Stats stats = await repo.statsFor('klondike-draw1');
    expect(stats.gamesWon, 1);
```

with:

```dart
    expect(find.byType(RecordsScreen), findsOneWidget);
    expect(find.text('You won in 00:00 · 1 moves'), findsOneWidget);
    final Stats stats = await repo.statsFor('klondike-draw1');
    expect(stats.totalWins, 1);
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/widget/game_widget_test.dart`
Expected: FAIL — the win banner isn't shown yet because
`_navigateToRecords` doesn't pass `justWonTimeSeconds`/`justWonMoves`.

- [ ] **Step 3: Pass the win through to `RecordsScreen`**

In `lib/ui/game_screen.dart`, update `_navigateToRecords` to take the
`GameWon` state and forward its `elapsed`/`moves`:

```dart
  /// Pushes the records screen. A completed game has nothing left to resume,
  /// so leaving its records screen should land back on the main menu rather
  /// than reopen the finished board underneath — hence pushAndRemoveUntil
  /// down to the app root instead of a plain push.
  void _navigateToRecords(BuildContext context, GameBloc bloc, GameWon won) {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RecordsScreen(
          repository: bloc.repository,
          variant: bloc.variant,
          title: variantTitle(bloc.variant),
          justWonTimeSeconds: won.elapsed,
          justWonMoves: won.moves,
        ),
      ),
      (Route<void> route) => route.isFirst,
    );
  }
```

Then update its two call sites. In `_onGameWon`:

```dart
    if (MediaQuery.of(context).disableAnimations) {
      _navigateToRecords(context, context.read<GameBloc>(), won);
      return;
    }
```

In `_winOverlay`:

```dart
        onTap: _cascadeDismissible
            ? () =>
                  _navigateToRecords(context, context.read<GameBloc>(), _wonState!)
            : null,
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/widget/game_widget_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the full suite**

Run: `flutter analyze && flutter test`
Expected: `flutter analyze` reports no issues; the full test suite is
green.

- [ ] **Step 6: Format and commit**

```bash
dart format lib/ui/game_screen.dart test/widget/game_widget_test.dart
git add lib/ui/game_screen.dart test/widget/game_widget_test.dart
git commit -m "feat(records): show the just-won banner when reaching records from a win"
```

---

## Final verification (after Task 6)

- [ ] Run the full CI-equivalent sequence locally:

```bash
flutter pub get
flutter analyze
grep -rl "package:flutter" lib/core lib/persistence  # expect no output
flutter test
```

- [ ] Manually smoke-test on a device/emulator (`flutter run --flavor
      production`): win a game and confirm the banner + highlighted
      leaderboard row appear; open Records from the main menu (not via a
      win) and confirm no banner appears; win enough games to push
      something off the top 10 and confirm the 11th-fastest win drops off.
