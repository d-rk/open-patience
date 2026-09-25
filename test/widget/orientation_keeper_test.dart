import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/orientation_keeper.dart';

// Android's lock screen is portrait-only on most phones, so turning the screen
// off rotates the display to portrait behind it. On unlock the app is left in
// portrait unless the orientation sensor proposes a new rotation — which it
// never does while the phone lies flat on a table. OrientationKeeper pins the
// orientation the player was using while the app is backgrounded and releases
// the pin shortly after it resumes.

const Duration _release = Duration(milliseconds: 500);

void main() {
  late List<List<String>> requested;

  setUp(() {
    requested = <List<String>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (MethodCall call) {
          if (call.method == 'SystemChrome.setPreferredOrientations') {
            requested.add((call.arguments as List<Object?>).cast<String>());
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<void> pumpKeeper(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        home: OrientationKeeper(releaseDelay: _release, child: SizedBox()),
      ),
    );
  }

  testWidgets('pins landscape while backgrounded in landscape', (
    WidgetTester tester,
  ) async {
    await pumpKeeper(tester, const Size(800, 400));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);

    expect(requested, <List<String>>[
      <String>[
        'DeviceOrientation.landscapeLeft',
        'DeviceOrientation.landscapeRight',
      ],
    ]);
  });

  testWidgets('pins portrait while backgrounded in portrait', (
    WidgetTester tester,
  ) async {
    await pumpKeeper(tester, const Size(400, 800));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);

    expect(requested, <List<String>>[
      <String>[
        'DeviceOrientation.portraitUp',
        'DeviceOrientation.portraitDown',
      ],
    ]);
  });

  testWidgets('releases the pin shortly after resuming', (
    WidgetTester tester,
  ) async {
    await pumpKeeper(tester, const Size(800, 400));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    requested.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(_release ~/ 2);
    expect(requested, isEmpty, reason: 'pin must survive the unlock');

    await tester.pump(_release);
    expect(requested, <List<String>>[<String>[]]);
  });

  testWidgets('a brief inactive (e.g. notification shade) never pins', (
    WidgetTester tester,
  ) async {
    await pumpKeeper(tester, const Size(800, 400));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(_release * 2);

    expect(requested, isEmpty);
  });

  testWidgets('backgrounding again before the release keeps the pin', (
    WidgetTester tester,
  ) async {
    await pumpKeeper(tester, const Size(800, 400));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    requested.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(_release * 2);

    expect(requested, isNot(contains(<String>[])));
  });
}
