# Records Screen: Win Leaderboard (Remove Loss Tracking) — Design

**Date:** 2026-08-25
**Status:** Approved design, pre-implementation
**Framework:** Flutter (latest stable)
**Language:** Dart

## Purpose

Loss tracking (added in commit `70b3ad0`, 2026-08-24) doesn't hold up: a
"loss" only exists because the player walked away from an in-progress deal,
which isn't a meaningful defeat condition for solitaire and makes the
Records screen's win-rate framing feel wrong. This removes the loss concept
entirely and replaces it with a local leaderboard: every win is a data
point (timestamp + time + moves), the Records screen shows total wins plus
a table of the player's 10 fastest wins, and a game that was just won is
called out and located on that table.

## Scope

**In**
- Remove `Stats.recordLoss`, `gamesPlayed`, `winPercentage`,
  `currentStreak`, `longestStreak`, `bestTimeSeconds`, `fewestMoves`.
- New `WinRecord` value object (timestamp, time, moves) and a `Stats` shape
  built from it: an ever-incrementing `totalWins` counter plus a
  `bestWins` list capped at the 10 fastest.
- `RecordsRepository.recordResult(won: ...)` → `recordWin(...)` (no more
  `won` flag).
- Delete the three loss-recording call sites (`GameBloc`'s new-deal/restart
  abandon-tracking, `MainMenuScreen`'s swipe-delete tracking).
- Redesigned `RecordsScreen`: trophy hero (total wins + best win), a
  fastest-10 table with medal-tinted ranks, and — when navigated to
  straight from a win — a banner naming that win's time/moves, with its
  row tagged `NEW` if it placed in the table.
- Old (pre-change) stored `Stats` JSON is discarded on next read (falls
  back to `Stats.empty()`), per the "fresh start" decision — no migration
  code.

**Explicitly out**
- No migration/backfill of old `bestTimeSeconds`/`fewestMoves`/streak data
  into synthetic leaderboard entries.
- No cross-device or online leaderboard — still local, still behind
  `RecordsRepository`, still `shared_preferences`-backed.
- No change to how or when a win is detected (`GameBloc._emitAfterMove`,
  `_onAutoSolveRequested`) beyond the method rename — the win path's
  control flow is unchanged.
- No sort-order toggle in the UI (fastest-time only, per the approved
  design) — a future "sort by moves / most recent" control is not part of
  this change.

## Architecture

```
persistence/  stats.dart                      (WinRecord + rewritten Stats)
              records_repository.dart          (recordResult → recordWin)
              shared_prefs_records_repository.dart (rename, pass DateTime.now())
presentation/ bloc/game_bloc.dart              (drop loss call sites, rename)
ui/           main_menu_screen.dart            (drop loss call site)
              game_screen.dart                 (pass elapsed/moves to RecordsScreen)
              records_screen.dart              (new layout + win banner)
```

`core/` is untouched — this is entirely a `persistence/` + `ui/` change.
`persistence/` keeps zero Flutter imports throughout.

## Component 1 — `persistence/stats.dart`

```dart
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
}

/// Per-variant records: a running win count plus a capped leaderboard of the
/// fastest wins. Immutable value object — [recordWin] returns an updated
/// copy, keeping the leaderboard math (ranking, capping) testable in
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

  static const int maxBestWins = 10;

  final int totalWins;

  /// The fastest wins so far, sorted ascending by time (ties broken by fewer
  /// moves), capped at [maxBestWins]. `bestWins.first` is the best win ever;
  /// the list may be empty or shorter than the cap before enough wins exist.
  final List<WinRecord> bestWins;

  /// A copy reflecting one more win: increments [totalWins] unconditionally,
  /// and inserts [timestamp]/[timeSeconds]/[moves] into [bestWins] if it
  /// ranks among the fastest [maxBestWins] — a win that doesn't crack the
  /// leaderboard still counts toward the total.
  Stats recordWin({
    required int timeSeconds,
    required int moves,
    required DateTime timestamp,
  }) {
    if (timeSeconds < 0 || moves < 0) {
      throw ArgumentError('timeSeconds and moves must be non-negative');
    }
    final List<WinRecord> updated = <WinRecord>[
      ...bestWins,
      WinRecord(timestamp: timestamp, timeSeconds: timeSeconds, moves: moves),
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
}
```

`timestamp` is a required parameter rather than `DateTime.now()` inside the
method — the same reasoning as the seeded `Random` injected into `Deck`:
`Stats` stays a pure value object, so ranking/capping logic is testable
with exact, reproducible timestamps. The repository (below) is the impure
caller that supplies the real clock.

## Component 2 — Repository interface

`records_repository.dart`:

```dart
/// Records a win against [variant]'s stats.
Future<void> recordWin({
  required String variant,
  required int timeSeconds,
  required int moves,
});
```

replaces `recordResult({required bool won, ...})`. `statsFor`,
`saveGame`/`loadGame`/`hasSave`/`clearSave`/`loadAllSaves` are unchanged.

`shared_prefs_records_repository.dart`'s implementation calls
`current.recordWin(timeSeconds: ..., moves: ..., timestamp: DateTime.now())`
and persists the result exactly as today (same `stats:<variant>` key, same
JSON-blob shape swap). `Stats.fromJson` throwing on the old shape (missing
`totalWins`/`bestWins` keys) is already caught by `statsFor`'s existing
try/catch and degrades to `Stats.empty()` — no explicit migration branch
needed.

## Component 3 — Removing loss tracking from callers

- `GameBloc`: delete `_recordAbandonedLossIfAny` and its two call sites (in
  `_onNewDealRequested` and `_onRestartDealRequested`). The two win call
  sites (`_onAutoSolveRequested`, `_emitAfterMove`) change
  `repository.recordResult(variant: ..., won: true, timeSeconds: ..., moves: ...)`
  to `repository.recordWin(variant: ..., timeSeconds: ..., moves: ...)`.
- `MainMenuScreen._deleteSave`: delete the
  `if (saved.state.moveCount > 0) { recordResult(won: false, ...) }` block;
  the method becomes just the synchronous list removal plus `clearSave`.

## Component 4 — `ui/records_screen.dart`

Layout (approved: "compact table" direction from the visual mockup):

- `FeltHeader` unchanged (title/subtitle/back).
- **Win banner** (new, conditional) — shown only when `justWonTimeSeconds`
  and `justWonMoves` are both non-null: a gold-bordered strip reading
  "🎉 You won in `mm:ss` · N moves", plus a "#K BEST" chip when that
  win's `(timeSeconds, moves)` pair is found in `bestWins` (K = its
  1-based index there).
- **Hero row** (replaces `_WinRateHero`): trophy icon, `totalWins` as the
  big number with "Total wins" label, and — right-aligned — the best win's
  time + moves (`bestWins.first`, or `—` when `bestWins` is empty).
- **Leaderboard table**: one row per `bestWins` entry — rank (gold/silver/
  bronze tint for 1–3, plain otherwise), time, moves, date
  (`MM/dd`-style short date; "Today" for the current calendar day). The row
  matching the just-won game (when present) gets a gold left-edge
  highlight and a `NEW` tag next to its rank.
- **Empty state** (`totalWins == 0`): hero shows "0" / best "—"; the table
  area is replaced by a centered placeholder — "Win a game to start your
  leaderboard."

`RecordsScreen` constructor gains two optional fields:

```dart
const RecordsScreen({
  required this.repository,
  required this.variant,
  required this.title,
  this.justWonTimeSeconds,
  this.justWonMoves,
  super.key,
});

final int? justWonTimeSeconds;
final int? justWonMoves;
```

Both null except when pushed from a win. `GameScreen._navigateToRecords`
is the only call site that sets them, from the `GameWon` state it already
holds (`won.elapsed`, `won.moves`); `GameOptionsScreen`'s existing
navigation to `RecordsScreen` (opened from the main menu, not from a win)
passes neither, so it defaults to no banner. `_WinRateHero`, `_LegendRow`
are deleted; `_StatTile` is dropped in favor of the hero row + table
above (no other screen references it).

## Testing (TDD: RED → GREEN → REFACTOR)

**Unit — `test/unit/`**
- `Stats.recordWin` increments `totalWins` on every call, including when
  the win doesn't crack `bestWins`.
- `Stats.recordWin` inserts into `bestWins` in ascending time order, breaks
  ties by fewer moves, and caps the list at `Stats.maxBestWins` (an 11th,
  slower win doesn't grow the list; an 11th *faster* win evicts the
  current slowest).
- `WinRecord`/`Stats` `toJson` → `fromJson` round-trips equal to the
  original (protects save/resume of records data).
- `Stats.fromJson` on the old pre-change shape (no `totalWins`/`bestWins`
  keys) throws, and `SharedPrefsRecordsRepository.statsFor` degrades that
  to `Stats.empty()` (exercises the existing try/catch with the new shape).
- `SharedPrefsRecordsRepository.recordWin` persists a `Stats` whose
  `bestWins` contains the recorded win, and `statsFor` reads it back.
- `GameBloc`: a new-deal/restart on an in-progress game (`moveCount > 0`)
  no longer calls anything loss-shaped — `repository` interactions on
  discard are limited to `clearSave` (verify no stray `recordWin`/removed
  method call).
- `GameBloc`: winning (manual or `AutoSolveRequested`) calls
  `repository.recordWin(variant, timeSeconds, moves)` and clears the save,
  same as the current win-path tests but renamed.

**Widget (happy path) — `test/widget/`**
- `RecordsScreen` with populated `Stats` renders total wins, the best-win
  badge, and a table row per `bestWins` entry in order.
- `RecordsScreen` with `Stats.empty()` renders the "0 total wins" /
  placeholder empty state, no table rows.
- `RecordsScreen` constructed with `justWonTimeSeconds`/`justWonMoves`
  matching a `bestWins` entry shows the win banner with the "#K BEST" chip
  and highlights that row with the `NEW` tag.
- `RecordsScreen` constructed with `justWonTimeSeconds`/`justWonMoves` that
  do **not** appear in `bestWins` (a win outside the top 10) shows the
  banner without a rank chip and highlights no row.
- Winning a game end-to-end (`GameScreen` → tap to dismiss the cascade)
  navigates to `RecordsScreen` with the just-won banner visible — this is
  the flow currently covered by the win → records navigation test; it
  gains the banner assertion.

## Risks & mitigations

- **Tie collisions in the "which row is the just-won one" match** — two
  distinct wins with identical `(timeSeconds, moves)` would both read as a
  match. Accepted: harmless in a casual local leaderboard (at worst the
  highlight lands on the tied row that sorted first), not worth threading
  a synthetic id through the win path to prevent.
- **`bestWins` growing unbounded in storage** — prevented structurally by
  `maxBestWins` capping in `recordWin` itself, not just at render time.
- **Old installs' stored stats disappearing silently** — accepted per the
  "fresh start" decision; `totalWins` simply starts back at 0 for existing
  players. No corruption risk since it's a clean `Stats.empty()` fallback,
  identical to how corrupt JSON is already handled today.

## Pre-commit checklist (per CLAUDE.md)

- [ ] Tests written first, drove the change (RED → GREEN → REFACTOR).
- [ ] `flutter analyze` and `flutter test` pass; `dart format` clean.
- [ ] `persistence/` still has zero `package:flutter` imports.
- [ ] No rules leaked into widgets; ranking/capping logic lives in `Stats`,
      not in `RecordsScreen`.
- [ ] New happy-path interactions (empty state, win banner + highlighted
      row) have widget tests.
