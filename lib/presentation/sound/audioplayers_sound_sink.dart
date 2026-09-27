import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'sound_sink.dart';

/// [SoundSink] over `audioplayers`: a fixed round-robin pool of
/// [AudioPlayer]s per file, so a rapid re-trigger of the same sound (e.g.
/// several cards landing in the same frame) always has a free player instead
/// of cutting off the one already playing.
///
/// Each player has its position updater disabled (`positionUpdater = null`):
/// `audioplayers`' default [FramePositionUpdater] re-schedules a transient
/// frame callback and polls `getCurrentPosition` over the platform channel
/// every frame for as long as the player reports "playing", which forces
/// continuous redraws for the life of every clip. This app never reads
/// playback position, so that polling is pure overhead — and it's what an
/// `integration_test` run caught as leftover transient callbacks after the
/// widget tree was disposed.
///
/// The audio context makes sounds *mix with* whatever the player is already
/// listening to (iOS `ambient`, which also honors the silent switch; Android
/// game usage without taking audio focus). Every failure is reported to
/// [onError] and swallowed — sound can never crash or stall the game — and
/// playing a file that has not finished preloading is a silent no-op. A
/// fourth rapid play of the same sound restarts the oldest of its three
/// players (round-robin), cutting that one off; see `tools/sfx/build_sfx.py`
/// (`MAX_CLIP_S`) for why every bundled clip is kept short enough that this
/// is never noticeable in practice.
class AudioplayersSoundSink implements SoundSink {
  AudioplayersSoundSink({void Function(Object error)? onError})
    : _onError = onError ?? _debugLog;

  static const int _playersPerSound = 3;

  static final AudioContext _context = AudioContext(
    android: const AudioContextAndroid(
      usageType: AndroidUsageType.game,
      contentType: AndroidContentType.sonification,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  final void Function(Object error) _onError;
  final Map<String, List<AudioPlayer>> _players = <String, List<AudioPlayer>>{};
  final Map<String, int> _next = <String, int>{};

  bool isLoaded(String asset) => _players.containsKey(asset);

  @override
  Future<void> preload(List<String> assets) async {
    try {
      await AudioPlayer.global.setAudioContext(_context);
    } catch (error) {
      _onError(error);
    }
    for (final String asset in assets) {
      try {
        final List<AudioPlayer> players = <AudioPlayer>[];
        for (int i = 0; i < _playersPerSound; i++) {
          final AudioPlayer player = AudioPlayer()..positionUpdater = null;
          await player.setPlayerMode(PlayerMode.lowLatency);
          await player.setAudioContext(_context);
          await player.setReleaseMode(ReleaseMode.stop);
          await player.setSource(AssetSource(asset));
          players.add(player);
        }
        _players[asset] = players;
        _next[asset] = 0;
      } catch (error) {
        _onError(error);
      }
    }
  }

  @override
  void play(String asset, double volume) {
    final List<AudioPlayer>? players = _players[asset];
    if (players == null) {
      return;
    }
    final int index = _next[asset]!;
    _next[asset] = (index + 1) % players.length;
    unawaited(_restart(players[index], volume));
  }

  Future<void> _restart(AudioPlayer player, double volume) async {
    try {
      await player.stop();
      await player.setVolume(volume);
      await player.resume();
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
