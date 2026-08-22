import 'package:flutter/material.dart' hide Card;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/card.dart';
import 'package:open_patience/core/game_state.dart';
import 'package:open_patience/core/pile.dart';
import 'package:open_patience/persistence/records_repository.dart';
import 'package:open_patience/persistence/shared_prefs_records_repository.dart';
import 'package:open_patience/presentation/bloc/game_bloc.dart';
import 'package:open_patience/presentation/bloc/game_event.dart';
import 'package:open_patience/ui/game_screen.dart';
import 'package:open_patience/ui/theme/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RecordingBloc extends GameBloc {
  _RecordingBloc(RecordsRepository repo, GameState state)
    : super(variant: 'klondike-draw1', repository: repo, seed: 5, state: state);

  final List<GameEvent> recorded = <GameEvent>[];

  @override
  void add(GameEvent event) {
    recorded.add(event);
    super.add(event);
  }
}

GameState _oneCard() => GameState(
  piles: <Pile>[
    Pile(kind: PileKind.stock),
    Pile(kind: PileKind.waste),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(kind: PileKind.foundation),
    Pile(
      kind: PileKind.tableau,
      cards: const <Card>[Card(suit: Suit.spades, rank: 7, faceUp: true)],
    ),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
    Pile(kind: PileKind.tableau),
  ],
);

Future<_RecordingBloc> _repoBloc() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  return _RecordingBloc(SharedPrefsRecordsRepository(prefs), _oneCard());
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

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menu'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menu opens and shows the variant title', (
    WidgetTester tester,
  ) async {
    final _RecordingBloc bloc = await _repoBloc();
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await _openMenu(tester);
    expect(find.text('Klondike (Draw 1)'), findsOneWidget);
  });

  testWidgets('Restart Deal tile dispatches RestartDealRequested and closes', (
    WidgetTester tester,
  ) async {
    final _RecordingBloc bloc = await _repoBloc();
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await _openMenu(tester);
    await tester.tap(find.text('Restart Deal'));
    await tester.pumpAndSettle();
    expect(bloc.recorded.whereType<RestartDealRequested>(), isNotEmpty);
    expect(find.text('Restart Deal'), findsNothing); // dialog closed
  });

  testWidgets('New Deal tile dispatches NewDealRequested and closes', (
    WidgetTester tester,
  ) async {
    final _RecordingBloc bloc = await _repoBloc();
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await _openMenu(tester);
    await tester.tap(find.text('New Deal'));
    await tester.pumpAndSettle();
    expect(bloc.recorded.whereType<NewDealRequested>(), isNotEmpty);
    expect(find.text('New Deal'), findsNothing);
  });

  testWidgets('menu content is width-capped so it stays compact in landscape', (
    WidgetTester tester,
  ) async {
    final _RecordingBloc bloc = await _repoBloc();
    addTearDown(bloc.close);
    await _pump(tester, bloc);
    await _openMenu(tester);
    final MenuWidthLimit widthLimit = tester.widget(
      find.byType(MenuWidthLimit),
    );
    expect(widthLimit.maxWidth, lessThanOrEqualTo(400));
  });

  testWidgets('timer pauses while the in-game menu is open', (
    WidgetTester tester,
  ) async {
    final _RecordingBloc bloc = await _repoBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<GameBloc>.value(
          value: bloc,
          child: const GameScreen(autoTick: Duration(milliseconds: 10)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pump(const Duration(milliseconds: 35));
    final int ticksBeforeMenu = bloc.recorded.whereType<Tick>().length;
    expect(ticksBeforeMenu, greaterThan(0));

    await _openMenu(tester);
    await tester.pump(const Duration(milliseconds: 35));
    expect(bloc.recorded.whereType<Tick>().length, ticksBeforeMenu);

    // Dismiss by tapping the barrier, outside the dialog bounds.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 35));
    expect(
      bloc.recorded.whereType<Tick>().length,
      greaterThan(ticksBeforeMenu),
    );
  });

  testWidgets('Exit closes the dialog and pops back to the previous screen', (
    WidgetTester tester,
  ) async {
    final _RecordingBloc bloc = await _repoBloc();
    addTearDown(bloc.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BlocProvider<GameBloc>.value(
                      value: bloc,
                      child: const GameScreen(),
                    ),
                  ),
                ),
                child: const Text('play'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('play'));
    await tester.pumpAndSettle();
    await _openMenu(tester);
    await tester.tap(find.text('Exit to menu'));
    await tester.pumpAndSettle();
    expect(find.text('play'), findsOneWidget); // back on the launcher screen
    expect(find.byType(GameScreen), findsNothing);
  });
}
