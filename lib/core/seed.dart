import 'dart:math';

/// Upper bound (exclusive) for a deal seed.
///
/// Must be valid for [Random.nextInt], whose argument has to satisfy
/// `0 < max <= 2^32`. Crucially it is written as `1 << 30`, **not** `1 << 32`:
/// on the web (dart2js) integers are 32-bit for shift operations, so `1 << 32`
/// truncates to `0`, and `Random().nextInt(0)` throws `RangeError`. That
/// exception, raised inside a button's `onPressed`, is swallowed by Flutter's
/// gesture zone — which is exactly how the "Play" button silently did nothing
/// on the web build while working on Android (64-bit ints). `1 << 30` is safe
/// on both platforms and still yields ~1e9 distinct deals.
const int maxSeedExclusive = 1 << 30;

/// A fresh, web-safe deal seed drawn from [random] (defaults to global
/// randomness). Always use this instead of `nextInt(1 << 32)`.
int randomSeed([Random? random]) =>
    (random ?? Random()).nextInt(maxSeedExclusive);
