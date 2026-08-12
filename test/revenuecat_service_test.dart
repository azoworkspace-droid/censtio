import 'package:flutter_test/flutter_test.dart';

import 'package:freelancer/services/revenuecat_service.dart';

void main() {
  test(
    'free creation gate allows three records and blocks the fourth',
    () async {
      expect(await RevenueCatService.hasReachedFreeLimit(0), isFalse);
      expect(await RevenueCatService.hasReachedFreeLimit(2), isFalse);
      expect(await RevenueCatService.hasReachedFreeLimit(3), isTrue);
    },
  );
}
