import 'package:flutter/material.dart';

/// Freshness status derived from an item's expiry date.
///
/// This is the single source of truth for the status label and colour shown on
/// a fridge item card. Colours are chosen for AAA high-contrast against a light
/// surface, per the accessibility mandate in Design Spec V3.
enum Freshness {
  expired('Expired', Color(0xFFB00020)),
  expiringSoon('Expiring Soon', Color(0xFF8A5A00)),
  fresh('Fresh', Color(0xFF1B5E20)),
  unknown('No date', Color(0xFF49454F));

  const Freshness(this.label, this.color);

  /// Human-readable status shown on the card.
  final String label;

  /// AAA-contrast foreground colour for the status text.
  final Color color;

  /// Soft tinted fill used behind icon chips and status pills, echoing the
  /// colored-chip style of the reference nutrition apps.
  Color get tint => color.withValues(alpha: 0.12);
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
