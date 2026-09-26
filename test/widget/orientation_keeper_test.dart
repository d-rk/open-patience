import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/orientation_keeper.dart';

// Android's lock screen is portrait-only on most phones, so turning the screen
// off rotates the display to portrait behind it. On unlock the app is left in
// portrait unless the orientation sensor proposes a new rotation — which it
// never does while the phone lies flat on a table. OrientationKeeper pins the
// orientation the player was using while the app is backgrounded and keeps it
// until the player physically turns the device to the other orientation.
//
// It must not release on a timer: with auto-rotate off (e.g. the Samsung
// rotate-suggestion button was used to get landscape), handing rotation back
// to the system re-applies its locked rotation, which is portrait after the
// lock screen, so the app flipped to portrait ~1s after unlock.

const Duration _release = Duration(milliseconds: 500);
const Duration _settle = Duration(milliseconds: 300);
const List<String> _free = <String>[];

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

  late StreamController<Orientation?> device;

  Future<void> pumpKeeper(
    WidgetTester tester,
    Size size, {
    Stream<Orientation?>? physicalOrientation,
  }) async {
    device = StreamController<Orientation?>.broadcast();
    addTearDown(device.close);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: OrientationKeeper(
          releaseDelay: _release,
          settleDelay: _settle,
          physicalOrientation: physicalOrientation ?? device.stream,
          child: const SizedBox(),
        ),
      ),
    );
  }

  void screenOff(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }

  void screenOn(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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

  testWidgets('keeps the pin after unlock while the device is not turned', (
    WidgetTester tester,
  ) async {
    await pumpKeeper(tester, const Size(800, 400));
    screenOff(tester);
    requested.clear();

    screenOn(tester);
    device.add(Orientation.landscape); // still held (or lying) in landscape
    device.add(null); // flat on the table: no reading
    await tester.pump(const Duration(seconds: 10));

    expect(requested, isNot(contains(_free)));
  });

  testWidgets('releases the pin once the device is turned and held', (
    WidgetTester tester,
  ) async {
    await pumpKeeper(tester, const Size(800, 400));
    screenOff(tester);
    screenOn(tester);
    requested.clear();

    device.add(Orientation.portrait);
    await tester.pump(_settle ~/ 2);
    expect(requested, isEmpty, reason: 'must be held, not just passed through');

    await tester.pump(_settle);
    expect(requested, <List<String>>[_free]);
  });

  testWidgets('a brief wobble to the other orientation keeps the pin', (
    WidgetTester tester,
  ) async {
    await pumpKeeper(tester, const Size(800, 400));
    screenOff(tester);
    screenOn(tester);
    requested.clear();

    device.add(Orientation.portrait);
    await tester.pump(_settle ~/ 2);
    device.add(Orientation.landscape);
    await tester.pump(_settle * 3);

    expect(requested, isEmpty);
  });

  testWidgets('turning the device while the screen is off is ignored', (
    WidgetTester tester,
  ) async {
    await pumpKeeper(tester, const Size(800, 400));
    screenOff(tester);
    requested.clear();

    device.add(Orientation.portrait); // e.g. pocketed upright
    await tester.pump(_settle * 3);
    screenOn(tester);
    await tester.pump(_settle * 3);

    expect(requested, isEmpty);
  });

  testWidgets('without an orientation sensor it releases after a delay', (
    WidgetTester tester,
  ) async {
    await pumpKeeper(
      tester,
      const Size(800, 400),
      physicalOrientation: Stream<Orientation?>.error(MissingPluginException()),
    );
    screenOff(tester);
    screenOn(tester);
    requested.clear();

    await tester.pump(_release ~/ 2);
    expect(requested, isEmpty, reason: 'pin must survive the unlock');
    await tester.pump(_release);
    expect(requested, <List<String>>[_free]);
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
