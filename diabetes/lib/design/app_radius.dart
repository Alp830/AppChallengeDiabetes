/// Corner-radius tokens, mapped to M3's shape scale. Use these instead of
/// literal radii so every surface of the same kind matches.
abstract class AppRadius {
  /// Images and small marks inside cards.
  static const double sm = 8;

  /// Buttons, fields, chips, info pills, icon tiles, snackbars.
  static const double md = 12;

  /// Cards, fridge tiles, banners.
  static const double lg = 16;

  /// Bottom sheets and dialogs.
  static const double xl = 24;

  /// Fully rounded (status pills).
  static const double full = 999;
}
