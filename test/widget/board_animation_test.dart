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
