import 'package:flutter/material.dart' hide Card;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/move.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/presentation/bloc/game_bloc.dart';
import 'package:open_patience/ui/top_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

List<Card> _run(Suit s, int maxRank) => <Card>[
  for (int r = aceRank; r <= maxRank; r++) _up(s, r),
];

Future<RecordsRepository> _repo() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return SharedPrefsRecordsRepository(prefs);
}

/// A completed board that still carries undo history, so a check based only
/// on `GameState.canUndo`/`canRedo` (ignoring the won status) would wrongly
/// report the buttons as enabled.
GameState _wonBoardWithHistory() {
  return GameState(
    piles: <Pile>[
      Pile(kind: PileKind.stock),
      Pile(kind: PileKind.waste),
      Pile(kind: PileKind.foundation, cards: _run(Suit.clubs, kingRank)),
      Pile(kind: PileKind.foundation, cards: _run(Suit.diamonds, kingRank)),
      Pile(kind: PileKind.foundation, cards: _run(Suit.hearts, kingRank)),
      Pile(kind: PileKind.foundation, cards: _run(Suit.spades, kingRank)),
      for (int i = 0; i < 7; i++) Pile(kind: PileKind.tableau),
    ],
    undoStack: <Move>[
      Move(fromPile: 6, toPile: 5, cards: <Card>[_up(Suit.spades, kingRank)]),
    ],
    redoStack: <Move>[
      Move(fromPile: 5, toPile: 6, cards: <Card>[_up(Suit.spades, kingRank)]),
    ],
  );
}

IconButton _iconButton(WidgetTester tester, String tooltip) {
  return tester.widget<IconButton>(
    find.byWidgetPredicate(
      (Widget w) => w is IconButton && w.tooltip == tooltip,
    ),
  );
}

void main() {
  testWidgets(
    'undo and redo stay disabled once the game is won, even with history',
    (WidgetTester tester) async {
      final RecordsRepository repo = await _repo();
      final GameBloc bloc = GameBloc(
        variant: 'klondike-draw1',
        repository: repo,
        seed: 1,
        state: _wonBoardWithHistory(),
      );
      addTearDown(bloc.close);

      await tester.pumpWidget(
        MaterialApp(
          home: BlocProvider<GameBloc>.value(
            value: bloc,
            child: TopBar(onMenu: () {}),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_iconButton(tester, 'Undo').onPressed, isNull);
      expect(_iconButton(tester, 'Redo').onPressed, isNull);
    },
  );
}
