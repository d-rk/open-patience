import 'package:flutter/material.dart' hide Card;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/presentation/bloc/game_bloc.dart';
import 'package:open_patience/presentation/card_view.dart';
import 'package:open_patience/ui/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

Finder _cardFace(Suit s, int rank) => find.byWidgetPredicate(
  (Widget w) =>
      w is CardFace && w.card.suit == s && w.card.rank == rank && w.card.faceUp,
);

/// Counts any dimmed drag "ghost" left behind in a pile (a card rendered at
/// 0.3 opacity because it belongs to a stack being dragged). Dragging leaves no
/// such ghost anymore, so this should always find nothing.
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
  testWidgets('the dragged card centers on the finger, not the grab point', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    final GameBloc bloc = _bloc(
      repo,
      _game(<List<Card>>[
        <Card>[_up(Suit.spades, 7)],
      ]),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc);

    // Grab the card near its top edge (well off-center), then drag.
    final Finder card = _cardFace(Suit.spades, 7);
    final Offset finger = _grab(tester, card);
    final TestGesture gesture = await tester.startGesture(finger);
    await tester.pump(const Duration(milliseconds: 200));
    final Offset here = finger + const Offset(0, -120);
    await gesture.moveTo(here);
    await tester.pump();

    // During the drag the only copy of the card is the floating feedback that
    // follows the finger; the source slot is left empty (no ghost). The
    // feedback's center must sit on the finger — so hit-testing (always at the
    // finger) effectively targets the card's center.
    final Iterable<Element> faces = card.evaluate();
    expect(faces.length, 1);
    final double dist =
        (tester.getRect(find.byWidget(faces.single.widget)).center - here)
            .distance;
    expect(dist, lessThan(1.0));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('dragging a mid-stack card leaves no ghost behind in the pile', (
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

    // No dimmed ghost is left behind. The grabbed queen and the trailing jack
    // ride along in the floating feedback and appear exactly once each — not
    // duplicated in place — while the king above them stays put.
    expect(_placeholders(), findsNothing);
    expect(_cardFace(Suit.hearts, 12), findsOneWidget);
    expect(_cardFace(Suit.spades, 11), findsOneWidget);
    expect(_cardFace(Suit.spades, kingRank), findsOneWidget);

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
