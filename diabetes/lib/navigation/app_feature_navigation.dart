import 'package:flutter/material.dart';

/// Navigation helpers for build-time product capabilities.
///
/// Callers should also hide disabled controls. This guard prevents a stale or
/// indirect callback from pushing a diabetes-only route in a dieting build.
abstract final class AppFeatureNavigation {
  static Future<T?> pushDiabetesPage<T>(
    BuildContext context, {
    required bool diabetesEnabled,
    required WidgetBuilder builder,
  }) {
    if (!diabetesEnabled) {
      return Future<T?>.value();
    }

    return Navigator.of(
      context,
    ).push<T>(MaterialPageRoute<T>(builder: builder));
  }
}
