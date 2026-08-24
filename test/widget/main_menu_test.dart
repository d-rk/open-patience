import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/game_registry.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/persistence/stats.dart';
import 'package:open_patience/presentation/board.dart';
import 'package:open_patience/ui/main_menu_screen.dart';
import 'package:open_patience/ui/widgets/menu_banner.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<RecordsRepository> _repo() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return SharedPrefsRecordsRepository(prefs);
}

Widget _host(Widget child) => MediaQuery(
  data: const MediaQueryData(disableAnimations: true),
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('lists the games and opens a game\'s options', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(_host(MainMenuScreen(repository: repo)));
    await tester.pumpAndSettle();

    expect(find.text('Klondike'), findsOneWidget);
    expect(find.text('FreeCell'), findsOneWidget);
    // The title screen no longer shows per-variant rows.
    expect(find.text('Draw 1'), findsNothing);

    await tester.tap(find.text('Klondike'));
    await tester.pumpAndSettle();
    expect(find.text('Draw 1'), findsOneWidget);
  });

  testWidgets('an in-progress game appears in Continue and resumes', (
    WidgetTester tester,
  ) async {
    // A real landscape surface: a zero-size MediaQuery would trip the
    // pre-existing FreeCell Board layout overflow (out of scope here).
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final RecordsRepository repo = await _repo();
    await repo.saveGame(
      variant: 'freecell',
      seed: 9,
      state: GameState.newGame(GameRegistry.rulesFor('freecell'), seed: 9),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(1200, 800),
          disableAnimations: true,
        ),
        child: MaterialApp(home: MainMenuScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue playing'), findsOneWidget);
    await tester.tap(find.text('Resume').first);
    await tester.pumpAndSettle();
    expect(find.byType(Board), findsOneWidget);
  });

  testWidgets('Continue refreshes when returning from a pushed route', (
    WidgetTester tester,
  ) async {
    // Landscape surface (defensive; the menu itself renders no Board).
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(1200, 800),
          disableAnimations: true,
        ),
        child: MaterialApp(home: MainMenuScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Continue playing'), findsNothing);

    // Leave the menu for a pushed route (game options).
    await tester.tap(find.text('Klondike'));
    await tester.pumpAndSettle();

    // A save materialises while we are away from the menu.
    await repo.saveGame(
      variant: 'freecell',
      seed: 9,
      state: GameState.newGame(GameRegistry.rulesFor('freecell'), seed: 9),
    );

    // Return to the menu; it must reflect the repository's current state.
    final NavigatorState nav = tester.state(find.byType(Navigator));
    nav.pop();
    await tester.pumpAndSettle();

    expect(find.text('Continue playing'), findsOneWidget);
  });

  testWidgets('swiping a Continue row removes it and clears the save', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await repo.saveGame(
      variant: 'freecell',
      seed: 9,
      state: GameState.newGame(GameRegistry.rulesFor('freecell'), seed: 9),
    );
    await tester.pumpWidget(_host(MainMenuScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('Continue playing'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey<String>('continue-freecell')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('Continue playing'), findsNothing);
    expect(await repo.loadAllSaves(), isEmpty);
  });

  testWidgets(
    'swiping away a Continue row with moves played records it as a loss',
    (WidgetTester tester) async {
      final RecordsRepository repo = await _repo();
      final GameState fresh = GameState.newGame(
        GameRegistry.rulesFor('freecell'),
        seed: 9,
      );
      await repo.saveGame(
        variant: 'freecell',
        seed: 9,
        state: GameState(piles: fresh.piles, moveCount: 3),
      );
      await tester.pumpWidget(_host(MainMenuScreen(repository: repo)));
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const ValueKey<String>('continue-freecell')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      final Stats stats = await repo.statsFor('freecell');
      expect(stats.gamesPlayed, 1);
      expect(stats.gamesWon, 0);
    },
  );

  testWidgets('swiping away an untouched Continue row does not record a loss', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await repo.saveGame(
      variant: 'freecell',
      seed: 9,
      state: GameState.newGame(GameRegistry.rulesFor('freecell'), seed: 9),
    );
    await tester.pumpWidget(_host(MainMenuScreen(repository: repo)));
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey<String>('continue-freecell')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();

    final Stats stats = await repo.statsFor('freecell');
    expect(stats.gamesPlayed, 0);
  });

  testWidgets('no Continue section when nothing is in progress', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(_host(MainMenuScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('Continue playing'), findsNothing);
  });

  testWidgets('shrinks the hero banner in a short landscape viewport', (
    WidgetTester tester,
  ) async {
    // A small phone in landscape: only ~360dp tall. The full-height portrait
    // banner would crowd the games list off the bottom, so it must shrink.
    tester.view.physicalSize = const Size(720, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(720, 360),
          disableAnimations: true,
        ),
        child: MaterialApp(home: MainMenuScreen(repository: repo)),
      ),
    );
    await tester.pumpAndSettle();

    // The banner is compact (well below its 168dp portrait height), leaving
    // room for the games list — the Klondike tile stays on screen.
    expect(tester.getSize(find.byType(MenuBanner)).height, lessThan(110));
    expect(find.text('Klondike'), findsOneWidget);
    expect(
      tester.getBottomLeft(find.text('Klondike')).dy,
      lessThanOrEqualTo(360),
    );
  });

  testWidgets('shows the handwritten signature footer', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(_host(MainMenuScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('made by Dirk Wilden'), findsOneWidget);
  });

  testWidgets('tapping the banner logo 10 times in a row unlocks debug mode', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(_host(MainMenuScreen(repository: repo)));
    await tester.pumpAndSettle();

    for (int i = 0; i < 9; i++) {
      await tester.tap(find.byType(MenuBanner));
      await tester.pump();
    }
    expect(find.text('Debug mode enabled'), findsNothing);

    await tester.tap(find.byType(MenuBanner));
    await tester.pump();
    expect(find.text('Debug mode enabled'), findsOneWidget);
  });
}
