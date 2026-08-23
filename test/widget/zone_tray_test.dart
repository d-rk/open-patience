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
import 'package:open_patience/presentation/board_geometry.dart';
import 'package:open_patience/presentation/card_view.dart';
import 'package:open_patience/presentation/zone_tray.dart';
import 'package:open_patience/ui/theme/game_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

Card _up(Suit s, int r) => Card(suit: s, rank: r, faceUp: true);

GameState _klondike() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation, cards: <Card>[_up(Suit.clubs, aceRank)]),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.tableau, cards: <Card>[_up(Suit.spades, 5)]),
    for (int i = 0; i < 6; i++) Pile(kind: PileKind.tableau),
  ],
);

Future<void> _pump(WidgetTester tester, Size size, GameState state) async {
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
      home: Scaffold(
        body: BlocProvider<GameBloc>.value(value: bloc, child: const Board()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Color _fillOf(WidgetTester tester, TrayKind kind) {
  final ZoneTray tray = tester.widget<ZoneTray>(
    find.byWidgetPredicate((Widget w) => w is ZoneTray && w.kind == kind),
  );
  final DecoratedBox box = tester.widget<DecoratedBox>(
    find.descendant(
      of: find.byWidget(tray),
      matching: find.byType(DecoratedBox),
    ),
  );
  return (box.decoration as BoxDecoration).color!;
}

void main() {
  testWidgets('renders a foundation and a parking zone tray with their fills', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const Size(400, 800), _klondike());

    expect(find.byType(ZoneTray), findsNWidgets(2));
    expect(
      _fillOf(tester, TrayKind.foundation),
      GamePalette.foundationTrayFill,
    );
    expect(_fillOf(tester, TrayKind.parking), GamePalette.parkingTrayFill);
  });

  testWidgets('the foundation tray frames its foundation card', (
    WidgetTester tester,
  ) async {
    await _pump(tester, const Size(400, 800), _klondike());

    final Finder trayFinder = find.byWidgetPredicate(
      (Widget w) => w is ZoneTray && w.kind == TrayKind.foundation,
    );
    final Finder aceFinder = find.byWidgetPredicate(
      (Widget w) =>
          w is CardFace && w.card.suit == Suit.clubs && w.card.rank == aceRank,
    );
    final Rect trayRect = tester.getRect(trayFinder);
    final Rect aceRect = tester.getRect(aceFinder);
    // The tray panel encloses the foundation card it sits behind.
    expect(trayRect.contains(aceRect.center), isTrue);
    expect(trayRect.left, lessThan(aceRect.left));
    expect(trayRect.top, lessThan(aceRect.top));
  });
}
