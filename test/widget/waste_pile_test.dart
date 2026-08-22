import 'package:flutter/material.dart' hide Card;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/games/klondike.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/presentation/bloc/game_bloc.dart';
import 'package:open_patience/presentation/bloc/game_event.dart';
import 'package:open_patience/presentation/card_view.dart';
import 'package:open_patience/ui/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Card _down(Suit s, int r) => Card(suit: s, rank: r);

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

/// A board with only the stock populated (given, in stock order — the last
/// card in [stock] is the physical top, drawn first) and every other pile
/// empty, so the waste pile's contents after drawing are entirely
/// deterministic.
GameState _game(List<Card> stock) {
  return GameState(
    piles: <Pile>[
      Pile(kind: PileKind.stock, cards: stock),
      Pile(kind: PileKind.waste),
      Pile(kind: PileKind.foundation),
      Pile(kind: PileKind.foundation),
      Pile(kind: PileKind.foundation),
      Pile(kind: PileKind.foundation),
      for (int i = 0; i < 7; i++) Pile(kind: PileKind.tableau),
    ],
  );
}

GameBloc _bloc(RecordsRepository repo, String variant, GameState state) {
  return GameBloc(variant: variant, repository: repo, seed: 1, state: state);
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

Future<void> _draw(WidgetTester tester, GameBloc bloc) async {
  bloc.add(const TapMoveRequested(fromPile: KlondikeRules.stockIndex));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('drawing three fans the waste with a slight offset', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    // Physical stock order (last drawn first): spades9, clubs2, diamonds4,
    // hearts6 — a draw-three pulls the top three, leaving spades9 behind.
    final GameBloc bloc = _bloc(
      repo,
      'klondike-draw3',
      _game(<Card>[
        _down(Suit.spades, 9),
        _down(Suit.clubs, 2),
        _down(Suit.diamonds, 4),
        _down(Suit.hearts, 6),
      ]),
    );
    addTearDown(bloc.close);

    await _pump(tester, bloc);
    await _draw(tester, bloc);

    final Finder oldest = _cardFace(Suit.clubs, 2);
    final Finder middle = _cardFace(Suit.diamonds, 4);
    final Finder top = _cardFace(Suit.hearts, 6);
    expect(oldest, findsOneWidget);
    expect(middle, findsOneWidget);
    expect(top, findsOneWidget);

    // All three sit in one row, each shifted right of the last — never
    // stacked exactly on top of each other.
    final double oldestX = tester.getTopLeft(oldest).dx;
    final double middleX = tester.getTopLeft(middle).dx;
    final double topX = tester.getTopLeft(top).dx;
    expect(middleX, greaterThan(oldestX));
    expect(topX, greaterThan(middleX));
    expect(
      tester.getTopLeft(oldest).dy,
      closeTo(tester.getTopLeft(top).dy, 0.5),
    );
  });

  testWidgets(
    'draw-one reveals the previously drawn card while the top waste card is dragged',
    (WidgetTester tester) async {
      final RecordsRepository repo = await _repo();
      // Physical stock order (last drawn first): clubs9 (left behind),
      // diamonds5, hearts3 — two draw-ones pull hearts3 then diamonds5, so
      // hearts3 ends up underneath the later, topmost diamonds5.
      final GameBloc bloc = _bloc(
        repo,
        'klondike-draw1',
        _game(<Card>[
          _down(Suit.clubs, 9),
          _down(Suit.diamonds, 5),
          _down(Suit.hearts, 3),
        ]),
      );
      addTearDown(bloc.close);

      await _pump(tester, bloc);
      await _draw(tester, bloc);
      await _draw(tester, bloc);

      final Finder top = _cardFace(Suit.diamonds, 5);
      final Finder below = _cardFace(Suit.hearts, 3);
      expect(top, findsOneWidget);
      // The card the top draw is sitting on is already represented in the
      // tree (fully covered), not simply absent — otherwise there is nothing
      // to reveal once the top card lifts away.
      expect(below, findsOneWidget);
      expect(_placeholders(), findsNothing);

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(top),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();

      // Mid-drag: the lifted card leaves no ghost behind (it rides in the
      // floating feedback and appears exactly once), and the card underneath
      // it is still there to be seen.
      expect(_placeholders(), findsNothing);
      expect(top, findsOneWidget);
      expect(below, findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );
}
