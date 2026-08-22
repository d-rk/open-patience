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

  testWidgets('the deal ends without every card lurching back to the origin', (
    WidgetTester tester,
  ) async {
    await _startDeal(tester, const Size(400, 800), state: _dragPair());
    // Play the deal out in real frames so the card genuinely settles at rest.
    for (int t = 0; t < 500; t += 40) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    final double rest = tester.getTopLeft(_cardFace(Suit.hearts, 8)).dy;
    // Keep stepping across the controller-completion boundary (~2260ms). The
    // card is long settled and must not move: a regression re-pended every card
    // to the origin on the completion frame, so all cards lurched back.
    for (int i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 40)); // 540ms .. 2940ms
      expect(
        tester.getTopLeft(_cardFace(Suit.hearts, 8)).dy,
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

  testWidgets('winning plays a flourish and then rests without error', (
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
    await tester.pump(); // rebuild: GameWon, the flourish begins
    await tester.pump(const Duration(milliseconds: 100)); // mid-flourish
    // The pulse scales a foundation card up (>1.0); nothing else scales up, so a
    // Transform with an x-scale above 1 proves the flourish is playing.
    final Iterable<Transform> transforms = tester.widgetList<Transform>(
      find.byType(Transform),
    );
    expect(
      transforms.any((Transform t) => t.transform.storage[0] > 1.001),
      isTrue,
      reason: 'expected a foundation card scaled up mid-flourish',
    );
    await tester.pumpAndSettle();
    expect(bloc.state.state.isWon(bloc.rules), isTrue);
    expect(tester.takeException(), isNull);
  });

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
