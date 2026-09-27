import 'package:flutter/material.dart';

import '../fridge/freshness.dart';

/// Status colors that have no M3 role (fridge freshness today). They live on
/// the theme so the whole palette is defined in one place. Each color is
/// ≥5:1 against its own 12% tint (WCAG AA).
@immutable
class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.expired,
    required this.expiringSoon,
    required this.fresh,
    required this.unknown,
  });

  static const standard = AppStatusColors(
    expired: Color(0xFFB00020),
    expiringSoon: Color(0xFF8A5A00),
    fresh: Color(0xFF1B5E20),
    unknown: Color(0xFF49454F),
  );

  final Color expired;
  final Color expiringSoon;
  final Color fresh;
  final Color unknown;

  /// The theme's status colors, or [standard] when a test pumps without
  /// [AppTheme].
  static AppStatusColors of(BuildContext context) =>
      Theme.of(context).extension<AppStatusColors>() ?? standard;

  /// Soft fill behind status icons and pills.
  static Color tint(Color color) => color.withValues(alpha: 0.12);

  Color forFreshness(Freshness freshness) => switch (freshness) {
    Freshness.expired => expired,
    Freshness.expiringSoon => expiringSoon,
    Freshness.fresh => fresh,
    Freshness.unknown => unknown,
  };

  @override
  AppStatusColors copyWith({
    Color? expired,
    Color? expiringSoon,
    Color? fresh,
    Color? unknown,
  }) => AppStatusColors(
    expired: expired ?? this.expired,
    expiringSoon: expiringSoon ?? this.expiringSoon,
    fresh: fresh ?? this.fresh,
    unknown: unknown ?? this.unknown,
  );

  @override
  AppStatusColors lerp(AppStatusColors? other, double t) {
    if (other == null) return this;
    return AppStatusColors(
      expired: Color.lerp(expired, other.expired, t)!,
      expiringSoon: Color.lerp(expiringSoon, other.expiringSoon, t)!,
      fresh: Color.lerp(fresh, other.fresh, t)!,
      unknown: Color.lerp(unknown, other.unknown, t)!,
    );
  }
}
