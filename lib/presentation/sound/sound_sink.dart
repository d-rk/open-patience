/// The platform audio seam: plays bundled files by asset path (relative to
/// `assets/`, e.g. `sounds/place_1.ogg`).
abstract class SoundSink {
  Future<void> preload(List<String> assets);

  void play(String asset, double volume);
}
