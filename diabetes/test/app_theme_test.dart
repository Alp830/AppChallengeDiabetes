import 'package:diabetes/design/app_radius.dart';
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

  test('sheets get a drag handle from the theme', () {
    expect(theme.bottomSheetTheme.showDragHandle, isTrue);
  });

  test('app bars use the platform title alignment', () {
    expect(theme.appBarTheme.centerTitle, isNull);
  });

  test('cards use the large radius token', () {
    final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(AppRadius.lg));
  });

  test('whole text theme uses the bundled family with explicit weights', () {
    final t = theme.textTheme;
    expect(t.bodyMedium!.fontFamily, 'AtkinsonHyperlegibleNext');
    for (final style in [
      t.titleSmall,
      t.labelLarge,
      t.labelMedium,
      t.labelSmall,
    ]) {
      expect(style!.fontWeight, FontWeight.w600);
    }
    expect(t.displaySmall!.fontWeight, FontWeight.w700);
  });
}
