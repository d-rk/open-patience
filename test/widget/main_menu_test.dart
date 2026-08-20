import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  testWidgets('menu lists the variants and starts a new game', (
    WidgetTester tester,
  ) async {
    final RecordsRepository repo = await _repo();
    await tester.pumpWidget(
      MaterialApp(home: MainMenuScreen(repository: repo)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Klondike (Draw 1)'), findsOneWidget);
    expect(find.text('Klondike (Draw 3)'), findsOneWidget);
    expect(find.text('FreeCell'), findsOneWidget);

    await tester.tap(find.text('New game').first);
    await tester.pumpAndSettle();

    expect(find.byType(Board), findsOneWidget);
  });
}
