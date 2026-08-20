import 'package:flutter/material.dart' hide Card;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solitaire/core/card.dart';
import 'package:solitaire/core/game_state.dart';
import 'package:solitaire/core/games/klondike.dart';
import 'package:solitaire/core/pile.dart';
import 'package:solitaire/persistence/records_repository.dart';
import 'package:solitaire/persistence/shared_prefs_records_repository.dart';
import 'package:solitaire/persistence/stats.dart';
import 'package:solitaire/presentation/bloc/game_bloc.dart';
import 'package:solitaire/presentation/card_view.dart';
import 'package:solitaire/ui/game_screen.dart';
import 'package:solitaire/ui/records_screen.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

List<Card> _run(Suit s, int maxRank) => <Card>[
  for (int r = aceRank; r <= maxRank; r++) _up(s, r),
];

GameState _board({
  List<Card> foundationClubs = const <Card>[],
  List<Card> foundationDiamonds = const <Card>[],
  List<Card> foundationHearts = const <Card>[],
  List<Card> foundationSpades = const <Card>[],
  List<Card> col6 = const <Card>[],
  List<Card> col7 = const <Card>[],
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
  );
}

Finder _cardFace(Suit s, int rank) => find.byWidgetPredicate(
  (Widget w) =>
      w is CardFace && w.card.suit == s && w.card.rank == rank && w.card.faceUp,
);

Future<SharedPrefsRecordsRepository> _repo() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return SharedPrefsRecordsRepository(prefs);
}

GameBloc _bloc(RecordsRepository repo, GameState state, {int seed = 5}) {
  return GameBloc(
    variant: 'klondike-draw1',
    repository: repo,
    seed: seed,
    state: state,
  );
}

Future<void> _pump(WidgetTester tester, GameBloc bloc) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<GameBloc>.value(
        value: bloc,
        child: const GameScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A single tap on a card that also handles double-tap is intentionally
/// deferred by Flutter's gesture arena until the double-tap window closes, so
/// the test must let that timer elapse before `onTap` fires.
Future<void> _tapCard(WidgetTester tester, Finder card) async {
  await tester.tap(card);
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pumpAndSettle();
}

Future<void> _dragTo(WidgetTester tester, Finder from, Finder to) async {
  final TestGesture gesture = await tester.startGesture(tester.getCenter(from));
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.moveTo(tester.getCenter(to));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('new deal renders the board and a fresh HUD', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    final GameBloc bloc = _bloc(
      repo,
      GameState.newGame(KlondikeRules(), seed: 42),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.text('0 moves'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
    // A fresh Klondike deal shows seven face-up tableau tops (plus more).
    expect(find.byType(CardFace), findsWidgets);
  });

  testWidgets('drag a card between tableau piles moves it', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    final GameBloc bloc = _bloc(
      repo,
      _board(
        col6: <Card>[_up(Suit.spades, 7)],
        col7: <Card>[_up(Suit.hearts, 8)],
      ),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc);
    expect(find.text('0 moves'), findsOneWidget);

    await _dragTo(tester, _cardFace(Suit.spades, 7), _cardFace(Suit.hearts, 8));

    expect(find.text('1 moves'), findsOneWidget);
    expect(bloc.state.state.pileAt(7).length, 2);
  });

  testWidgets('tap-to-move sends an Ace to its foundation', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    final GameBloc bloc = _bloc(
      repo,
      _board(col6: <Card>[_up(Suit.spades, aceRank)]),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc);
    await _tapCard(tester, _cardFace(Suit.spades, aceRank));

    expect(find.text('1 moves'), findsOneWidget);
    expect(
      bloc.state.state.pileAt(6).isEmpty,
      isTrue,
      reason: 'the ace left the tableau column',
    );
  });

  testWidgets('double-tap sends a card to its foundation', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    final GameBloc bloc = _bloc(
      repo,
      _board(
        foundationSpades: _run(Suit.spades, 2),
        col6: <Card>[_up(Suit.spades, 3)],
      ),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    final Finder card = _cardFace(Suit.spades, 3);
    await tester.tap(card);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(bloc.state.state.pileAt(5).length, 3);
    expect(find.text('1 moves'), findsOneWidget);
  });

  testWidgets('undo then redo walks the move counter back and forward', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    final GameBloc bloc = _bloc(
      repo,
      _board(
        col6: <Card>[_up(Suit.spades, 7)],
        col7: <Card>[_up(Suit.hearts, 8)],
      ),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc);
    await _dragTo(tester, _cardFace(Suit.spades, 7), _cardFace(Suit.hearts, 8));
    expect(find.text('1 moves'), findsOneWidget);

    await tester.tap(find.byTooltip('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('0 moves'), findsOneWidget);

    await tester.tap(find.byTooltip('Redo'));
    await tester.pumpAndSettle();
    expect(find.text('1 moves'), findsOneWidget);
  });

  testWidgets('winning navigates to the records screen and records the win', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    final GameBloc bloc = _bloc(
      repo,
      _board(
        foundationClubs: _run(Suit.clubs, kingRank),
        foundationDiamonds: _run(Suit.diamonds, kingRank),
        foundationHearts: _run(Suit.hearts, kingRank),
        foundationSpades: _run(Suit.spades, 12),
        col6: <Card>[_up(Suit.spades, kingRank)],
      ),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc);
    await _tapCard(tester, _cardFace(Suit.spades, kingRank));

    expect(find.byType(RecordsScreen), findsOneWidget);
    expect(find.text('Games won'), findsOneWidget);
    final Stats stats = await repo.statsFor('klondike-draw1');
    expect(stats.gamesWon, 1);
  });

  testWidgets('play screen shows a menu button and no AppBar', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    final GameBloc bloc = _bloc(
      repo,
      GameState.newGame(KlondikeRules(), seed: 42),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('Menu'), findsOneWidget);
    expect(find.text('0 moves'), findsOneWidget);
    expect(find.text('00:00'), findsOneWidget);
  });

  testWidgets('save then simulated relaunch resumes the in-progress game', (
    WidgetTester tester,
  ) async {
    final SharedPrefsRecordsRepository repo = await _repo();
    final GameBloc bloc = _bloc(
      repo,
      _board(
        col6: <Card>[_up(Suit.spades, 7)],
        col7: <Card>[_up(Suit.hearts, 8)],
      ),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc);
    await _dragTo(tester, _cardFace(Suit.spades, 7), _cardFace(Suit.hearts, 8));
    expect(find.text('1 moves'), findsOneWidget);

    // Simulate the OS pausing the app: GameScreen saves on paused.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    final SavedGame? saved = await repo.loadGame('klondike-draw1');
    expect(saved, isNotNull);
    expect(saved!.state.moveCount, 1);

    // "Relaunch": a fresh bloc built from the loaded save.
    final GameBloc resumed = _bloc(repo, saved.state, seed: saved.seed);
    addTearDown(resumed.close);
    await _pump(tester, resumed);

    expect(find.text('1 moves'), findsOneWidget);
    expect(resumed.state.state.pileAt(7).length, 2);
  });
}
