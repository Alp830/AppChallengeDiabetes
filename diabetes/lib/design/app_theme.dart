import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_radius.dart';
import 'app_status_colors.dart';

/// Central design system for the Wellness Companion app.
///
/// Every screen inherits from this single [ThemeData], so visual polish added
/// here (rounded cards, soft borders, consistent typography, pill buttons)
/// cascades across the whole app without touching individual widgets.
abstract class AppTheme {
  // Brand palette — a fresh, health-forward green with warm neutral surfaces.
  // [_seed] fails AA under white text (3.99:1), so it only seeds the scheme;
  // [_primary] is the same hue at 5.23:1.
  static const Color _seed = Color(0xFF2F8F6B);
  static const Color _primary = Color(0xFF267A5B);

  /// Deep brand green for gradient ends and text buttons (6.42:1 on white).
  static const Color brandDark = Color(0xFF1F6B4E);

  // Warm apricot secondary, overridden as a whole family so tonal components
  // (nav indicator, tonal buttons) actually show it. Every pair is ≥5:1.
  static const Color _secondary = Color(0xFFA15C0E);
  static const Color _secondaryContainer = Color(0xFFFFDCC0);
  static const Color _onSecondaryContainer = Color(0xFF3A1D00);

  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _ink = Color(0xFF1B241F);
  static const Color _muted = Color(0xFF63706A);
  static const Color _hairline = Color(0xFFE4E9E4);

  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.light,
        ).copyWith(
          primary: _primary,
          onPrimary: Colors.white,
          secondary: _secondary,
          onSecondary: Colors.white,
          secondaryContainer: _secondaryContainer,
          onSecondaryContainer: _onSecondaryContainer,
          surface: _surface,
          onSurface: _ink,
          onSurfaceVariant: _muted,
          outlineVariant: _hairline,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'AtkinsonHyperlegibleNext',
      scaffoldBackgroundColor: scheme.surfaceContainerLow,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      extensions: const [AppStatusColors.standard],
    );

    TextStyle? weight(TextStyle? style, FontWeight w, [double? tracking]) =>
        style?.copyWith(fontWeight: w, letterSpacing: tracking);
    final t = base.textTheme.apply(bodyColor: _ink, displayColor: _ink);
    final text = t.copyWith(
      displayLarge: weight(t.displayLarge, FontWeight.w700),
      displayMedium: weight(t.displayMedium, FontWeight.w700),
      displaySmall: weight(t.displaySmall, FontWeight.w700),
      headlineLarge: weight(t.headlineLarge, FontWeight.w700),
      headlineMedium: weight(t.headlineMedium, FontWeight.w700),
      headlineSmall: weight(t.headlineSmall, FontWeight.w700, -0.4),
      titleLarge: weight(t.titleLarge, FontWeight.w700, -0.2),
      titleMedium: weight(t.titleMedium, FontWeight.w600),
      titleSmall: weight(t.titleSmall, FontWeight.w600),
      bodyLarge: weight(t.bodyLarge, FontWeight.w400),
      bodyMedium: weight(t.bodyMedium, FontWeight.w400),
      bodySmall: weight(t.bodySmall, FontWeight.w400),
      labelLarge: weight(t.labelLarge, FontWeight.w600),
      labelMedium: weight(t.labelMedium, FontWeight.w600),
      labelSmall: weight(t.labelSmall, FontWeight.w600),
    );

    return base.copyWith(
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surfaceContainerLow,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: _hairline),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: _hairline,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 52),
          elevation: 0,
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          foregroundColor: brandDark,
          side: const BorderSide(color: _hairline),
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brandDark,
          textStyle: text.labelLarge,
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 2,
        highlightElevation: 4,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: _surface,
        side: const BorderSide(color: _hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        labelStyle: text.labelLarge,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: _primary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: _primary, width: 2),
        ),
        labelStyle: const TextStyle(color: _muted),
        hintStyle: const TextStyle(color: _muted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _ink,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: _surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
    );
  }
}
