import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/game_registry.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/presentation/board.dart';
import 'package:open_patience/ui/game_options_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<RecordsRepository> _repo() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return SharedPrefsRecordsRepository(prefs);
}

// A real landscape size so the destination Board reads a sane orientation:
// the Board chooses its layout from MediaQuery.orientation/size, and a
// zero-size MediaQueryData would force the stacked layout whose FreeCell top
// row overflows at the real render width.
Widget _host(Widget child) => MediaQuery(
  data: const MediaQueryData(size: Size(1200, 800), disableAnimations: true),
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('lists a game\'s variants and plays one', (
    WidgetTester tester,
  ) async {
    // The destination FreeCell board needs a real-device width or its top row
    // overflows at the default 800x600 test surface (see board_layout_test).
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(
      _host(GameOptionsScreen(gameId: 'freecell', repository: repo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Classic · 4 cells'), findsOneWidget);
    expect(find.text('2 cells · hard'), findsOneWidget);
    expect(find.text('6 cells · relaxed'), findsOneWidget);

    await tester.tap(find.text('Play').first);
    await tester.pumpAndSettle();
    expect(find.byType(Board), findsOneWidget);
  });

  testWidgets('Resume appears only for a variant with a save', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await repo.saveGame(
      variant: 'klondike-draw1',
      seed: 1,
      state: GameState.newGame(
        GameRegistry.rulesFor('klondike-draw1'),
        seed: 1,
      ),
    );
    await tester.pumpWidget(
      _host(GameOptionsScreen(gameId: 'klondike', repository: repo)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('Records opens the records screen for the variant', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(
      _host(GameOptionsScreen(gameId: 'freecell', repository: repo)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Records').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Records'), findsWidgets);
  });
}
