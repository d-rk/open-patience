import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps the screen orientation the player was using across a screen-off.
///
/// Android's lock screen is portrait-only on most phones, so turning the
/// screen off rotates the display to portrait behind it. After unlocking, the
/// app stays in portrait until the orientation sensor proposes a new rotation
/// — which it never does while the phone lies flat on a table. With auto-rotate
/// off (landscape reached via the system's rotate-suggestion button) it is
/// worse: whenever the app hands rotation back to the system, the system
/// re-applies its locked rotation, which after the lock screen is portrait.
///
/// So when the app is hidden this pins the current orientation (either
/// landscape or either portrait), and keeps the pin until the player
/// physically turns the device to the other orientation and holds it there
/// for [settleDelay] — only then is rotation handed back to the system. The
/// device's physical orientation comes from [physicalOrientation] (on Android
/// the `OrientationEventListener` bridged in `MainActivity`), which is only
/// listened to while the app is in the foreground. Without a sensor (the
/// stream errors or ends) the pin is released [releaseDelay] after resuming.
class OrientationKeeper extends StatefulWidget {
  const OrientationKeeper({
    required this.child,
    this.releaseDelay = const Duration(seconds: 1),
    this.settleDelay = const Duration(milliseconds: 500),
    this.physicalOrientation,
    super.key,
  });

  final Widget child;

  /// Fallback only: how long the pin outlives a resume when the device has no
  /// orientation sensor to tell us the player turned it.
  final Duration releaseDelay;

  /// How long the device must be held in the other orientation before the pin
  /// is released, so a wobble while picking the phone up doesn't count.
  final Duration settleDelay;

  /// The device's physical orientation, `null` when unknown (e.g. lying flat).
  /// Defaults to the platform sensor channel.
  final Stream<Orientation?>? physicalOrientation;

  @override
  State<OrientationKeeper> createState() => _OrientationKeeperState();
}

class _OrientationKeeperState extends State<OrientationKeeper>
    with WidgetsBindingObserver {
  static const List<DeviceOrientation> _landscape = <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
  static const List<DeviceOrientation> _portrait = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ];

  static const EventChannel _sensorChannel = EventChannel(
    'open_patience/physical_orientation',
  );

  /// The orientation currently pinned, or null when rotation is free.
  Orientation? _pinned;
  StreamSubscription<Orientation?>? _sensor;
  Timer? _settleTimer;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _stopWatching();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _pin();
      case AppLifecycleState.resumed:
        _watchForTurn();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _pin() {
    // Sensor readings while the screen is off (a phone pocketed upright) must
    // never release the pin.
    _stopWatching();
    if (_pinned != null) {
      return;
    }
    final Orientation current = MediaQuery.orientationOf(context);
    _pinned = current;
    SystemChrome.setPreferredOrientations(
      current == Orientation.landscape ? _landscape : _portrait,
    );
  }

  void _watchForTurn() {
    if (_pinned == null || _sensor != null) {
      return;
    }
    final Stream<Orientation?> readings =
        widget.physicalOrientation ?? _platformReadings();
    _sensor = readings.listen(
      _onReading,
      onError: (Object _) => _fallBackToDelay(),
      onDone: _fallBackToDelay,
    );
  }

  void _onReading(Orientation? reading) {
    final Orientation? pinned = _pinned;
    if (pinned == null) {
      return;
    }
    if (reading == null || reading == pinned) {
      // Flat, ambiguous or back in the pinned orientation: not a turn.
      _settleTimer?.cancel();
      _settleTimer = null;
      return;
    }
    _settleTimer ??= Timer(widget.settleDelay, _release);
  }

  void _fallBackToDelay() {
    _sensor?.cancel();
    _sensor = null;
    if (_pinned == null) {
      return;
    }
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(widget.releaseDelay, _release);
  }

  void _release() {
    _stopWatching();
    _pinned = null;
    SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
  }

  void _stopWatching() {
    _sensor?.cancel();
    _sensor = null;
    _settleTimer?.cancel();
    _settleTimer = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }

  static Stream<Orientation?> _platformReadings() {
    return _sensorChannel.receiveBroadcastStream().map(
      (Object? event) => switch (event) {
        'portrait' => Orientation.portrait,
        'landscape' => Orientation.landscape,
        _ => null,
      },
    );
  }
}
