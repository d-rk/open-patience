import 'package:flutter/material.dart' hide Card;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_registry.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/presentation/bloc/game_bloc.dart';
import 'package:open_patience/presentation/board.dart';
import 'package:open_patience/presentation/board_geometry.dart';
import 'package:open_patience/presentation/board_sequence.dart';
import 'package:open_patience/presentation/card_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

Finder _cardFace(Suit s, int rank) => find.byWidgetPredicate(
  (Widget w) =>
      w is CardFace && w.card.suit == s && w.card.rank == rank && w.card.faceUp,
);

GameState _oneAce() => GameState(
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

GameState _stockToDraw() => GameState(
  piles: <Pile>[
    Pile(
      kind: PileKind.stock,
      cards: const <Card>[
        Card(suit: Suit.hearts, rank: 9), // face-down in stock
      ],
    ),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    for (int i = 0; i < 7; i++) Pile(kind: PileKind.tableau),
  ],
);

GameState _dragPair() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, 7)]),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.hearts, 8)]),
    for (int i = 0; i < 5; i++) Pile(kind: PileKind.tableau),
  ],
);

GameState _aceOverKing() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, aceRank)]),
    for (int i = 0; i < 5; i++) Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.hearts, kingRank)]),
  ],
);

List<Card> _run(Suit s, int upTo) => <Card>[
  for (int r = aceRank; r <= upTo; r++) _up(s, r),
];

/// A board one legal tap-to-foundation away from a win: three foundations are
/// complete (Ace..King) and the fourth is Ace..Queen, with its lone King sitting
/// face-up on a tableau column. Tapping that King sends it to its foundation, so
/// the bloc emits `GameWon` and the board plays its win flourish.
GameState _almostWon() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation, cards: _run(Suit.clubs, kingRank)),
    Pile(kind: PileKind.foundation, cards: _run(Suit.diamonds, kingRank)),
    Pile(kind: PileKind.foundation, cards: _run(Suit.hearts, kingRank)),
    Pile(kind: PileKind.foundation, cards: _run(Suit.spades, 12)),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, kingRank)]),
    for (int i = 0; i < 6; i++) Pile(kind: PileKind.tableau),
  ],
);

Future<GameBloc> _pump(
  WidgetTester tester,
  Size size, {
  required GameState state,
  bool disableAnimations = false,
  String variant = 'klondike-draw1',
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final RecordsRepository repo = SharedPrefsRecordsRepository(
    await SharedPreferences.getInstance(),
  );
  final GameBloc bloc = GameBloc(
    variant: variant,
    repository: repo,
    seed: 1,
    state: state,
  );
  addTearDown(bloc.close);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: disableAnimations),
        child: Scaffold(
          body: BlocProvider<GameBloc>.value(value: bloc, child: const Board()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return bloc;
}

/// Like [_pump] but stops after the first frame — the deal set-piece is *still
/// playing*, so tests can observe cards mid-deal instead of at rest.
Future<GameBloc> _startDeal(
  WidgetTester tester,
  Size size, {
  required GameState state,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final RecordsRepository repo = SharedPrefsRecordsRepository(
    await SharedPreferences.getInstance(),
  );
  final GameBloc bloc = GameBloc(
    variant: 'klondike-draw1',
    repository: repo,
    seed: 1,
    state: state,
  );
  addTearDown(bloc.close);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: BlocProvider<GameBloc>.value(value: bloc, child: const Board()),
        ),
      ),
    ),
  );
  await tester.pump(); // first frame — deal starts, nothing settled
  return bloc;
}

Finder _faceDown(Suit s, int rank) => find.byWidgetPredicate(
  (Widget w) =>
      w is CardFace &&
      w.card.suit == s &&
      w.card.rank == rank &&
      !w.card.faceUp,
);

/// The paint-order index (low = painted first/behind, high = on top) of the
/// [AnimatedPositioned] whose subtree holds [s]/[rank]'s [CardFace]. The board
/// Stack paints children in element-list order, so this reflects z-order.
int _paintIndexOf(WidgetTester tester, Suit s, int rank) {
  final List<Element> positioned = tester
      .elementList(find.byType(AnimatedPositioned))
      .toList();
  for (int i = 0; i < positioned.length; i++) {
    CardFace? face;
    void visit(Element el) {
      if (el.widget is CardFace) {
        face ??= el.widget as CardFace;
      }
      el.visitChildren(visit);
    }

    positioned[i].visitChildren(visit);
    if (face != null && face!.card.suit == s && face!.card.rank == rank) {
      return i;
    }
  }
  return -1;
}

void main() {
  testWidgets('board renders every card exactly once inside a single Stack', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const Size(400, 800), state: _oneAce());
    expect(tester.takeException(), isNull);
    expect(_cardFace(Suit.spades, aceRank), findsOneWidget);
  });

  testWidgets('reduce-motion: a tap-move lands instantly in one frame', (
    WidgetTester tester,
  ) async {
    final GameBloc bloc = await _pump(
      tester,
      const Size(400, 800),
      state: _oneAce(),
      disableAnimations: true,
    );
    await tester.tap(_cardFace(Suit.spades, aceRank));
    // A card that also handles double-tap defers its onTap until the
    // double-tap window closes; let that timer elapse so the move fires.
    await tester.pump(const Duration(milliseconds: 350)); // fire onTap
    await tester.pump(); // one build; no animation to settle
    expect(bloc.state.state.pileAt(6).isEmpty, isTrue);
    // The ace now renders at a foundation position (top of the board).
    expect(tester.getCenter(_cardFace(Suit.spades, aceRank)).dy, lessThan(200));
  });

  testWidgets('animated tap-move converges to the same final layout', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const Size(400, 800), state: _oneAce());
    final Offset before = tester.getCenter(_cardFace(Suit.spades, aceRank));
    await tester.tap(_cardFace(Suit.spades, aceRank));
    // A card that also handles double-tap defers its onTap until the
    // double-tap window closes; let that timer elapse so the move fires.
    await tester.pump(const Duration(milliseconds: 350)); // fire onTap
    await tester.pump(); // rebuild applies the new target, animation begins
    await tester.pump(const Duration(milliseconds: 60)); // mid-flight
    final Offset mid = tester.getCenter(_cardFace(Suit.spades, aceRank));
    await tester.pumpAndSettle();
    final Offset after = tester.getCenter(_cardFace(Suit.spades, aceRank));
    // It actually moved during the animation (not an instant jump)...
    expect(mid, isNot(equals(before)));
    expect(mid, isNot(equals(after)));
    // ...and settled above where it started (now on a foundation).
    expect(after.dy, lessThan(before.dy));
  });

  testWidgets('a moving card paints above the cards it flies over', (
    WidgetTester tester,
  ) async {
    // Ace on tableau col 6; a lone king sits on the last tableau column. When
    // the ace is tapped it flies up to a foundation. In pile-major paint order a
    // foundation card sorts *before* tableau cards, so without a moving-set the
    // king would paint on top of the flying ace. Mid-flight the ace must be the
    // last CardFace in the Stack instead.
    await _pump(tester, const Size(400, 800), state: _aceOverKing());
    await tester.tap(_cardFace(Suit.spades, aceRank));
    // A card that also handles double-tap defers its onTap until the
    // double-tap window closes; let that timer elapse so the move fires.
    await tester.pump(const Duration(milliseconds: 350)); // fire onTap
    await tester.pump(); // rebuild applies the new target, animation begins
    await tester.pump(const Duration(milliseconds: 60)); // mid-flight

    final List<CardFace> faces = tester
        .widgetList<CardFace>(find.byType(CardFace))
        .toList();
    // The flying ace is the last-painted CardFace.
    expect(faces.last.card.suit, Suit.spades);
    expect(faces.last.card.rank, aceRank);

    await tester.pumpAndSettle();
  });

  testWidgets('drawing from stock ends with a face-up card on the waste', (
    WidgetTester tester,
  ) async {
    final GameBloc bloc = await _pump(
      tester,
      const Size(400, 800),
      state: _stockToDraw(),
    );
    // Tap the stock (top-left) to draw.
    await tester.tap(find.byType(CardFace).first);
    await tester.pumpAndSettle();
    expect(bloc.state.state.pileAt(1).topCard!.faceUp, isTrue);
    expect(_cardFace(Suit.hearts, 9), findsOneWidget); // face-up nine on waste
  });

  testWidgets('drawing from stock actually rotates a card mid-flip', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const Size(400, 800), state: _stockToDraw());
    await tester.tap(find.byType(CardFace).first);
    await tester.pump(); // dispatch the draw; the flip begins
    await tester.pump(const Duration(milliseconds: 80)); // mid-flip
    // Some keyed flip Transform is genuinely rotated (not the identity) — the
    // drawn card is turning. The others (untouched cards) stay at identity.
    final Iterable<Transform> mid = tester.widgetList<Transform>(
      find.byKey(const Key('cardFlip')),
    );
    expect(
      mid.any((Transform t) => t.transform != Matrix4.identity()),
      isTrue,
      reason: 'expected a rotationY flip in progress mid-draw',
    );
    await tester.pumpAndSettle();
    // Settled: every flip Transform is back to the identity and the drawn card
    // is face-up on the waste.
    final Iterable<Transform> settled = tester.widgetList<Transform>(
      find.byKey(const Key('cardFlip')),
    );
    expect(
      settled.every((Transform t) => t.transform == Matrix4.identity()),
      isTrue,
    );
    expect(_cardFace(Suit.hearts, 9), findsOneWidget);
  });

  testWidgets('a dropped card settles from the release point, not the source', (
    WidgetTester tester,
  ) async {
    final GameBloc bloc = await _pump(
      tester,
      const Size(400, 800),
      state: _dragPair(),
    );
    final Offset source = tester.getCenter(_cardFace(Suit.spades, 7));
    final Offset target = tester.getCenter(_cardFace(Suit.hearts, 8));

    final TestGesture g = await tester.startGesture(source);
    await tester.pump(const Duration(milliseconds: 200));
    await g.moveTo(target);
    await tester.pump();
    await g.up();
    await tester.pump(); // move accepted; card re-homed to col 7
    await tester.pump(const Duration(milliseconds: 30)); // first settle frame

    // Mid-settle the seven is near the release point (col 7), NOT back at col 6.
    final double x = tester.getCenter(_cardFace(Suit.spades, 7)).dx;
    expect((x - target.dx).abs(), lessThan((x - source.dx).abs()));

    await tester.pumpAndSettle();
    expect(bloc.state.state.pileAt(7).length, 2); // 8 then 7
  });

  testWidgets('a fresh deal converges to the resolved layout', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const Size(400, 800), state: _dragPair());
    // During the deal, some cards have not yet reached their slots.
    await tester.pump(const Duration(milliseconds: 10));
    // After it settles, both distinctive cards are at rest and visible.
    await tester.pumpAndSettle();
    expect(_cardFace(Suit.spades, 7), findsOneWidget);
    expect(_cardFace(Suit.hearts, 8), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a card waiting at the deal origin shows its back, not its face',
    (WidgetTester tester) async {
      await _startDeal(tester, const Size(400, 800), state: _dragPair());
      // hearts-8 is the second card in paint order, so it waits at the origin
      // until ~40ms. Sample at 20ms, while it is still parked there.
      await tester.pump(const Duration(milliseconds: 20));
      // It must read as a face-down back at the origin, not its (face-up) face.
      expect(_cardFace(Suit.hearts, 8), findsNothing);
      expect(_faceDown(Suit.hearts, 8), findsOneWidget);
      // Once dealt it lands face up.
      await tester.pumpAndSettle();
      expect(_cardFace(Suit.hearts, 8), findsOneWidget);
    },
  );

  testWidgets('draw-3 leaves the top waste card painted on top', (
    WidgetTester tester,
  ) async {
    // Stock holds three face-down cards; only its top is rendered before the
    // draw. Drawing surfaces all three to the waste — the buried two merely
    // appear (they never fly), so they must not be lifted above the flying top
    // card, or the fan's z-order scrambles (middle card ends up on top).
    final GameState state = GameState(
      piles: <Pile>[
        Pile(
          kind: PileKind.stock,
          cards: const <Card>[
            Card(suit: Suit.clubs, rank: 3),
            Card(suit: Suit.clubs, rank: 4),
            Card(suit: Suit.clubs, rank: 5), // top of stock -> top of waste
          ],
        ),
        Pile(kind: PileKind.waste),
        for (int i = 0; i < 4; i++) Pile(kind: PileKind.foundation),
        for (int i = 0; i < 7; i++) Pile(kind: PileKind.tableau),
      ],
    );
    await _pump(
      tester,
      const Size(400, 800),
      state: state,
      variant: 'klondike-draw3',
    );

    await tester.tap(find.byType(GestureDetector).first); // tap the stock
    await tester.pumpAndSettle();

    // The waste is [3,4,5]; the playable top (5) must paint above 4 above 3.
    final int z3 = _paintIndexOf(tester, Suit.clubs, 3);
    final int z4 = _paintIndexOf(tester, Suit.clubs, 4);
    final int z5 = _paintIndexOf(tester, Suit.clubs, 5);
    expect(z3, isNonNegative);
    expect(z4, greaterThan(z3));
    expect(z5, greaterThan(z4));
  });

  testWidgets('no card is ever shown face up at the deal origin', (
    WidgetTester tester,
  ) async {
    final GameState deal = GameState.newGame(
      GameRegistry.rulesFor('klondike-draw1'),
      seed: 1,
    );
    final BoardGeometry g = BoardGeometry.resolve(
      game: deal,
      width: 400,
      height: 800,
      shortestSide: 400,
      isLandscape: false,
      wasteVisibleCount: 1,
    );
    final Offset origin = dealOriginOf(g);
    await _startDeal(tester, const Size(400, 800), state: deal);

    // Walk the whole deal frame by frame. A face-up card must never be rendered
    // at the fly-from origin: waiting cards show their back, and each card only
    // reveals its face (mid-flip) once it has flown clear of the deck.
    for (int frame = 0; frame < 120; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      for (final CardFace f in tester.widgetList<CardFace>(
        find.byType(CardFace),
      )) {
        if (!f.card.faceUp) {
          continue;
        }
        final Offset tl = tester.getTopLeft(find.byWidget(f));
        expect(
          (tl - origin).distance,
          greaterThan(g.cardSize.height * 0.5),
          reason:
              'face-up ${f.card.suit.name}${f.card.rank} flashed at the deal '
              'origin on frame $frame',
        );
      }
    }
    await tester.pumpAndSettle();
  });

  testWidgets('the deal ends without every card lurching back to the origin', (
    WidgetTester tester,
  ) async {
    // A full Klondike deal (~29 animated cards) so an early card settles well
    // before the controller completes, giving a clear window across completion.
    final GameState deal = GameState.newGame(
      GameRegistry.rulesFor('klondike-draw1'),
      seed: 1,
    );
    final GameBloc bloc = await _startDeal(
      tester,
      const Size(400, 800),
      state: deal,
    );
    // The second tableau column's bottom card is dealt early and stays face
    // down (so it reads as a plain CardFace whether at rest or, in the bug,
    // re-pended to the origin).
    final Card early = bloc.state.state.pileAt(7).cards.first;
    final Finder earlyFinder = _faceDown(early.suit, early.rank);

    // Play the deal out in real frames so that card genuinely settles at rest.
    for (int t = 0; t < 400; t += 40) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    final double rest = tester.getTopLeft(earlyFinder).dy;
    // Keep stepping across the controller-completion boundary. The card is long
    // settled and must not move: a regression re-pended every card to the origin
    // on the completion frame, so all cards lurched back.
    for (int i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 40)); // 440ms .. 2040ms
      expect(
        tester.getTopLeft(earlyFinder).dy,
        closeTo(rest, 2.0),
        reason: 'card lurched toward the origin at step $i',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce-motion deals instantly (no stagger)', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      const Size(400, 800),
      state: _dragPair(),
      disableAnimations: true,
    );
    await tester.pump();
    expect(_cardFace(Suit.spades, 7), findsOneWidget);
  });

  testWidgets('winning plays a cascade and then rests without error', (
    WidgetTester tester,
  ) async {
    // Drive the win with a real final move: tap the lone King up to its
    // foundation, which completes the board and makes the bloc emit GameWon.
    final GameBloc bloc = await _pump(
      tester,
      const Size(400, 800),
      state: _almostWon(),
    );
    await tester.tap(_cardFace(Suit.spades, kingRank));
    // A card that also handles double-tap defers its onTap until the
    // double-tap window closes; let that timer elapse so the move fires.
    await tester.pump(const Duration(milliseconds: 350)); // fire onTap
    await tester.pump(); // rebuild: GameWon, the cascade begins
    // Mid-cascade, past the initial upward launch pop (so the card has
    // clearly fallen, not just popped up off its foundation).
    await tester.pump(const Duration(milliseconds: 300));
    // The cascade translates a foundation card downward (a positive
    // y-translation); nothing else in the board translates, so a Transform
    // with one proves the cascade is playing.
    final Iterable<Transform> transforms = tester.widgetList<Transform>(
      find.byType(Transform),
    );
    expect(
      transforms.any((Transform t) => t.transform.storage[13] > 0.5),
      isTrue,
      reason: 'expected a foundation card translated downward mid-cascade',
    );
    await tester.pumpAndSettle();
    expect(bloc.state.state.isWon(bloc.rules), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a buried foundation card revealed by the cascade is not interactive',
    (WidgetTester tester) async {
      // The clubs foundation has two cards once won (Ace then King); the
      // cascade must reveal the buried Ace as a plain, non-draggable face —
      // only the real top card is ever interactive.
      final GameBloc bloc = await _pump(
        tester,
        const Size(400, 800),
        state: _almostWon(),
      );
      await tester.tap(_cardFace(Suit.spades, kingRank));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(); // rebuild: GameWon, the cascade begins
      final Finder buriedAce = _cardFace(Suit.clubs, aceRank);
      expect(buriedAce, findsOneWidget);
      expect(tester.widget<CardFace>(buriedAce).card.faceUp, isTrue);
      expect(
        find.ancestor(of: buriedAce, matching: find.byType(CardView)),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(bloc.state.state.isWon(bloc.rules), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduce-motion shows the flipped face immediately', (
    WidgetTester tester,
  ) async {
    final GameBloc bloc = await _pump(
      tester,
      const Size(400, 800),
      state: _stockToDraw(),
      disableAnimations: true,
    );
    await tester.tap(find.byType(CardFace).first);
    await tester.pump();
    await tester.pump();
    expect(bloc.state.state.pileAt(1).topCard!.faceUp, isTrue);
    expect(_cardFace(Suit.hearts, 9), findsOneWidget);
  });
}
