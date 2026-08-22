/// Base-8 spacing tokens for the Fridge Agent UI.
///
/// Design Spec V3 mandates a strict base-8 spacing system with 16px as the
/// standard gutter/margin. Keeping these as named constants (rather than the
/// inline literals used elsewhere in the app) makes the mandate explicit and
/// keeps the new Fridge widgets consistent.
abstract class Spacing {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s24 = 24;
  static const double s32 = 32;

  /// 16px gutter between grid columns/rows, per the 4-column mobile grid.
  static const double gutter = s16;

  /// 16px side margin around the content grid.
  static const double margin = s16;

  /// 12px internal padding required inside each item card.
  static const double cardPadding = s12;
}
