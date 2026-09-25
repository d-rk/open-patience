import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/main.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/ui/main_menu_screen.dart';
import 'package:open_patience/ui/orientation_keeper.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('every screen sits under an OrientationKeeper', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      OpenPatienceApp(repository: SharedPrefsRecordsRepository(prefs)),
    );

    expect(
      find.descendant(
        of: find.byType(OrientationKeeper),
        matching: find.byType(MainMenuScreen),
      ),
      findsOneWidget,
    );
    expect(find.byType(OrientationKeeper), findsOneWidget);
  });
}
