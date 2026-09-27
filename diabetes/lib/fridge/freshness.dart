/// Freshness status derived from an item's expiry date.
///
/// Single source of truth for the status label on a fridge card. Colors live
/// in [AppStatusColors] on the theme.
enum Freshness {
  expired('Expired'),
  expiringSoon('Expiring soon'),
  fresh('Fresh'),
  unknown('No date');

  const Freshness(this.label);

  /// Human-readable status shown on the card.
  final String label;
}

/// Number of days before expiry within which an item is "Expiring Soon".
const int kExpiringSoonThresholdDays = 2;

/// Computes the [Freshness] for an [expiry] date.
///
/// [now] is injectable so widgets and tests can pin the reference time. A null
/// [expiry] yields [Freshness.unknown]. Comparison is done on calendar days so
/// an item expiring later today still counts as expiring, not expired.
Freshness freshnessFor(DateTime? expiry, {DateTime? now}) {
  if (expiry == null) {
    return Freshness.unknown;
  }

  final reference = now ?? DateTime.now();
  final today = DateTime(reference.year, reference.month, reference.day);
  final expiryDay = DateTime(expiry.year, expiry.month, expiry.day);
  final daysLeft = expiryDay.difference(today).inDays;

  if (daysLeft < 0) {
    return Freshness.expired;
  }
  if (daysLeft <= kExpiringSoonThresholdDays) {
    return Freshness.expiringSoon;
  }
  return Freshness.fresh;
}
