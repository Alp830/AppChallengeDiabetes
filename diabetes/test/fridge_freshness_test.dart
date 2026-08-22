import 'package:diabetes/fridge/freshness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 7, 21, 10);

  test('null expiry is unknown', () {
    expect(freshnessFor(null, now: now), Freshness.unknown);
  });

  test('past expiry is expired', () {
    expect(
      freshnessFor(DateTime(2026, 7, 20), now: now),
      Freshness.expired,
    );
  });

  test('expiry today is expiring soon', () {
    expect(
      freshnessFor(DateTime(2026, 7, 21, 23), now: now),
      Freshness.expiringSoon,
    );
  });

  test('expiry within threshold is expiring soon', () {
    expect(
      freshnessFor(DateTime(2026, 7, 23), now: now),
      Freshness.expiringSoon,
    );
  });

  test('expiry beyond threshold is fresh', () {
    expect(
      freshnessFor(DateTime(2026, 7, 24), now: now),
      Freshness.fresh,
    );
  });
}
