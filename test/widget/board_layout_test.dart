import 'package:flutter/material.dart' hide Card;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/presentation/bloc/game_bloc.dart';
import 'package:open_patience/presentation/board.dart';
import 'package:open_patience/presentation/card_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

Finder _cardFace(Suit s, int rank) => find.byWidgetPredicate(
  (Widget w) =>
      w is CardFace && w.card.suit == s && w.card.rank == rank && w.card.faceUp,
);

/// A board with a distinctive foundation card, a distinctive tableau card, and
/// a long tableau fan (to stress vertical fitting in landscape).
GameState _board() {
  return GameState(
    piles: <Pile>[
      Pile(kind: PileKind.stock),
      Pile(kind: PileKind.waste),
      Pile(kind: PileKind.foundation, cards: <Card>[_up(Suit.clubs, aceRank)]),
      Pile(kind: PileKind.foundation),
      Pile(kind: PileKind.foundation),
      Pile(kind: PileKind.foundation),
      Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, 5)]),
      Pile(
        kind: PileKind.tableau,
        cards: <Card>[for (int r = kingRank; r >= 1; r--) _up(Suit.hearts, r)],
      ),
      Pile(kind: PileKind.tableau),
      Pile(kind: PileKind.tableau),
      Pile(kind: PileKind.tableau),
      Pile(kind: PileKind.tableau),
      // A distinctive card in the *last* tableau column, to locate the
      // tableau's right edge.
      Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.diamonds, kingRank)]),
    ],
  );
}

/// A FreeCell board with a distinctive card parked in the first free cell and a
/// distinctive ace on the first foundation, to locate the two side sub-columns.
GameState _freecellBoard() {
  return GameState(
    piles: <Pile>[
      Pile(kind: PileKind.freecell, cards: <Card>[_up(Suit.spades, 7)]),
      Pile(kind: PileKind.freecell),
      Pile(kind: PileKind.freecell),
      Pile(kind: PileKind.freecell),
      Pile(kind: PileKind.foundation, cards: <Card>[_up(Suit.clubs, aceRank)]),
      Pile(kind: PileKind.foundation),
      Pile(kind: PileKind.foundation),
      Pile(kind: PileKind.foundation),
      for (int i = 0; i < 8; i++) Pile(kind: PileKind.tableau),
    ],
  );
}

/// A 6-cell (relaxed) FreeCell board: 6 free cells + 4 foundations + 8 tableau.
/// A distinctive card parks in the first free cell and a distinctive ace sits on
/// the first foundation, to locate the two top zones.
GameState _freecell6Board() {
  return GameState(
    piles: <Pile>[
      Pile(kind: PileKind.freecell, cards: <Card>[_up(Suit.spades, 7)]),
      for (int i = 0; i < 5; i++) Pile(kind: PileKind.freecell),
      Pile(kind: PileKind.foundation, cards: <Card>[_up(Suit.clubs, aceRank)]),
      Pile(kind: PileKind.foundation),
      Pile(kind: PileKind.foundation),
      Pile(kind: PileKind.foundation),
      for (int i = 0; i < 8; i++) Pile(kind: PileKind.tableau),
    ],
  );
}

Future<RecordsRepository> _repo() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPrefsRecordsRepository(await SharedPreferences.getInstance());
}

Future<GameBloc> _pumpBoard(
  WidgetTester tester,
  Size size, {
  GameState? state,
}) async {
  final RecordsRepository repo = await _repo();
  final GameBloc bloc = GameBloc(
    variant: 'klondike-draw1',
    repository: repo,
    seed: 1,
    state: state ?? _board(),
  );
  addTearDown(bloc.close);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BlocProvider<GameBloc>.value(value: bloc, child: const Board()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return bloc;
}

void main() {
  testWidgets('phone landscape fits without overflow and stacks the top row', (
    WidgetTester tester,
  ) async {
    await _pumpBoard(tester, const Size(800, 360));

    expect(tester.takeException(), isNull);
    expect(find.byType(CardFace), findsWidgets);
    // Stacked arrangement: the foundation card sits above the tableau card.
    expect(
      tester.getCenter(_cardFace(Suit.clubs, aceRank)).dy,
      lessThan(tester.getCenter(_cardFace(Suit.spades, 5)).dy),
    );
    // Fit-to-height: the deepest card of the longest fan stays on screen.
    expect(
      tester.getRect(_cardFace(Suit.hearts, aceRank)).bottom,
      lessThanOrEqualTo(360 + 0.5),
    );
  });

  testWidgets('phone landscape: tap-to-move still reaches the foundation', (
    WidgetTester tester,
  ) async {
    final GameState oneAce = GameState(
      piles: <Pile>[
        Pile(kind: PileKind.stock),
        Pile(kind: PileKind.waste),
        Pile(kind: PileKind.foundation),
        Pile(kind: PileKind.foundation),
        Pile(kind: PileKind.foundation),
        Pile(kind: PileKind.foundation),
        Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, aceRank)]),
        for (int i = 0; i < 6; i++) Pile(kind: PileKind.tableau),
      ],
    );
    final GameBloc bloc = await _pumpBoard(
      tester,
      const Size(800, 360),
      state: oneAce,
    );

    await tester.tap(_cardFace(Suit.spades, aceRank));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(bloc.state.state.pileAt(6).isEmpty, isTrue);
  });

  testWidgets('tablet landscape puts the foundations right of the tableau', (
    WidgetTester tester,
  ) async {
    await _pumpBoard(tester, const Size(1200, 800));

    expect(tester.takeException(), isNull);
    // Side-column arrangement: the foundation sits to the right of even the
    // last (right-most) tableau column — impossible in the top-row layout,
    // where the tableau spans the full width.
    expect(
      tester.getCenter(_cardFace(Suit.clubs, aceRank)).dx,
      greaterThan(tester.getCenter(_cardFace(Suit.diamonds, kingRank)).dx),
    );
  });

  testWidgets(
    'freecell tablet landscape: free cells sit left of the foundations',
    (WidgetTester tester) async {
      await _pumpBoard(tester, const Size(1200, 800), state: _freecellBoard());

      expect(tester.takeException(), isNull);
      // Two clean sub-columns: parking (free cells) is the left column, the
      // foundations (aces) are the right column, on the board's right edge.
      expect(
        tester.getCenter(_cardFace(Suit.spades, 7)).dx,
        lessThan(tester.getCenter(_cardFace(Suit.clubs, aceRank)).dx),
      );
    },
  );

  testWidgets('portrait keeps the foundations above the tableau', (
    WidgetTester tester,
  ) async {
    await _pumpBoard(tester, const Size(400, 800));

    expect(tester.takeException(), isNull);
    expect(
      tester.getCenter(_cardFace(Suit.clubs, aceRank)).dy,
      lessThan(tester.getCenter(_cardFace(Suit.spades, 5)).dy),
    );
  });

  testWidgets('classic 4-cell FreeCell portrait fits without overflow', (
    WidgetTester tester,
  ) async {
    // Regression: the 4+4 single-row top used to overflow ~6px in portrait.
    await _pumpBoard(tester, const Size(400, 800), state: _freecellBoard());

    expect(tester.takeException(), isNull);
    expect(find.byType(CardFace), findsWidgets);
  });

  testWidgets(
    '6-cell FreeCell portrait fits and stacks foundations over free cells',
    (WidgetTester tester) async {
      await _pumpBoard(tester, const Size(400, 800), state: _freecell6Board());

      // The 6+4 top no longer overflows the row.
      expect(tester.takeException(), isNull);
      // Two-row top area: the foundation ace sits above the parked free cell.
      expect(
        tester.getCenter(_cardFace(Suit.clubs, aceRank)).dy,
        lessThan(tester.getCenter(_cardFace(Suit.spades, 7)).dy),
      );
    },
  );

  testWidgets(
    '6-cell FreeCell phone landscape keeps parking beside the foundations',
    (WidgetTester tester) async {
      await _pumpBoard(tester, const Size(800, 360), state: _freecell6Board());

      expect(tester.takeException(), isNull);
      // Landscape has the width to keep the 6+4 top on a single row: parking
      // (free cells) on the left, foundations on the right — same row, not
      // stacked as in portrait.
      final Offset parked = tester.getCenter(_cardFace(Suit.spades, 7));
      final Offset ace = tester.getCenter(_cardFace(Suit.clubs, aceRank));
      expect(parked.dx, lessThan(ace.dx));
      expect((parked.dy - ace.dy).abs(), lessThan(1.0));
    },
  );
}
