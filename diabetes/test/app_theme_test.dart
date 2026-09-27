import 'package:diabetes/design/app_status_colors.dart';
import 'package:diabetes/design/app_theme.dart';
import 'package:diabetes/fridge/freshness.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/contrast.dart';

void main() {
  final theme = AppTheme.light();
  final scheme = theme.colorScheme;

  test('primary and secondary pairs meet WCAG AA 4.5:1', () {
    expect(
      contrast(scheme.primary, scheme.onPrimary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(scheme.secondary, scheme.onSecondary),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(scheme.secondaryContainer, scheme.onSecondaryContainer),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('secondary family is warm apricot, not seeded mint', () {
    expect(scheme.secondaryContainer, const Color(0xFFFFDCC0));
  });

  test('enabled input border meets 3:1 non-text contrast on white', () {
    final border =
        theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
    expect(
      contrast(border.borderSide.color, Colors.white),
      greaterThanOrEqualTo(3),
    );
  });

  test('page is surfaceContainerLow so white cards separate by tone', () {
    expect(theme.scaffoldBackgroundColor, scheme.surfaceContainerLow);
  });

  test('freshness colors come from the theme extension', () {
    final status = theme.extension<AppStatusColors>()!;
    expect(status.forFreshness(Freshness.expired), const Color(0xFFB00020));
  });
}
