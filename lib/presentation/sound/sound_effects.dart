import 'sound_cue.dart';

/// What the bloc talks to. Fire-and-forget: playing never blocks or fails.
abstract class SoundEffects {
  void play(SoundCue cue);
}

/// The default — used by tests and anywhere no sound is wired in.
class SilentSoundEffects implements SoundEffects {
  const SilentSoundEffects();

  @override
  void play(SoundCue cue) {}
}
