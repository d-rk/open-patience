import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps the screen orientation the player was using across a screen-off.
///
/// Android's lock screen is portrait-only on most phones, so turning the
/// screen off rotates the display to portrait behind it. After unlocking, the
/// app stays in portrait until the orientation sensor proposes a new rotation
/// — which it never does while the phone lies flat on a table.
///
/// When the app is hidden this pins the current orientation (either landscape
/// or either portrait), so unlocking restores it. Shortly after the app
/// resumes the pin is released again and the player can rotate freely.
class OrientationKeeper extends StatefulWidget {
  const OrientationKeeper({
    required this.child,
    this.releaseDelay = const Duration(seconds: 1),
    super.key,
  });

  final Widget child;

  /// How long the pin outlives a resume, so the display has settled in the
  /// pinned orientation before rotation is handed back to the system.
  final Duration releaseDelay;

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

  bool _pinned = false;
  Timer? _releaseTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
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
        _scheduleRelease();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _pin() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    if (_pinned) {
      return;
    }
    _pinned = true;
    final bool isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    SystemChrome.setPreferredOrientations(isLandscape ? _landscape : _portrait);
  }

  void _scheduleRelease() {
    if (!_pinned) {
      return;
    }
    _releaseTimer?.cancel();
    _releaseTimer = Timer(widget.releaseDelay, () {
      _releaseTimer = null;
      _pinned = false;
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    });
  }
}
