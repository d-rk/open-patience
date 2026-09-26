import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/persistence/settings_repository.dart';
import 'package:open_patience/presentation/sound/sound_board.dart';
import 'package:open_patience/presentation/sound/sound_cue.dart';
import 'package:open_patience/presentation/sound/sound_sink.dart';

class _Sink implements SoundSink {
  final List<(String, double)> played = <(String, double)>[];

  @override
  Future<void> preload(List<String> assets) async {}

  @override
  void play(String asset, double volume) => played.add((asset, volume));
}

class _Settings implements SettingsRepository {
  @override
  bool soundEnabled = true;

  @override
  Future<void> setSoundEnabled(bool enabled) async => soundEnabled = enabled;
}

void main() {
  late _Sink sink;
  late _Settings settings;
  late DateTime now;
  late SoundBoard board;

  setUp(() {
    sink = _Sink();
    settings = _Settings();
    now = DateTime(2026, 9, 26);
    board = SoundBoard(
      sink: sink,
      settings: settings,
      random: Random(1),
      clock: () => now,
    );
  });

  test('each cue plays one of its own files at its volume', () {
    for (final SoundCue cue in SoundCue.values.where(
      (SoundCue c) => c != SoundCue.flip,
    )) {
      sink.played.clear();
      board.play(cue);
      expect(sink.played, hasLength(1), reason: '$cue');
      expect(SoundBoard.assetsFor(cue), contains(sink.played.single.$1));
      expect(sink.played.single.$2, SoundBoard.volumeFor(cue));
    }
  });

  test('quiet cues are quieter', () {
    expect(SoundBoard.volumeFor(SoundCue.illegal), 0.5);
    expect(SoundBoard.volumeFor(SoundCue.flip), 0.6);
    expect(SoundBoard.volumeFor(SoundCue.undo), 0.6);
    expect(SoundBoard.volumeFor(SoundCue.win), 1.0);
  });

  test('place rotates through its variants', () {
    final Set<String> heard = <String>{};
    for (int i = 0; i < 40; i++) {
      now = now.add(const Duration(seconds: 1));
      board.play(SoundCue.place);
      heard.add(sink.played.last.$1);
    }
    expect(heard.length, greaterThan(1));
  });

  test('muted plays nothing', () {
    settings.soundEnabled = false;
    board.play(SoundCue.deal);
    expect(sink.played, isEmpty);
  });

  test('unmuting takes effect for the very next cue', () {
    settings.soundEnabled = false;
    board.play(SoundCue.place);
    settings.soundEnabled = true;
    board.play(SoundCue.place);
    expect(sink.played, hasLength(1));
  });

  test('a repeat of the same cue within 60 ms is dropped', () {
    board.play(SoundCue.foundation);
    now = now.add(const Duration(milliseconds: 59));
    board.play(SoundCue.foundation);
    expect(sink.played, hasLength(1));
    now = now.add(const Duration(milliseconds: 1));
    board.play(SoundCue.foundation);
    expect(sink.played, hasLength(2));
  });

  test('different cues are not throttled against each other', () {
    board.play(SoundCue.place);
    board.play(SoundCue.undo);
    expect(sink.played, hasLength(2));
  });

  test('flip trails by 120 ms', () {
    fakeAsync((FakeAsync async) {
      board.play(SoundCue.flip);
      async.elapse(const Duration(milliseconds: 119));
      expect(sink.played, isEmpty);
      async.elapse(const Duration(milliseconds: 1));
      expect(sink.played.single.$1, 'sounds/flip.ogg');
    });
  });

  test('muting while a flip is pending silences it', () {
    fakeAsync((FakeAsync async) {
      board.play(SoundCue.flip);
      settings.soundEnabled = false;
      async.elapse(SoundBoard.flipDelay);
      expect(sink.played, isEmpty);
    });
  });

  test('allAssets lists every file of every cue exactly once', () {
    final List<String> all = SoundBoard.allAssets;
    expect(all.toSet().length, all.length);
    for (final SoundCue cue in SoundCue.values) {
      expect(all, containsAll(SoundBoard.assetsFor(cue)));
    }
  });
}
