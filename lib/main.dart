import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'persistence/records_repository.dart';
import 'persistence/shared_prefs_records_repository.dart';
import 'ui/main_menu_screen.dart';
import 'ui/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final RecordsRepository repository = SharedPrefsRecordsRepository(prefs);
  runApp(SolitaireApp(repository: repository));
}

/// Root of the app. Owns the single [RecordsRepository] and hands it to the
/// menu, which builds a [GameBloc] per game. All game logic lives in `core/`
/// behind the bloc — this widget only wires dependencies and navigation.
class SolitaireApp extends StatelessWidget {
  const SolitaireApp({required this.repository, super.key});

  final RecordsRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solitaire',
      theme: AppTheme.themeData,
      home: MainMenuScreen(
        repository: repository,
        autoTick: const Duration(seconds: 1),
      ),
    );
  }
}
