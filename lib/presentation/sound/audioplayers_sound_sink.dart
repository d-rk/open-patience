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
/// playing a file that has not finished preloading is a silent no-op. Each
/// player is handed back to its pool [_releaseAfter] after a clip starts,
/// since a low-latency pool never recycles one on its own.
class AudioplayersSoundSink implements SoundSink {
  AudioplayersSoundSink({void Function(Object error)? onError})
    : _onError = onError ?? _debugLog;

  static const int _maxPlayersPerSound = 3;

  /// Longer than the longest bundled clip (~1.3 s), so the player has
  /// certainly finished before its [StopFunction] is called. Kept ahead of
  /// `MAX_CLIP_S` (1.8 s) in tools/sfx/build_sfx.py, which refuses to render
  /// any clip that wouldn't fit inside this window.
  static const Duration _releaseAfter = Duration(seconds: 2);

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
    unawaited(_playAndRelease(pool, volume));
  }

  /// Low-latency pools never recycle a player on their own, so hand it back
  /// once the clip has certainly finished; otherwise every play would leak a
  /// native player and the pool cap would never apply.
  Future<void> _playAndRelease(AudioPool pool, double volume) async {
    try {
      final StopFunction stop = await pool.start(volume: volume);
      await Future<void>.delayed(_releaseAfter);
      await stop();
    } catch (error) {
      _onError(error);
    }
  }

  static void _debugLog(Object error) {
    if (kDebugMode) {
      debugPrint('sound: $error');
    }
  }
}
