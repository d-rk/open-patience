import 'package:flutter_test/flutter_test.dart';
import 'package:open_patience/ui/debug_deals.dart';

void main() {
  group('shouldShowDebugDeals', () {
    test('true in debug mode regardless of flavor', () {
      expect(shouldShowDebugDeals(debugMode: true, flavor: null), isTrue);
      expect(
        shouldShowDebugDeals(debugMode: true, flavor: 'production'),
        isTrue,
      );
    });

    test('true in release mode when the flavor is Testing (any case)', () {
      expect(shouldShowDebugDeals(debugMode: false, flavor: 'Testing'), isTrue);
      expect(shouldShowDebugDeals(debugMode: false, flavor: 'testing'), isTrue);
    });

    test('false in release mode for production or a missing flavor', () {
      expect(
        shouldShowDebugDeals(debugMode: false, flavor: 'production'),
        isFalse,
      );
      expect(shouldShowDebugDeals(debugMode: false, flavor: null), isFalse);
    });
  });
}
