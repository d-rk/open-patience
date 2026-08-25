import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/core/seed.dart';

void main() {
  group('randomSeed', () {
    test('bound is web-safe: positive and strictly below 2^32', () {
      // On dart2js `1 << 32` truncates to 0, so `Random().nextInt(1 << 32)`
      // throws RangeError and silently kills any "new deal" tap on web. The
      // bound must therefore be a value that is valid on *both* platforms:
      // greater than zero and no larger than 2^32.
      expect(maxSeedExclusive, greaterThan(0));
      expect(maxSeedExclusive, lessThanOrEqualTo(4294967296)); // 2^32
      // And it must carry real entropy, not collapse to a tiny range.
      expect(maxSeedExclusive, greaterThanOrEqualTo(1 << 20));
    });

    test('returns a value within [0, maxSeedExclusive)', () {
      final Random random = Random(12345);
      for (int i = 0; i < 1000; i++) {
        final int seed = randomSeed(random);
        expect(seed, greaterThanOrEqualTo(0));
        expect(seed, lessThan(maxSeedExclusive));
      }
    });

    test('is deterministic for a seeded Random', () {
      expect(randomSeed(Random(7)), randomSeed(Random(7)));
    });
  });
}
