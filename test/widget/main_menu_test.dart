import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/game_registry.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/presentation/board.dart';
import 'package:open_patience/ui/main_menu_screen.dart';
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

  testWidgets('no Continue section when nothing is in progress', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(_host(MainMenuScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('Continue playing'), findsNothing);
  });

  testWidgets('shows the handwritten signature footer', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(_host(MainMenuScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('a game by Dirk Wilden'), findsOneWidget);
  });
}
