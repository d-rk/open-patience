import 'dart:async';
import 'dart:math';

import '../../persistence/settings_repository.dart';
import 'sound_cue.dart';
import 'sound_effects.dart';
import 'sound_sink.dart';

/// Turns [SoundCue]s into files for a [SoundSink]: honors the player's mute
/// setting (read live, per sound), picks a random variant so repeats don't
/// sound mechanical, sets each cue's volume, drops a same-cue repeat inside
/// [repeatWindow], and delays [SoundCue.flip] by [flipDelay] so a revealed
/// card is heard just after the landing.
class SoundBoard implements SoundEffects {
  SoundBoard({
    required SoundSink sink,
    required SettingsRepository settings,
    Random? random,
    DateTime Function()? clock,
  }) : _sink = sink,
       _settings = settings,
       _random = random ?? Random(),
       _clock = clock ?? DateTime.now;

  static const Duration repeatWindow = Duration(milliseconds: 60);
  static const Duration flipDelay = Duration(milliseconds: 120);

  static const Map<SoundCue, List<String>> _assets = <SoundCue, List<String>>{
    SoundCue.place: <String>[
      'sounds/place_1.ogg',
      'sounds/place_2.ogg',
      'sounds/place_3.ogg',
      'sounds/place_4.ogg',
    ],
    SoundCue.foundation: <String>[
      'sounds/foundation_1.ogg',
      'sounds/foundation_2.ogg',
    ],
    SoundCue.draw: <String>[
      'sounds/draw_1.ogg',
      'sounds/draw_2.ogg',
      'sounds/draw_3.ogg',
    ],
    SoundCue.flip: <String>['sounds/flip.ogg'],
    SoundCue.illegal: <String>['sounds/illegal.ogg'],
    SoundCue.undo: <String>['sounds/undo_1.ogg', 'sounds/undo_2.ogg'],
    SoundCue.deal: <String>['sounds/deal.ogg'],
    SoundCue.win: <String>['sounds/win.ogg'],
  };

  static const Map<SoundCue, double> _volumes = <SoundCue, double>{
    SoundCue.illegal: 0.5,
    SoundCue.flip: 0.6,
    SoundCue.undo: 0.6,
  };

  final SoundSink _sink;
  final SettingsRepository _settings;
  final Random _random;
  final DateTime Function() _clock;
  final Map<SoundCue, DateTime> _lastPlayed = <SoundCue, DateTime>{};

  /// Every file any cue can play — what the sink preloads.
  static List<String> get allAssets => <String>[
    for (final List<String> files in _assets.values) ...files,
  ];

  static List<String> assetsFor(SoundCue cue) => _assets[cue]!;

  static double volumeFor(SoundCue cue) => _volumes[cue] ?? 1.0;

  @override
  void play(SoundCue cue) {
    if (cue == SoundCue.flip) {
      Timer(flipDelay, () => _playNow(cue));
      return;
    }
    _playNow(cue);
  }

  void _playNow(SoundCue cue) {
    if (!_settings.soundEnabled) {
      return;
    }
    final DateTime now = _clock();
    final DateTime? last = _lastPlayed[cue];
    if (last != null && now.difference(last) < repeatWindow) {
      return;
    }
    _lastPlayed[cue] = now;
    final List<String> files = _assets[cue]!;
    _sink.play(files[_random.nextInt(files.length)], volumeFor(cue));
  }
}
