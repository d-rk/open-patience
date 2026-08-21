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
}
