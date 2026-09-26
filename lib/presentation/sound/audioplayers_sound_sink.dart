import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'sound_sink.dart';

/// [SoundSink] over `audioplayers`: one low-latency [AudioPool] per file.
///
/// The audio context makes sounds *mix with* whatever the player is already
/// listening to (iOS `ambient`, which also honors the silent switch; Android
/// game usage without taking audio focus). Every failure is reported to
/// [onError] and swallowed — sound can never crash or stall the game — and
/// playing a file that has not finished preloading is a silent no-op.
class AudioplayersSoundSink implements SoundSink {
  AudioplayersSoundSink({void Function(Object error)? onError})
    : _onError = onError ?? _debugLog;

  static const int _maxPlayersPerSound = 3;

  static final AudioContext _context = AudioContext(
    android: const AudioContextAndroid(
      usageType: AndroidUsageType.game,
      contentType: AndroidContentType.sonification,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  final void Function(Object error) _onError;
  final Map<String, AudioPool> _pools = <String, AudioPool>{};

  bool isLoaded(String asset) => _pools.containsKey(asset);

  @override
  Future<void> preload(List<String> assets) async {
    try {
      await AudioPlayer.global.setAudioContext(_context);
    } catch (error) {
      _onError(error);
    }
    for (final String asset in assets) {
      try {
        _pools[asset] = await AudioPool.create(
          source: AssetSource(asset),
          maxPlayers: _maxPlayersPerSound,
          playerMode: PlayerMode.lowLatency,
          audioContext: _context,
        );
      } catch (error) {
        _onError(error);
      }
    }
  }

  @override
  void play(String asset, double volume) {
    final AudioPool? pool = _pools[asset];
    if (pool == null) {
      return;
    }
    unawaited(pool.start(volume: volume).then<void>((_) {}, onError: _onError));
  }

  static void _debugLog(Object error) => debugPrint('sound: $error');
}
