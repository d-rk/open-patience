/// Whether the "Test win" debug trigger should be shown.
///
/// True for any local debug build ([debugMode], e.g. a plain `flutter run`
/// with no flavor) or the Testing-channel release build. [flavor] is
/// compared case-insensitively: Android's Flutter Gradle plugin sets
/// `appFlavor` to the exact AGP product-flavor name, which is `"Testing"`
/// (capital T — AGP rejects a flavor starting with lowercase `test`; see
/// android/app/build.gradle.kts), while other platforms propagate the
/// lowercase `--flavor` CLI string as-is.
bool shouldShowDebugDeals({required bool debugMode, String? flavor}) {
  return debugMode || flavor?.toLowerCase() == 'testing';
}
