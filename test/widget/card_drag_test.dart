import 'package:flutter/material.dart' hide Card;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solitaire/core/card.dart';
import 'package:solitaire/core/game_state.dart';
import 'package:solitaire/core/pile.dart';
import 'package:solitaire/persistence/records_repository.dart';
import 'package:solitaire/persistence/shared_prefs_records_repository.dart';
import 'package:solitaire/presentation/bloc/game_bloc.dart';
import 'package:solitaire/presentation/card_view.dart';
import 'package:solitaire/ui/game_screen.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

Finder _cardFace(Suit s, int rank) => find.byWidgetPredicate(
  (Widget w) =>
      w is CardFace && w.card.suit == s && w.card.rank == rank && w.card.faceUp,
);

/// Counts the dimmed drag placeholders currently in the tree (cards rendered at
/// 0.3 opacity because they belong to a stack being dragged).
Finder _placeholders() => find.byWidgetPredicate(
  (Widget w) => w is Opacity && (w.opacity - 0.3).abs() < 1e-3,
);

Future<SharedPrefsRecordsRepository> _repo() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return SharedPrefsRecordsRepository(prefs);
}

GameBloc _bloc(RecordsRepository repo, GameState state) {
  return GameBloc(
    variant: 'klondike-draw1',
    repository: repo,
    seed: 5,
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

GameState _game(List<List<Card>> tableau) {
  return GameState(
    piles: <Pile>[
      Pile(kind: PileKind.stock),
      Pile(kind: PileKind.waste),
      Pile(kind: PileKind.foundation),
      Pile(kind: PileKind.foundation),
      Pile(kind: PileKind.foundation),
      Pile(kind: PileKind.foundation),
      for (final List<Card> col in tableau)
        Pile(kind: PileKind.tableau, cards: col),
      for (int i = tableau.length; i < 7; i++) Pile(kind: PileKind.tableau),
    ],
  );
}

/// A grab point near the top edge of [card], so a fanned (overlapped) card is
/// picked up rather than the one stacked below it.
Offset _grab(WidgetTester tester, Finder card) {
  final Rect r = tester.getRect(card);
  return Offset(r.center.dx, r.top + 4);
}

void main() {
  testWidgets('dragging a mid-stack card dims the whole moving sub-stack', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    // A valid descending run: K(black) Q(red) J(black).
    final GameBloc bloc = _bloc(
      repo,
      _game(<List<Card>>[
        <Card>[
          _up(Suit.spades, kingRank),
          _up(Suit.hearts, 12),
          _up(Suit.spades, 11),
        ],
      ]),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc);
    expect(_placeholders(), findsNothing);

    // Grab the queen (index 1); the jack below it (index 2) rides along.
    final TestGesture gesture = await tester.startGesture(
      _grab(tester, _cardFace(Suit.hearts, 12)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();

    // Both the grabbed queen and the trailing jack are dimmed in place; the
    // king above them is not.
    expect(_placeholders(), findsNWidgets(2));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(_placeholders(), findsNothing);
  });

  testWidgets('a second finger cannot start a drag while one is in progress', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    final GameBloc bloc = _bloc(
      repo,
      _game(<List<Card>>[
        <Card>[_up(Suit.spades, 7)], // A: 7 black -> 8 red
        <Card>[_up(Suit.hearts, 8)],
        <Card>[_up(Suit.clubs, 6)], // B: 6 black -> 7 red
        <Card>[_up(Suit.diamonds, 7)],
      ]),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    // Start dragging A and hold it in the air over its target.
    final TestGesture a = await tester.startGesture(
      tester.getCenter(_cardFace(Suit.spades, 7)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await a.moveTo(tester.getCenter(_cardFace(Suit.hearts, 8)));
    await tester.pump();

    // With A still down, run a full, otherwise-valid drag of B and release it.
    final TestGesture b = await tester.startGesture(
      tester.getCenter(_cardFace(Suit.clubs, 6)),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await b.moveTo(tester.getCenter(_cardFace(Suit.diamonds, 7)));
    await tester.pump();
    await b.up();
    await tester.pumpAndSettle();

    // B's move was rejected: the six is still on its own column, no move logged.
    expect(bloc.state.state.pileAt(8).length, 1);
    expect(find.text('0 moves'), findsOneWidget);

    // A still completes normally once released.
    await a.up();
    await tester.pumpAndSettle();
    expect(bloc.state.state.pileAt(7).length, 2);
    expect(find.text('1 moves'), findsOneWidget);
  });
}
