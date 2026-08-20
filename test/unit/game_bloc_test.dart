import 'dart:math';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/games/klondike.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/stats.dart';
import 'package:open_patience/presentation/bloc/game_bloc.dart';
import 'package:open_patience/presentation/bloc/game_bloc_state.dart';
import 'package:open_patience/presentation/bloc/game_event.dart';

/// Records every call so tests can assert the bloc drives persistence.
class _FakeRepo implements RecordsRepository {
  final List<String> calls = <String>[];
  GameState? savedState;

  @override
  Future<void> recordResult({
    required String variant,
    required bool won,
    required int timeSeconds,
    required int moves,
  }) async {
    calls.add('record:$variant:$won:$timeSeconds:$moves');
  }

  @override
  Future<Stats> statsFor(String variant) async => const Stats();

  @override
  Future<void> saveGame({
    required String variant,
    required int seed,
    required GameState state,
  }) async {
    calls.add('save:$variant:$seed');
    savedState = state;
  }

  @override
  Future<SavedGame?> loadGame(String variant) async => null;

  @override
  Future<bool> hasSave(String variant) async => false;

  @override
  Future<void> clearSave(String variant) async {
    calls.add('clear:$variant');
  }
}

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

List<Card> _run(Suit s, int maxRank) => <Card>[
  for (int r = aceRank; r <= maxRank; r++) _up(s, r),
];

/// A 13-pile Klondike board with the given tableau columns 6 and 7 and the
/// four foundations at [f0]..[f3] cards.
GameState _klondikeBoard({
  List<Card> foundationSpades = const <Card>[],
  List<Card> foundationHearts = const <Card>[],
  List<Card> foundationClubs = const <Card>[],
  List<Card> foundationDiamonds = const <Card>[],
  List<Card> col6 = const <Card>[],
  List<Card> col7 = const <Card>[],
  int elapsedSeconds = 0,
}) {
  return GameState(
    piles: <Pile>[
      Pile(kind: PileKind.stock),
      Pile(kind: PileKind.waste),
      Pile(kind: PileKind.foundation, cards: foundationClubs),
      Pile(kind: PileKind.foundation, cards: foundationDiamonds),
      Pile(kind: PileKind.foundation, cards: foundationHearts),
      Pile(kind: PileKind.foundation, cards: foundationSpades),
      Pile(kind: PileKind.tableau, cards: col6),
      Pile(kind: PileKind.tableau, cards: col7),
      Pile(kind: PileKind.tableau),
      Pile(kind: PileKind.tableau),
      Pile(kind: PileKind.tableau),
      Pile(kind: PileKind.tableau),
      Pile(kind: PileKind.tableau),
    ],
    elapsedSeconds: elapsedSeconds,
  );
}

GameBloc _bloc(_FakeRepo repo, GameState state, {int seed = 7}) {
  return GameBloc(
    variant: 'klondike-draw1',
    repository: repo,
    seed: seed,
    state: state,
    random: Random(1),
  );
}

void main() {
  const int stock = KlondikeRules.stockIndex;
  const int waste = KlondikeRules.wasteIndex;
  const int spadesFoundation = 5;

  group('GameBloc initial state', () {
    test('exposes an in-progress snapshot of the deal it was given', () {
      final _FakeRepo repo = _FakeRepo();
      final GameState state = GameState.newGame(KlondikeRules(), seed: 99);
      final GameBloc bloc = _bloc(repo, state);
      addTearDown(bloc.close);
      expect(bloc.state, isA<GameInProgress>());
      expect(bloc.state.state.moveCount, 0);
    });
  });

  group('MoveRequested', () {
    blocTest<GameBloc, GameBlocState>(
      'applies a legal tableau move and increments the move count',
      build: () => _bloc(
        _FakeRepo(),
        _klondikeBoard(
          col6: <Card>[_up(Suit.spades, 7)],
          col7: <Card>[_up(Suit.hearts, 8)],
        ),
      ),
      act: (GameBloc bloc) =>
          bloc.add(const MoveRequested(fromPile: 6, toPile: 7, cardIndex: 0)),
      expect: () => <Matcher>[
        isA<GameInProgress>()
            .having((GameBlocState s) => s.state.moveCount, 'moveCount', 1)
            .having((GameBlocState s) => s.state.pileAt(7).length, 'col7', 2),
      ],
    );

    blocTest<GameBloc, GameBlocState>(
      'an illegal move is a silent no-op (no emission)',
      build: () => _bloc(
        _FakeRepo(),
        _klondikeBoard(
          col6: <Card>[_up(Suit.spades, 7)],
          col7: <Card>[_up(Suit.clubs, 8)],
        ),
      ),
      act: (GameBloc bloc) =>
          bloc.add(const MoveRequested(fromPile: 6, toPile: 7, cardIndex: 0)),
      expect: () => <Matcher>[],
    );
  });

  group('TapMoveRequested', () {
    blocTest<GameBloc, GameBlocState>(
      'a tap on the stock draws a card onto the waste',
      build: () =>
          _bloc(_FakeRepo(), GameState.newGame(KlondikeRules(), seed: 3)),
      act: (GameBloc bloc) => bloc.add(const TapMoveRequested(fromPile: stock)),
      expect: () => <Matcher>[
        isA<GameInProgress>().having(
          (GameBlocState s) => s.state.pileAt(waste).length,
          'waste length',
          1,
        ),
      ],
    );

    blocTest<GameBloc, GameBlocState>(
      'tapping an Ace sends it to its foundation',
      build: () => _bloc(
        _FakeRepo(),
        _klondikeBoard(col6: <Card>[_up(Suit.spades, aceRank)]),
      ),
      act: (GameBloc bloc) => bloc.add(const TapMoveRequested(fromPile: 6)),
      expect: () => <Matcher>[
        isA<GameInProgress>().having(
          (GameBlocState s) => s.state.piles
              .where((Pile p) => p.kind == PileKind.foundation)
              .any((Pile p) => p.topCard == _up(Suit.spades, aceRank)),
          'ace on a foundation',
          isTrue,
        ),
      ],
    );
  });

  group('DoubleTapRequested', () {
    blocTest<GameBloc, GameBlocState>(
      'double-tap sends the card to a foundation when legal',
      build: () => _bloc(
        _FakeRepo(),
        _klondikeBoard(
          foundationSpades: _run(Suit.spades, 2),
          col6: <Card>[_up(Suit.spades, 3)],
        ),
      ),
      act: (GameBloc bloc) => bloc.add(const DoubleTapRequested(fromPile: 6)),
      expect: () => <Matcher>[
        isA<GameInProgress>().having(
          (GameBlocState s) => s.state.pileAt(spadesFoundation).length,
          'spades foundation length',
          3,
        ),
      ],
    );
  });

  group('Undo / Redo', () {
    blocTest<GameBloc, GameBlocState>(
      'undo restores the exact prior board; redo re-applies',
      build: () => _bloc(
        _FakeRepo(),
        _klondikeBoard(
          col6: <Card>[_up(Suit.spades, 7)],
          col7: <Card>[_up(Suit.hearts, 8)],
        ),
      ),
      act: (GameBloc bloc) => bloc
        ..add(const MoveRequested(fromPile: 6, toPile: 7, cardIndex: 0))
        ..add(const UndoRequested())
        ..add(const RedoRequested()),
      expect: () => <Matcher>[
        isA<GameInProgress>().having(
          (GameBlocState s) => s.state.moveCount,
          'after move',
          1,
        ),
        isA<GameInProgress>().having(
          (GameBlocState s) => s.state.moveCount,
          'after undo',
          0,
        ),
        isA<GameInProgress>().having(
          (GameBlocState s) => s.state.moveCount,
          'after redo',
          1,
        ),
      ],
    );
  });

  group('Tick', () {
    blocTest<GameBloc, GameBlocState>(
      'advances the elapsed timer by one second',
      build: () => _bloc(_FakeRepo(), _klondikeBoard(elapsedSeconds: 41)),
      act: (GameBloc bloc) => bloc.add(const Tick()),
      expect: () => <Matcher>[
        isA<GameInProgress>().having(
          (GameBlocState s) => s.state.elapsedSeconds,
          'elapsed',
          42,
        ),
      ],
    );
  });

  group('winning', () {
    late _FakeRepo repo;
    blocTest<GameBloc, GameBlocState>(
      'a winning move records the result, clears the save and emits GameWon',
      build: () {
        repo = _FakeRepo();
        return _bloc(
          repo,
          _klondikeBoard(
            foundationClubs: _run(Suit.clubs, kingRank),
            foundationDiamonds: _run(Suit.diamonds, kingRank),
            foundationHearts: _run(Suit.hearts, kingRank),
            foundationSpades: _run(Suit.spades, 12),
            col6: <Card>[_up(Suit.spades, kingRank)],
            elapsedSeconds: 123,
          ),
        );
      },
      act: (GameBloc bloc) => bloc.add(
        const MoveRequested(
          fromPile: 6,
          toPile: spadesFoundation,
          cardIndex: 0,
        ),
      ),
      expect: () => <Matcher>[
        isA<GameWon>()
            .having((GameBlocState s) => (s as GameWon).moves, 'moves', 1)
            .having(
              (GameBlocState s) => (s as GameWon).elapsed,
              'elapsed',
              123,
            ),
      ],
      verify: (_) {
        expect(repo.calls, contains('record:klondike-draw1:true:123:1'));
        expect(repo.calls, contains('clear:klondike-draw1'));
      },
    );
  });

  group('SaveRequested', () {
    late _FakeRepo repo;
    blocTest<GameBloc, GameBlocState>(
      'persists the current game without changing state',
      build: () {
        repo = _FakeRepo();
        return _bloc(repo, _klondikeBoard(elapsedSeconds: 5), seed: 55);
      },
      act: (GameBloc bloc) => bloc.add(const SaveRequested()),
      expect: () => <Matcher>[],
      verify: (_) {
        expect(repo.calls, contains('save:klondike-draw1:55'));
        expect(repo.savedState!.elapsedSeconds, 5);
      },
    );
  });

  group('NewDealRequested / RestartDealRequested', () {
    blocTest<GameBloc, GameBlocState>(
      'a seeded new deal emits a fresh in-progress game',
      build: () => _bloc(_FakeRepo(), _klondikeBoard(elapsedSeconds: 99)),
      act: (GameBloc bloc) => bloc.add(const NewDealRequested(seed: 7)),
      expect: () => <Matcher>[
        isA<GameInProgress>()
            .having((GameBlocState s) => s.state.moveCount, 'moveCount', 0)
            .having((GameBlocState s) => s.state.elapsedSeconds, 'elapsed', 0)
            .having(
              (GameBlocState s) => s.state.pileAt(stock).length,
              'stock',
              24,
            ),
      ],
    );

    test('restart re-deals the same seed', () {
      final _FakeRepo repo = _FakeRepo();
      final GameBloc bloc = _bloc(
        repo,
        GameState.newGame(KlondikeRules(), seed: 44),
        seed: 44,
      );
      addTearDown(bloc.close);
      final GameState expected = GameState.newGame(KlondikeRules(), seed: 44);
      bloc.add(const RestartDealRequested());
      expectLater(
        bloc.stream,
        emits(
          isA<GameInProgress>().having(
            (GameBlocState s) => s.state.piles,
            'piles',
            expected.piles,
          ),
        ),
      );
    });
  });
}
