// Golden-path end-to-end flow, run on a real device/emulator (or the desktop
// harness) via `flutter test integration_test`. Unlike the headless widget
// tests, this drives the real render pipeline, real gestures and the real
// `shared_preferences` platform channel end to end.
//
// Deliberately selective (per the design doc): one critical flow —
// deal a game one move from a win, play that move, and see the win reflected
// on the records screen and in persisted stats.
import 'package:flutter/material.dart' hide Card;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/persistence/stats.dart';
import 'package:open_patience/presentation/bloc/game_bloc.dart';
import 'package:open_patience/presentation/card_view.dart';
import 'package:open_patience/ui/game_screen.dart';
import 'package:open_patience/ui/records_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

List<Card> _run(Suit s, int maxRank) => <Card>[
  for (int r = aceRank; r <= maxRank; r++) _up(s, r),
];

/// A Klondike board one move from a win: three suits complete on their
/// foundations, spades complete up to the Queen, and the King of spades sitting
/// alone on a tableau column ready to be sent home.
GameState _oneMoveFromWin() {
  return GameState(
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
}

Finder _cardFace(Suit s, int rank) => find.byWidgetPredicate(
  (Widget w) =>
      w is CardFace && w.card.suit == s && w.card.rank == rank && w.card.faceUp,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('deal → play the winning move → win recorded on records screen', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SharedPrefsRecordsRepository repository =
        SharedPrefsRecordsRepository(prefs);

    final GameBloc bloc = GameBloc(
      variant: 'klondike-draw1',
      repository: repository,
      seed: 7,
      state: _oneMoveFromWin(),
    );
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<GameBloc>.value(
          value: bloc,
          child: const GameScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The board renders and the game has not been won yet.
    expect(find.text('0 moves'), findsOneWidget);
    expect(find.byType(RecordsScreen), findsNothing);

    // Play the single remaining move: tap the King of spades to its foundation.
    // A card that also handles double-tap defers its onTap until the
    // double-tap window closes, so let that timer elapse.
    await tester.tap(_cardFace(Suit.spades, kingRank));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    // The win navigates to the records screen and the result is persisted.
    expect(find.byType(RecordsScreen), findsOneWidget);
    expect(find.text('Games won'), findsOneWidget);

    final Stats stats = await repository.statsFor('klondike-draw1');
    expect(stats.gamesWon, 1);
    expect(stats.gamesPlayed, 1);
  });
}
