# UI Refresh Implementation Plan

> **REQUIRED SUB-SKILL:** Use the executing-plans skill to implement this plan task-by-task.

**Goal:** Refresh the Wellness Companion Flutter UI (meal tracker, Agent, Fridge, Home) so it meets Material 3 (M3) and WCAG AA practice without rebranding it.

**Architecture:** Theme-level tokens come first (color, shape, spacing, motion, type in `lib/design/`), then screens are rebuilt on those tokens one at a time, each change locked in with a widget test. Screens stay in their current files, and only small new helpers and widgets are added under `lib/design/` and `lib/fridge/`.

**Tech Stack:** Flutter 3.44.6 / Dart 3.12, Material 3 light theme only, Firebase Auth + Firestore, `flutter_test`. The only new asset is the Atkinson Hyperlegible Next font (bundled, no new package).

---

## Read this first (context for a fresh session)

**App:** a mobile wellness companion. You photograph your fridge, the app detects the foods, and Gemini suggests meals. The shell (`MainPage` in `lib/main.dart`) has three tabs: Fridge (`FridgePage`), Home (`MvpHomePage` in `lib/home/mvp_home_page.dart`) and Agent (`AgentPage` + `MealRecommendationCard`), plus a pushed meal log form (`MealLogPage` in `lib/meals/screens/meal_log_page.dart`). There are two build modes:
- dieting (default): `flutter run -d chrome`
- diabetes: `flutter run -d chrome --dart-define=DIABETES_ENABLED=true`

Every visual check below must look right in **both**.

**Working directory:** `C:\AppChallengeDiabetes\diabetes` (git root is the parent folder, so run `git` from `diabetes/` with relative paths). The shell is bash on Windows.

**Baseline (verified 2026-09-26):** `flutter test` shows 146 passing, and `flutter analyze` reports "No issues found!". Keep both green after every task.

**Scope rules:**
- Only touch the Fridge, Home, Agent/recipe card, Auth and meal log surfaces. **Do not** change diabetes/sleep-only (D/S) screens (`lib/cgm`, `lib/sleep`, `lib/exercise`, `meal_lab_page.dart`, `meal_balance_page.dart`) except where a task explicitly says so (Task 4 only).
- **Do not** touch `AppEnvironment`, `.env` or the Gemini key handling. That security issue is tracked separately and is out of scope.
- `lib/main.dart` is 3,971 lines. Line numbers below are approximate, so locate code by the quoted class/method/string.
- Match existing style: `///` doc comments on classes, `Spacing.*` tokens, `const` wherever possible, and the `dart format` layout. Run `dart format <touched files>` before each commit.

**Visual check procedure** (the "Run the app" step in each task): run both commands above, sign in, and look at the named screen. Where a task says "screenshot", save it to your own scratch folder (not the repo) so the user can compare before and after.

**Traceability (research doc `## Applications to App` item → task):**

| Item | Tasks |
|---|---|
| 1 Color foundation | 1, 2 |
| 2 Labeled nav + account sheet | 6 |
| 3 Delete 28 border overrides | 4 |
| 4 Plain errors + Retry | 5, 6, 7, 8, 13 |
| 5 Stream, fake delay, scan progress | 6, 7, 8 |
| 6 Fridge empty state + Auth | 9, 11 |
| 7 Fridge action layout | 10 |
| 8 Recipe card | 12 |
| 9 Type system | 3, 13 |
| 10 Home | 13 |
| 11 Large text | 14 |
| 12 Meal log form | 15 |
| 13 Tokens / normalize | 2, 16 |
| 14 Copy pass | 7, 12, 17 |
| 15 Motion | 2, 6 |
| 16 D/S fixes | not in this plan |

---

### Task 1: Color foundation (`AppTheme.light()` + status-color extension)

**Files:**
- Create: `lib/design/app_status_colors.dart`, `test/support/contrast.dart`, `test/app_theme_test.dart`
- Modify: `lib/design/app_theme.dart` (palette constants + `light()`), `lib/fridge/freshness.dart` (enum drops colors), `lib/fridge/fridge_item_card.dart` (`build`)

**Step 1: Write the failing tests**

`test/support/contrast.dart`:
```dart
import 'package:flutter/painting.dart';

/// WCAG 2.x contrast ratio between two opaque colors.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
```

`test/app_theme_test.dart`:
```dart
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
    expect(contrast(scheme.primary, scheme.onPrimary), greaterThanOrEqualTo(4.5));
    expect(contrast(scheme.secondary, scheme.onSecondary), greaterThanOrEqualTo(4.5));
    expect(
      contrast(scheme.secondaryContainer, scheme.onSecondaryContainer),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('secondary family is warm apricot, not seeded mint', () {
    expect(scheme.secondaryContainer, const Color(0xFFFFDCC0));
  });

  test('enabled input border meets 3:1 non-text contrast on white', () {
    final border = theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
    expect(contrast(border.borderSide.color, Colors.white), greaterThanOrEqualTo(3));
  });

  test('page is surfaceContainerLow so white cards separate by tone', () {
    expect(theme.scaffoldBackgroundColor, scheme.surfaceContainerLow);
  });

  test('freshness colors come from the theme extension', () {
    final status = theme.extension<AppStatusColors>()!;
    expect(status.forFreshness(Freshness.expired), const Color(0xFFB00020));
  });
}
```

**Step 2: Run to verify failure**

Run: `flutter test test/app_theme_test.dart`
Expected: compile FAIL (`app_status_colors.dart` not found).

**Step 3: Implement**

`lib/design/app_status_colors.dart`:
```dart
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
```

`lib/fridge/freshness.dart`: change the enum so it holds labels only (colors moved to the extension), and fix the "AAA" claim:
```dart
/// Freshness status derived from an item's expiry date.
///
/// Single source of truth for the status label on a fridge card. Colors live
/// in [AppStatusColors] on the theme.
enum Freshness {
  expired('Expired'),
  expiringSoon('Expiring Soon'),
  fresh('Fresh'),
  unknown('No date');

  const Freshness(this.label);

  /// Human-readable status shown on the card.
  final String label;
}
```
(Delete the `color` field, the `tint` getter and the now-unused `package:flutter/material.dart` import. Leave `kExpiringSoonThresholdDays` and `freshnessFor` unchanged.)

`lib/design/app_theme.dart`:
1. Add `import 'app_status_colors.dart';`.
2. Replace the palette block (`_brand` … `_hairline`) with:
```dart
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
```
3. In `light()`, set the scheme to `ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.light).copyWith(primary: _primary, onPrimary: Colors.white, secondary: _secondary, onSecondary: Colors.white, secondaryContainer: _secondaryContainer, onSecondaryContainer: _onSecondaryContainer, surface: _surface, onSurface: _ink, onSurfaceVariant: _muted, outlineVariant: _hairline)`.
4. In `ThemeData(...)`: set `scaffoldBackgroundColor: scheme.surfaceContainerLow` and add `extensions: const [AppStatusColors.standard]`.
5. Make these replacements:
   - `AppBarTheme.backgroundColor` → `scheme.surfaceContainerLow`
   - every `_brandDark` → `brandDark`
   - `ElevatedButton.styleFrom(backgroundColor: _brand` → `_primary`
   - `FloatingActionButtonThemeData(backgroundColor: _brand` → `_primary`
   - `ListTileThemeData(iconColor: _brand` → `_primary`
   - `focusedBorder` side `_brand` → `_primary`
6. In `InputDecorationTheme`, set both `border` and `enabledBorder` to `BorderSide(color: scheme.outline)` (drop `const`). `scheme.outline` is #707973, 4.5:1 on white.

`lib/fridge/fridge_item_card.dart` → `FridgeItemCard.build`: add `import '../design/app_status_colors.dart';`, then after `final freshness = ...` add
```dart
    final statusColor = AppStatusColors.of(context).forFreshness(freshness);
    final statusTint = AppStatusColors.tint(statusColor);
```
and replace every `freshness.tint` with `statusTint` and every `freshness.color` with `statusColor`.

**Step 4: Run tests**

Run: `flutter test test/app_theme_test.dart test/fridge_item_card_test.dart test/fridge_freshness_test.dart && flutter analyze`
Expected: all PASS, no issues.

**Step 5: Verify visually.** Run the app in both modes and screenshot Home, Fridge and Agent. Filled buttons and the Home banner are a slightly deeper green, the page background is pale sage behind white cards, and text-field outlines are clearly visible on the Agent prompt.

**Step 6: Commit**
```bash
git add lib/design/app_status_colors.dart lib/design/app_theme.dart lib/fridge/freshness.dart lib/fridge/fridge_item_card.dart test/support/contrast.dart test/app_theme_test.dart
git commit -m "feat(theme): AA primary, full apricot secondary, visible inputs, status color extension"
```

---

### Task 2: Shape, spacing, motion and component tokens

**Files:**
- Create: `lib/design/app_radius.dart`, `lib/design/app_motion.dart`
- Modify: `lib/design/spacing.dart`, `lib/design/app_theme.dart` (`light()`), `lib/main.dart` (`_AgentPageState._showPreferences`), `lib/meals/screens/meal_qa_sheet.dart` (`showMealQaSheet`)
- Test: `test/app_theme_test.dart`

**Step 1: Write the failing tests** (append to `main()` in `test/app_theme_test.dart`, and add `import 'package:diabetes/design/app_radius.dart';`)
```dart
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
```

**Step 2: Run** `flutter test test/app_theme_test.dart`. Expected: FAIL (`app_radius.dart` not found).

**Step 3: Implement**

`lib/design/app_radius.dart`:
```dart
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
```

`lib/design/app_motion.dart`:
```dart
import 'package:flutter/material.dart';

/// M3 motion tokens (easing and duration pairs). Keep durations here so no
/// widget invents its own magic number.
abstract class AppMotion {
  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 300);

  /// Cross-fade used instead of slides when Reduce Motion is on.
  static const Duration reducedFade = Duration(milliseconds: 150);

  static const Curve enter = Easing.emphasizedDecelerate;
  static const Curve exit = Easing.emphasizedAccelerate;
}
```

`lib/design/spacing.dart`: add below `s32`:
```dart
  /// Gap between unrelated sections of a screen.
  static const double section = s24;
```
Then add this mapping rule to the class doc comment: "Off-grid literals map as 20/28 → s24 between sections or s16 inside a component, 10 → s8 or s12, 6 → s8 (s4 between an icon and its label), and 1–3 → s4 or remove."

`lib/design/app_theme.dart` → `light()`:
- `import 'app_radius.dart';`. Delete the now-unused `static const double radius = 18;` (nothing outside this file references it; confirm with `grep -rn "AppTheme.radius" lib test`).
- `AppBarTheme`: remove `centerTitle: true`.
- Radii:
  - `CardThemeData` → `AppRadius.lg`
  - filled/elevated/outlined button shapes (currently 14) → `AppRadius.md`
  - all three input borders → `AppRadius.md`
  - chip → `AppRadius.md`
  - snackbar → `AppRadius.md`
  - bottom sheet (`Radius.circular(24)`) → `AppRadius.xl`
  - dialog → `AppRadius.xl`
- `BottomSheetThemeData`: add `showDragHandle: true`.
- Add a navigation bar theme (consumed in Task 6):
```dart
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
```
- Add page transitions (fade-forwards on Android/desktop, keeping iOS swipe-back):
```dart
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
```

Remove the per-call `showDragHandle: true` from `_AgentPageState._showPreferences` (`lib/main.dart`) and from `showMealQaSheet` (`lib/meals/screens/meal_qa_sheet.dart`). The theme covers them now. Leave `meal_lab_page.dart` untouched (D/S).

**Step 4: Run** `flutter test && flutter analyze`. Expected: all PASS (146 + 8 new), no issues.

**Step 5: Verify visually.** Every bottom sheet (Add food, camera, Preferences) shows a drag handle, and pushed pages ("Log meal") have left-aligned titles on Android/web. Opening "Log meal" fades forward instead of sliding.

**Step 6: Commit**
```bash
git add lib/design test/app_theme_test.dart lib/main.dart lib/meals/screens/meal_qa_sheet.dart
git commit -m "feat(theme): radius, motion, section spacing, drag handle and nav bar tokens"
```

---

### Task 3: Type system (Atkinson Hyperlegible Next, all 15 roles styled)

Atkinson Hyperlegible Next is designed so commonly confused glyphs (1/l/I, 0/O) stay distinct, which matters for quantities, prices and glucose values when many users have diabetic retinopathy. It is bundled rather than fetched at runtime so it works offline and on web.

**Files:**
- Create: `assets/fonts/` (4 TTFs + `OFL.txt`)
- Modify: `pubspec.yaml`, `lib/main.dart` (`main()`, `_HeaderTitle.build`), `lib/design/app_theme.dart` (`light()` text theme), `lib/fridge/fridge_item_card.dart` (status pill style)
- Test: `test/app_theme_test.dart`

**Step 1: Write the failing test** (append):
```dart
  test('whole text theme uses the bundled family with explicit weights', () {
    final t = theme.textTheme;
    expect(t.bodyMedium!.fontFamily, 'AtkinsonHyperlegibleNext');
    for (final style in [t.titleSmall, t.labelLarge, t.labelMedium, t.labelSmall]) {
      expect(style!.fontWeight, FontWeight.w600);
    }
    expect(t.displaySmall!.fontWeight, FontWeight.w700);
  });
```

**Step 2: Run** `flutter test test/app_theme_test.dart`. Expected: FAIL (fontFamily is null).

**Step 3: Implement**

Download the static weights (the variable font needs `FontVariation`s on every style, which statics avoid):
```bash
mkdir -p assets/fonts
for w in Regular Medium SemiBold Bold; do
  curl -fsSLo assets/fonts/AtkinsonHyperlegibleNext-$w.ttf \
    https://raw.githubusercontent.com/googlefonts/atkinson-hyperlegible-next/main/fonts/ttf/AtkinsonHyperlegibleNext-$w.ttf
done
curl -fsSLo assets/fonts/OFL.txt https://raw.githubusercontent.com/googlefonts/atkinson-hyperlegible-next/main/OFL.txt
ls -l assets/fonts   # expect four ~65 KB .ttf files and OFL.txt
```

`pubspec.yaml`, under `flutter:`: add `- assets/fonts/OFL.txt` to `assets:` and add
```yaml
  fonts:
    - family: AtkinsonHyperlegibleNext
      fonts:
        - asset: assets/fonts/AtkinsonHyperlegibleNext-Regular.ttf
        - asset: assets/fonts/AtkinsonHyperlegibleNext-Medium.ttf
          weight: 500
        - asset: assets/fonts/AtkinsonHyperlegibleNext-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/AtkinsonHyperlegibleNext-Bold.ttf
          weight: 700
```
Then run `flutter pub get`.

`lib/main.dart` → `main()`: after `WidgetsFlutterBinding.ensureInitialized();` register the OFL licence so it appears on the licences page:
```dart
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['AtkinsonHyperlegibleNext'], license);
  });
```

`lib/design/app_theme.dart` → `light()`:
- Add `fontFamily: 'AtkinsonHyperlegibleNext',` to `ThemeData(...)`.
- Replace the `final text = ...` block with:
```dart
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
```
(`weight` with a null `tracking` keeps each role's default letter spacing, because `copyWith` ignores nulls.)

Remove literal font sizes:
- `_HeaderTitle.build` (`lib/main.dart`): `theme.textTheme.headlineSmall?.copyWith(fontSize: 22)` → `theme.textTheme.titleLarge`.
- `FridgeItemCard` status pill: replace the `labelSmall?.copyWith(color: …, fontWeight: FontWeight.w700, fontSize: 10)` style with `theme.textTheme.labelMedium?.copyWith(color: statusColor, fontWeight: FontWeight.w700)`. This raises the text from 10px to 12px, above Apple's 11pt floor.
- `_FridgeBanner`'s 17px/13px literals are replaced in Task 13, where the banner is rebuilt.

**Step 4: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 5: Verify visually.** Run both modes. All text (including the nav and buttons) now renders in Atkinson Hyperlegible Next, which has distinctive open "1" and slashed-looking "0" shapes. Fridge freshness pills are readable and not clipped (if a pill clips at normal text size, note it, because Task 14 resizes tiles). Screenshot Fridge and one recipe card.

**Step 6: Commit**
```bash
git add assets/fonts pubspec.yaml pubspec.lock lib/main.dart lib/design/app_theme.dart lib/fridge/fridge_item_card.dart test/app_theme_test.dart
git commit -m "feat(type): bundle Atkinson Hyperlegible Next and style all M3 roles"
```

---

### Task 4: One input style (delete the 28 `border: OutlineInputBorder()` overrides)

These overrides replace the themed 12px radius, white fill and outline color with a 4px default, so the app currently has two input styles.

**Files:**
- Modify: every file listed by `grep -rln "border: OutlineInputBorder()" lib`. These are `lib/main.dart` (11), `lib/meals/screens/meal_balance_input_form.dart` (7), `lib/exercise/screens/exercise_page.dart` (6), `lib/meals/screens/meal_log_page.dart` (2), `lib/exercise/screens/today_dashboard.dart` (1) and `lib/sleep/screens/sleep_log_sheet.dart` (1). This one-line style deletion is the only D/S-file edit in the plan.
- Test: `test/input_style_guard_test.dart`

**Step 1: Write the failing test**
```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no field overrides the themed input border', () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') &&
            file.readAsStringSync().contains('border: OutlineInputBorder()'))
          file.path,
    ];
    expect(offenders, isEmpty);
  });
}
```

**Step 2: Run** `flutter test test/input_style_guard_test.dart`. Expected: FAIL listing 6 files.

**Step 3: Implement**
```bash
grep -rln "border: OutlineInputBorder()," lib | xargs sed -i '/^[[:space:]]*border: OutlineInputBorder(),[[:space:]]*$/d'
grep -rn "OutlineInputBorder()" lib   # expect no output; delete any remaining inline occurrence by hand
dart format lib
```
`const InputDecoration(...)` stays valid once the line is gone.

**Step 4: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 5: Verify visually.** Open Add food, Agent prompt/feedback, Preferences (budget) and Log meal. Every field has the same rounded white style with a clearly visible grey outline and a 2px green focus ring.

**Step 6: Commit**
```bash
git add lib test/input_style_guard_test.dart
git commit -m "refactor(forms): remove per-field border overrides so all inputs use the theme"
```

---

### Task 5: Plain-language errors (helper, retry view, Auth/verification/save/Q&A)

**Files:**
- Create: `lib/design/friendly_errors.dart`, `lib/design/load_error.dart`, `test/friendly_errors_test.dart`
- Modify: `lib/main.dart` (`_EmailVerificationPageState._checkVerification` / `_resendVerification`, `_AuthPageState._submit` / `_signInWithGoogle`, `FridgePageState.save`), `lib/meals/screens/meal_qa_sheet.dart` (the `on MealQaException` block)
- The remaining raw-error sites are fixed in the tasks that rebuild those screens: fridge stream (Task 6), Agent (Task 7), fridge scan (Task 8) and Home (Task 13).

**Step 1: Write the failing test** (`test/friendly_errors_test.dart`)
```dart
import 'package:diabetes/design/friendly_errors.dart';
import 'package:diabetes/design/load_error.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Firestore outages map to the network message, never raw text', () {
    final message = FriendlyErrors.describe(
      FirebaseException(plugin: 'cloud_firestore', code: 'unavailable', message: 'raw internals'),
    );
    expect(message, FriendlyErrors.network);
  });

  test('unknown errors get the generic message', () {
    expect(FriendlyErrors.describe(StateError('boom')), FriendlyErrors.generic);
  });

  test('auth codes map to plain sentences', () {
    expect(
      FriendlyErrors.auth(FirebaseAuthException(code: 'email-already-in-use')),
      contains('already exists'),
    );
    expect(
      FriendlyErrors.auth(FirebaseAuthException(code: 'invalid-credential')),
      isNot(contains('invalid-credential')),
    );
  });

  testWidgets('LoadErrorView shows the message and retries', (tester) async {
    var retried = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LoadErrorView(message: 'Nope.', onRetry: () => retried++)),
    ));
    expect(find.text('Nope.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retried, 1);
  });
}
```

**Step 2: Run** `flutter test test/friendly_errors_test.dart`. Expected: compile FAIL.

**Step 3: Implement**

`lib/design/friendly_errors.dart`:
```dart
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Plain-language messages for errors shown to users. Raw errors go to the
/// debug log only, never on screen (NN/g error-message guidelines).
abstract final class FriendlyErrors {
  static const network =
      "Couldn't reach the server. Check your connection and try again.";
  static const generic = 'Something went wrong. Please try again.';

  /// Logs [error] under [context] and returns a message safe to show.
  static String describe(Object error, {String context = 'error'}) {
    debugPrint('$context: $error');
    if (error is TimeoutException) return network;
    if (error is FirebaseException) {
      return switch (error.code) {
        'unavailable' || 'deadline-exceeded' || 'network-request-failed' => network,
        'permission-denied' || 'unauthenticated' =>
          'Your session has expired. Sign in again to continue.',
        _ => generic,
      };
    }
    final text = error.toString();
    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('Failed host lookup')) {
      return network;
    }
    return generic;
  }

  /// Maps Firebase Auth codes to plain sign-in messages.
  static String auth(FirebaseAuthException error) {
    debugPrint('auth: ${error.code} ${error.message}');
    return switch (error.code) {
      'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-email' =>
        "That email and password don't match. Try again or reset your password.",
      'email-already-in-use' =>
        'An account already exists for that email. Sign in instead.',
      'weak-password' => 'Choose a password with at least 6 characters.',
      'too-many-requests' => 'Too many attempts. Wait a minute and try again.',
      'network-request-failed' => network,
      'popup-closed-by-user' || 'cancelled-popup-request' || 'web-context-canceled' =>
        'Google sign-in was cancelled.',
      _ => "Couldn't sign you in. Please try again.",
    };
  }
}
```

`lib/design/load_error.dart`:
```dart
import 'package:flutter/material.dart';

import 'spacing.dart';

/// Plain-language failure message with a Retry action. Layout-neutral: wrap
/// in [Center] for full-page errors, or place inline in a list.
class LoadErrorView extends StatelessWidget {
  const LoadErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Spacing.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: Spacing.s12),
          Text(message, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
          const SizedBox(height: Spacing.s16),
          FilledButton.tonalIcon(
            key: const Key('loadErrorRetry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
```

Apply in `lib/main.dart` (add `import 'design/friendly_errors.dart';`):
- `_checkVerification` / `_resendVerification`: `_message = error.message ?? '…'` → `_message = FriendlyErrors.describe(error, context: 'email verification');`
- `_submit`:
  - `on FirebaseAuthException` → `_authError = FriendlyErrors.auth(error);`
  - generic `catch` → `_authError = FriendlyErrors.describe(error, context: 'auth');`
- `_signInWithGoogle`: same two replacements.
- `FridgePageState.save` catch block:
```dart
      messenger.showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.describe(error, context: 'fridge save')),
          action: SnackBarAction(label: 'Retry', onPressed: save),
        ),
      );
```
- `lib/meals/screens/meal_qa_sheet.dart`, in `on MealQaException catch (error)`: replace `_error = error.message;` with `_error = "Couldn't get an answer right now.";` and add `debugPrint('meal Q&A: ${error.message}');` above the `setState`. Import `package:flutter/foundation.dart` if analyze asks.

**Step 4: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 5: Verify visually.** On the sign-in screen, enter a wrong password: the error reads "That email and password don't match…" with no `[firebase_auth/...]` text. Turn the network off in DevTools and save a fridge change: the snackbar reads "Couldn't reach the server…" and has a Retry action.

**Step 6: Commit**
```bash
git add lib/design/friendly_errors.dart lib/design/load_error.dart lib/main.dart lib/meals/screens/meal_qa_sheet.dart test/friendly_errors_test.dart
git commit -m "feat(errors): plain-language error messages with retry"
```

---

### Task 6: App shell (labeled NavigationBar, account sheet, single fridge subscription, motion)

**Files:**
- Modify: `lib/main.dart`:
  - `_MainPageState`: fields, `initState`/`dispose`, `build`, `_selectedPage`, new `_showAccountSheet`/`_signOut`/`_subscribeToFridge`
  - delete `CirclePageButton` and `_AppPage`
  - `_headerTitle` text only
- Modify: `test/meal_balance_page_test.dart` (delete the `'two MVP navigation buttons fit a narrow phone'` test, which pumps `CirclePageButton`)

`MainPage` needs a real Firebase `User`, so this task is verified by running the app, not by widget tests.

**Step 1: Single fridge subscription** (fixes the spinner flash on every tab switch; `_selectedPage` used to create a new `snapshots()` stream on every build). In `_MainPageState` add:
```dart
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _fridgeSubscription;

  /// Latest fridge contents; null until the first snapshot arrives.
  List<StoredFoodItem>? _fridgeItems;

  /// Plain-language load error, or null.
  String? _fridgeError;

  @override
  void initState() {
    super.initState();
    _subscribeToFridge();
  }

  @override
  void dispose() {
    _fridgeSubscription?.cancel();
    super.dispose();
  }

  /// One subscription for the life of the shell, so switching tabs never
  /// re-subscribes and flashes a loading spinner.
  void _subscribeToFridge() {
    _fridgeSubscription?.cancel();
    _fridgeError = null;
    _fridgeSubscription = _fridgeItemsCollection(widget.user.uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .listen(
          (snapshot) => setState(() {
            _fridgeItems = snapshot.docs.map(StoredFoodItem.fromDocument).toList();
            _fridgeError = null;
          }),
          onError: (Object error) => setState(
            () => _fridgeError = FriendlyErrors.describe(error, context: 'fridge stream'),
          ),
        );
  }
```
Replace the `StreamBuilder` in `_selectedPage` with:
```dart
    final fridgeError = _fridgeError;
    if (fridgeError != null) {
      return Center(
        child: LoadErrorView(message: fridgeError, onRetry: () => setState(_subscribeToFridge)),
      );
    }
    final storedItems = _fridgeItems;
    if (storedItems == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_selectedIndex == _fridgeTabIndex) {
      return FridgePage(
        key: _fridgeKey,
        initialItems: storedItems,
        // onCommit and onAddSelectedToMeal: unchanged
      );
    }

    return AgentPage(
      foodItems: [for (final stored in storedItems) stored.foodItem],
      // userId, geminiApiKey, diabetesEnabled: unchanged
    );
```
Keep the Home branch at the top of `_selectedPage` as-is. Add `import 'design/load_error.dart';`.

**Step 2: Labeled M3 NavigationBar.** Replace the whole `bottomNavigationBar: SafeArea(... CirclePageButton ...)` with:
```dart
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _goToPage,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.kitchen_outlined),
            selectedIcon: Icon(Icons.kitchen),
            label: 'Fridge',
          ),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'Meals',
          ),
        ],
      ),
```
Then:
- Delete `static const List<_AppPage> _pages`, the `_AppPage` class and the `CirclePageButton` class.
- Delete the `'two MVP navigation buttons fit a narrow phone'` test in `test/meal_balance_page_test.dart`, and remove any imports it leaves unused.
- In `_headerTitle`, change `'Meal Assistant'` → `'Meal ideas'` and `'Your Fridge'` → `'Your fridge'`.
- In `_headerEyebrow`, change `'Your smart assistant'` → `'Cook from what you have'`.

**Step 3: Account sheet replaces the tune and logout icons.** The same `tune` icon meant two different things, and Log out was a one-tap action that silently dropped unsaved fridge edits. Replace the `actions:` list with:
```dart
        actions: [
          _HeaderAction(
            tooltip: 'Account',
            icon: Icons.account_circle_outlined,
            onPressed: _showAccountSheet,
          ),
          const SizedBox(width: Spacing.s8),
        ],
```
Add to `_MainPageState`:
```dart
  Future<void> _showAccountSheet() async {
    final user = widget.user;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(_userDisplayName(user) ?? 'Your account'),
              subtitle: user.email == null ? null : Text(user.email!),
            ),
            const Divider(),
            if (widget.diabetesEnabled)
              ListTile(
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text('Glucose & data sources'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  AppFeatureNavigation.pushDiabetesPage<void>(
                    context,
                    diabetesEnabled: widget.diabetesEnabled,
                    builder: (context) => GlucoseSettingsPage(
                      userId: user.uid,
                      diabetesEnabled: widget.diabetesEnabled,
                    ),
                  );
                },
              ),
            ListTile(
              key: const Key('accountSignOut'),
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () {
                Navigator.pop(sheetContext);
                _signOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Runs the same unsaved-fridge guard as a tab switch before signing out.
  Future<void> _signOut() async {
    if (_selectedIndex == _fridgeTabIndex) {
      final fridgeState = _fridgeKey.currentState;
      if (fridgeState != null && !await fridgeState.confirmLeave()) return;
    }
    await FirebaseAuth.instance.signOut();
  }
```
Update `_HeaderAction`'s doc comment to "Soft circular icon button for the header's account action."

**Step 4: Motion tokens.** In `build`:
- Delete `_tabAnimationDuration`.
- Set `final animationDuration = reduceMotion ? AppMotion.reducedFade : AppMotion.medium;`.
- Set `switchInCurve: AppMotion.enter` and `switchOutCurve: AppMotion.exit`.
- In `transitionBuilder`, return only `FadeTransition(opacity: animation, child: child)` when `reduceMotion` is true. Apple's guidance is to swap slides for a short fade rather than cut instantly.

Add `import 'design/app_motion.dart';`, and set `titleSpacing: Spacing.s16` (was 20).

**Step 5: Run** `flutter test && flutter analyze`. Expected: PASS (one test fewer), no issues. Fix any unused-import warnings.

**Step 6: Verify visually** (both modes; screenshot the shell):
- the bottom bar shows three labeled destinations (Fridge / Home / Meals) with an apricot pill behind the selected one
- switching tabs quickly never flashes a full-screen spinner
- the header has one account button, and its sheet shows name, email and Sign out, plus "Glucose & data sources" only in the diabetes build
- on the Fridge tab, delete an item without saving, then choose Sign out: the "Save fridge changes?" dialog appears first
- with OS "Reduce motion" on (Chrome DevTools → Rendering → `prefers-reduced-motion: reduce`), tabs cross-fade instead of sliding

**Step 7: Commit**
```bash
git add lib/main.dart test/meal_balance_page_test.dart
git commit -m "feat(shell): labeled NavigationBar, account sheet with guarded sign-out, single fridge subscription"
```

---

### Task 7: Agent page (no fake delay, skeleton, retry, example prompts, inline meal type)

**Files:**
- Modify: `lib/main.dart`:
  - `_AgentPageState`: `_loadRecommendation`, `build`; delete `_showMealTypePicker`
  - new `_RecommendationSkeleton`
- Modify: `test/widget_test.dart`

**Step 1: Write/adjust failing tests** in `test/widget_test.dart`:
- In `'agent page starts with a focused recommendation flow'`, change `'Recommend a Meal'` → `'Recommend a meal'`.
- Replace the whole `'agent meal chip can change the meal type'` test with:
```dart
  testWidgets('agent meal type chips change the meal type', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AgentPage(foodItems: []))),
    );
    await tester.tap(find.byKey(const Key('agentMealType_snack')));
    await tester.pump();
    expect(
      tester.widget<ChoiceChip>(find.byKey(const Key('agentMealType_snack'))).selected,
      isTrue,
    );
  });

  testWidgets('example prompts fill the prompt field', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AgentPage(foodItems: []))),
    );
    await tester.tap(find.widgetWithText(ActionChip, 'Quick breakfast'));
    await tester.pump();
    final field = tester.widget<TextFormField>(find.byKey(const Key('agentFoodPrompt')));
    expect(field.controller!.text, 'Quick breakfast');
  });

  testWidgets('failed recommendation shows a plain message and retry', (tester) async {
    // No API key in tests, so GeminiMealService.generate throws immediately.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AgentPage(foodItems: []))),
    );
    await tester.tap(find.byKey(const Key('recommendMealButton')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't get a meal idea right now."), findsOneWidget);
    expect(find.textContaining('API key'), findsNothing);
    expect(find.byKey(const Key('loadErrorRetry')), findsOneWidget);
  });
```

**Step 2: Run** `flutter test test/widget_test.dart`. Expected: the 4 changed/new tests FAIL.

**Step 3: Implement** in `_AgentPageState`:

`_loadRecommendation`: remove the `Future.wait([..., Future.delayed(1s)])`, which added up to 1s of fake latency to every request. The try/catch becomes:
```dart
    try {
      final recommendations = await GeminiMealService.generate(request);
      if (!mounted) return;
      setState(() => _recommendations = recommendations);
    } catch (error) {
      debugPrint('meal recommendation: $error');
      if (!mounted) return;
      setState(() => _recommendationError = "Couldn't get a meal idea right now.");
    } finally {
```

Add `static const _examplePrompts = ['Quick breakfast', "Use what's expiring", r'Under $5'];` and make these changes in `build`'s `ListView` children:
- Right after the `agentFoodPrompt` field, show example chips only while nothing has been requested:
```dart
        if (_lastRequest == null) ...[
          const SizedBox(height: Spacing.s12),
          Wrap(
            spacing: Spacing.s8,
            runSpacing: Spacing.s8,
            children: [
              for (final prompt in _examplePrompts)
                ActionChip(
                  label: Text(prompt),
                  onPressed: () => setState(() => _preferencesController.text = prompt),
                ),
            ],
          ),
        ],
```
- Replace the `Align(... ActionChip(key: Key('agentMealTypeChip') ...))` with inline choice chips (this saves a sheet and a tap), then delete `_showMealTypePicker`:
```dart
        const SizedBox(height: Spacing.s16),
        Text('Meal type', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: Spacing.s8),
        Wrap(
          spacing: Spacing.s8,
          runSpacing: Spacing.s8,
          children: [
            for (final mealType in MealType.values)
              ChoiceChip(
                key: Key('agentMealType_${mealType.name}'),
                label: Text(mealType.label),
                selected: _mealType == mealType,
                onSelected: (_) => setState(() => _mealType = mealType),
              ),
          ],
        ),
```
- Change the recommend button label to `_isLoadingRecommendation ? 'Thinking…' : 'Recommend a meal'`.
- Replace the `if (_isLoadingRecommendation) ...[ Semantics(... spinner row ...) ]` block with `if (_isLoadingRecommendation) ...[const SizedBox(height: Spacing.s24), const _RecommendationSkeleton()],`.
- Replace the red error `Text` block with:
```dart
        if (_recommendationError != null && _lastRequest != null)
          LoadErrorView(
            message: _recommendationError!,
            onRetry: () => _loadRecommendation(_lastRequest!),
          ),
```
- Change `'Suggest Something Else'` → `'Suggest something else'`.

Add the skeleton (below `_AgentPageState`, with `import 'design/app_radius.dart';`):
```dart
/// Placeholder shaped like a recipe card, shown while Gemini works so the wait
/// previews the result (NN/g skeleton screens).
class _RecommendationSkeleton extends StatelessWidget {
  const _RecommendationSkeleton();

  @override
  Widget build(BuildContext context) {
    final block = Theme.of(context).colorScheme.surfaceContainerHigh;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: block,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: 'Finding a meal for you',
      child: ExcludeSemantics(
        child: Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(height: 180, color: block),
              Padding(
                padding: const EdgeInsets.all(Spacing.s16),
                child: Column(
                  children: [
                    bar(0.6, 24),
                    const SizedBox(height: Spacing.s12),
                    bar(1, 16),
                    const SizedBox(height: Spacing.s8),
                    bar(0.8, 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**Step 4: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 5: Verify visually.**
- Meals tab: three example chips under the prompt, and the meal types as a chip row.
- Tapping "Recommend a meal" shows a grey recipe-shaped skeleton and no spinner.
- With the network off: "Couldn't get a meal idea right now." plus "Try again", which re-runs the request.

Screenshot the loading and error states.

**Step 6: Commit**
```bash
git add lib/main.dart test/widget_test.dart
git commit -m "feat(agent): skeleton loading, retry, example prompts, inline meal type; drop fake 1s delay"
```

---

### Task 8: Fridge scan progress with Cancel

A 5–15s AI scan currently shows only a snackbar while the grid stays editable, so users re-tap the camera.

**Files:**
- Create: `lib/fridge/fridge_scan_dialog.dart`, `test/fridge_scan_dialog_test.dart`
- Modify: `lib/main.dart` (`FridgePageState._takeFridgePhoto`)

**Step 1: Write the failing test**
```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:diabetes/fridge/fridge_scan_dialog.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 1×1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
  0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
  0x60, 0x82,
]);

void main() {
  late Completer<List<FoodItem>> scan;
  FridgeScanResult? result;
  late bool closed;

  Future<void> open(WidgetTester tester) async {
    scan = Completer();
    result = null;
    closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDialog<FridgeScanResult>(
              context: context,
              barrierDismissible: false,
              builder: (_) => FridgeScanDialog(imageBytes: _png, detect: (_) => scan.future),
            );
            closed = true;
          },
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('shows progress, then returns detected foods', (tester) async {
    await open(tester);
    expect(find.text('Finding foods…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    scan.complete(const [FoodItem(name: 'Eggs', amount: '12', foodType: FoodType.protein)]);
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result!.foods.single.name, 'Eggs');
  });

  testWidgets('cancel closes immediately and ignores the late result', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('fridgeScanCancel')));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);

    scan.complete(const []);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed scan returns the error', (tester) async {
    await open(tester);
    scan.completeError(Exception('boom'));
    await tester.pumpAndSettle();
    expect(result!.error, isNotNull);
  });
}
```

**Step 2: Run** `flutter test test/fridge_scan_dialog_test.dart`. Expected: compile FAIL.

**Step 3: Implement** `lib/fridge/fridge_scan_dialog.dart`:
```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../design/app_radius.dart';
import '../design/spacing.dart';
import '../main.dart' show FoodItem;

/// Outcome of a fridge photo scan. The dialog returns null when cancelled.
class FridgeScanResult {
  const FridgeScanResult.success(this.foods) : error = null;
  const FridgeScanResult.failure(Object this.error) : foods = const [];

  final List<FoodItem> foods;
  final Object? error;
}

/// Blocks the fridge while the AI scan runs (5–15 s), so the user sees
/// progress, can cancel, and can't edit a grid that's about to change.
class FridgeScanDialog extends StatefulWidget {
  const FridgeScanDialog({super.key, required this.imageBytes, required this.detect});

  final Uint8List imageBytes;
  final Future<List<FoodItem>> Function(Uint8List imageBytes) detect;

  @override
  State<FridgeScanDialog> createState() => _FridgeScanDialogState();
}

class _FridgeScanDialogState extends State<FridgeScanDialog> {
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    FridgeScanResult result;
    try {
      result = FridgeScanResult.success(await widget.detect(widget.imageBytes));
    } catch (error) {
      result = FridgeScanResult.failure(error);
    }
    if (!mounted || _cancelled) return;
    Navigator.of(context).pop(result);
  }

  void _cancel() {
    _cancelled = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Finding foods…'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Opacity(
                opacity: 0.6,
                child: Image.memory(
                  widget.imageBytes,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(height: 160),
                ),
              ),
            ),
            const SizedBox(height: Spacing.s16),
            const LinearProgressIndicator(),
            const SizedBox(height: Spacing.s12),
            Text(
              'This usually takes 5–15 seconds.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('fridgeScanCancel'),
            onPressed: _cancel,
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
```

`lib/main.dart` → `_takeFridgePhoto` (add `import 'fridge/fridge_scan_dialog.dart';`): keep the camera sheet call, then replace everything after `if (imageBytes == null) return;` with:
```dart
    if (!context.mounted) return;
    final result = await showDialog<FridgeScanResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => FridgeScanDialog(
        imageBytes: imageBytes,
        detect: FridgePhotoFoodAgent.detectFoods,
      ),
    );
    if (result == null) return; // Cancelled.

    final error = result.error;
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(FriendlyErrors.describe(error, context: 'fridge scan')),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () => _takeFridgePhoto(context),
          ),
        ),
      );
      return;
    }
    if (result.foods.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No foods found. Try a closer, well-lit photo.')),
      );
      return;
    }

    _addDrafts(result.foods);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.foods.length == 1
              ? 'Added 1 item — remember to save.'
              : 'Added ${result.foods.length} items — remember to save.',
        ),
      ),
    );
```

**Step 4: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 5: Verify visually.** Scan a fridge photo. A dialog with the dimmed photo, an animated progress bar and Cancel appears, the grid behind can't be touched, Cancel closes it with no items added, and a successful scan adds items with the "remember to save" snackbar. Screenshot the dialog.

**Step 6: Commit**
```bash
git add lib/fridge/fridge_scan_dialog.dart lib/main.dart test/fridge_scan_dialog_test.dart
git commit -m "feat(fridge): blocking scan progress dialog with cancel and retry"
```

---

### Task 9: Fridge empty state

**Files:**
- Modify: `lib/main.dart` (`FridgePageState.build`, new `_FridgeEmptyState`), `test/widget_test.dart`, `test/fridge_save_workflow_test.dart`

**Step 1: Write/adjust failing tests**
- `test/fridge_save_workflow_test.dart`: change `'No food added yet.'` → `'Your fridge is empty'`, and add:
```dart
  testWidgets('empty fridge explains itself and offers scan and add', (tester) async {
    await tester.pumpWidget(wrap(GlobalKey<FridgePageState>(), const [], []));
    expect(find.text('Your fridge is empty'), findsOneWidget);
    expect(find.byKey(const Key('fridgeEmptyScan')), findsOneWidget);
    expect(find.byKey(const Key('fridgeEmptyAdd')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
  });
```
- `test/widget_test.dart` (`'fridge page can add, edit, and remove food items'`):
  - change both `'No food added yet.'` → `'Your fridge is empty'`
  - change the first `await tester.tap(find.byTooltip('Add food'));` (the empty fridge) → `await tester.tap(find.byKey(const Key('fridgeEmptyAdd')));`

**Step 2: Run** `flutter test test/fridge_save_workflow_test.dart test/widget_test.dart`. Expected: FAIL.

**Step 3: Implement.** In `FridgePageState.build`:
- Replace `const Center(child: Text('No food added yet.'))` with
```dart
          _FridgeEmptyState(
            onScan: () => _takeFridgePhoto(context),
            onAdd: () => _showAddFoodSheet(context),
          )
```
- Wrap the FAB `Positioned(...)` in `if (_drafts.isNotEmpty)`, because the empty state carries both actions.

Add:
```dart
/// First-run state for the core loop: says what the fridge is for and gives
/// both ways to fill it (NN/g empty-state guidelines).
class _FridgeEmptyState extends StatelessWidget {
  const _FridgeEmptyState({required this.onScan, required this.onAdd});

  final VoidCallback onScan;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.s24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.kitchen_outlined, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: Spacing.s16),
              Text(
                'Your fridge is empty',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.s8),
              Text(
                "Scan a photo of your fridge or add foods one by one — we'll suggest meals from them.",
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Spacing.s24),
              FilledButton.icon(
                key: const Key('fridgeEmptyScan'),
                onPressed: onScan,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Scan fridge'),
              ),
              const SizedBox(height: Spacing.s8),
              TextButton(
                key: const Key('fridgeEmptyAdd'),
                onPressed: onAdd,
                child: const Text('Add manually'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

**Step 4: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 5: Verify visually.** Sign in with a fresh account (or delete all items and save). The Fridge tab shows the icon, "Your fridge is empty", the explanation, "Scan fridge" and "Add manually", with no floating buttons. Screenshot it.

**Step 6: Commit**
```bash
git add lib/main.dart test/widget_test.dart test/fridge_save_workflow_test.dart
git commit -m "feat(fridge): explanatory empty state with scan and add actions"
```

---

### Task 10: Fridge action layout

Changes: one extended FAB, a bottom save bar, "Add to meal" as the primary selection action, and delete moved into the edit sheet.

**Files:**
- Modify: `lib/main.dart`:
  - `FridgePageState.build`, `_showEditFoodSheet`
  - `_FridgeSaveControls` renamed to `_FridgeSaveBar`
  - `AddFoodSheet` (new `onDelete`)
- Modify: `lib/fridge/fridge_item_card.dart` (remove `onRemove`/X, add selection slot)
- Modify: `lib/fridge/selectable_fridge_grid.dart` (`bottomPadding`, toolbar, dialog labels)
- Tests: `test/fridge_item_card_test.dart`, `test/fridge_save_workflow_test.dart`, `test/widget_test.dart`, `test/selectable_fridge_grid_test.dart`

**Step 1: Write/adjust failing tests**
- `test/fridge_item_card_test.dart`:
  - remove every `onRemove: () {},` argument
  - replace the `'tapping [X] triggers remove'` test with:
```dart
  testWidgets('no per-tile delete; selection mode shows a check slot', (tester) async {
    var toggled = false;
    await tester.pumpWidget(wrap(FridgeItemCard(
      foodItem: const FoodItem(name: 'Eggs', amount: '12 eggs', foodType: FoodType.protein),
      onEdit: () {},
      selectionMode: true,
      onToggleSelection: () => toggled = true,
      now: now,
    )));
    expect(find.byTooltip('Delete item'), findsNothing);
    expect(find.bySemanticsLabel('Not selected'), findsOneWidget);
    await tester.tap(find.text('Eggs'));
    expect(toggled, isTrue);
  });
```
- `test/fridge_save_workflow_test.dart`: add this helper inside `main()` and replace each `await tester.tap(find.byTooltip('Delete item')); await tester.pumpAndSettle();` pair with `await deleteViaEditSheet(tester, 'Milk');`:
```dart
  Future<void> deleteViaEditSheet(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('fridgeEditDelete')));
    await tester.tap(find.byKey(const Key('fridgeEditDelete')));
    await tester.pumpAndSettle();
  }
```
  Then add `expect(find.text('1 unsaved change'), findsOneWidget);` after the first deletion in `'deleting an existing item stages a deletion until saved'`, and add:
```dart
  testWidgets('one extended Scan fridge FAB plus a small add FAB', (tester) async {
    await tester.pumpWidget(wrap(GlobalKey<FridgePageState>(), [stored('a', 'Milk')], []));
    expect(find.widgetWithText(FloatingActionButton, 'Scan fridge'), findsOneWidget);
    expect(find.byTooltip('Add food'), findsOneWidget);
  });
```
- `test/widget_test.dart`: replace the `find.byTooltip('Delete item')` tap with the same edit-sheet flow for `'Milk'` (inline: tap `'Milk'`, pumpAndSettle, ensureVisible and tap `Key('fridgeEditDelete')`, pumpAndSettle).
- `test/selectable_fridge_grid_test.dart`: change `find.widgetWithText(FilledButton, 'Delete')` → `find.widgetWithText(FilledButton, 'Delete 2 items')`.

**Step 2: Run** the four test files. Expected: FAIL.

**Step 3: Implement**

`FridgeItemCard`:
- Delete the `onRemove` field and constructor parameter.
- Replace the whole `if (selected) Positioned(...) else Positioned(... IconButton ...)` with a top-left slot shown only in selection mode (the whole tile is the ≥48dp target):
```dart
              if (selectionMode)
                Positioned(
                  top: Spacing.s4,
                  left: Spacing.s4,
                  child: Icon(
                    selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 22,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    semanticLabel: selected ? 'Selected' : 'Not selected',
                  ),
                ),
```
- Update the class doc to: "Compact inventory tile. Tapping edits the item (delete lives in the edit sheet), and in selection mode tapping toggles selection."

`SelectableFridgeGrid`:
- Add `this.bottomPadding = 144` with a field doc ("Space kept clear below the grid for the host's floating buttons and bars"), and use it in place of the literal `280` in the grid `SliverPadding`.
- Delete the `onRemove:` argument.
- In `_runAction`:
  - dialog title → `Text(_selected.length == 1 ? 'Delete 1 item?' : 'Delete ${_selected.length} items?')`
  - confirm `FilledButton` → error colors via `FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError)` and label `_selected.length == 1 ? 'Delete 1 item' : 'Delete ${_selected.length} items'`
- Replace the toolbar's `TextButton.icon('Meal')` + `SizedBox` + `FilledButton.icon('Remove')` with:
```dart
                        IconButton.outlined(
                          key: const Key('deleteSelectedFridgeItems'),
                          tooltip: 'Remove selected',
                          onPressed: () => _runAction(FoodBulkAction.delete),
                          style: IconButton.styleFrom(
                            foregroundColor: Theme.of(context).colorScheme.error,
                            side: BorderSide(color: Theme.of(context).colorScheme.error),
                          ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                        const SizedBox(width: Spacing.s8),
                        FilledButton.icon(
                          key: const Key('addSelectedToMeal'),
                          onPressed: () => _runAction(FoodBulkAction.addToMeal),
                          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                          icon: const Icon(Icons.restaurant),
                          label: const Text('Add to meal'),
                        ),
```
  Give the `'${_selected.length} selected'` text `maxLines: 1, overflow: TextOverflow.ellipsis` and the `titleSmall` style.

`AddFoodSheet`:
- Constructor → `const AddFoodSheet({super.key, this.foodItem, this.onDelete});`, plus the field
```dart
  /// Edit mode only: deletes the item (staged until the fridge is saved).
  final VoidCallback? onDelete;
```
- After the save `FilledButton`, add:
```dart
              if (_isEditing && widget.onDelete != null) ...[
                const SizedBox(height: Spacing.s8),
                TextButton.icon(
                  key: const Key('fridgeEditDelete'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    minimumSize: const Size(0, 48),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onDelete!();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete item'),
                ),
              ],
```
- `_showEditFoodSheet`: `builder: (context) => AddFoodSheet(foodItem: _drafts[index].item, onDelete: () => _removeDrafts([index]))`.

`FridgePageState.build` (final shape of the `Stack` children; the empty-state branch comes from Task 9):
```dart
    final scheme = Theme.of(context).colorScheme;
    final barShowing = selecting || _isDirty;
    // ...
          SelectableFridgeGrid(
            // existing arguments, plus:
            bottomPadding: barShowing ? 216 : 144,
          ),
        if (_drafts.isNotEmpty)
          Positioned(
            right: Spacing.margin,
            bottom: barShowing ? 88 : Spacing.s16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'addFood',
                  onPressed: () => _showAddFoodSheet(context),
                  tooltip: 'Add food',
                  backgroundColor: scheme.secondaryContainer,
                  foregroundColor: scheme.onSecondaryContainer,
                  child: const Icon(Icons.add),
                ),
                const SizedBox(height: Spacing.s12),
                FloatingActionButton.extended(
                  heroTag: 'takeFridgePhoto',
                  onPressed: () => _takeFridgePhoto(context),
                  tooltip: 'Scan a fridge photo',
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Scan fridge'),
                ),
              ],
            ),
          ),
        // Unsaved-changes bar, in the same bottom slot as the selection toolbar
        // (which takes precedence while selecting).
        if (_isDirty && !selecting)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _FridgeSaveBar(
              pendingCount: _buildChangeSet().count,
              isSaving: _isSaving,
              onDiscard: _isSaving ? null : discard,
              onSave: _isSaving ? null : () => save(),
            ),
          ),
```
Rename `_FridgeSaveControls` → `_FridgeSaveBar` (keep the four fields) and replace its `build` with:
```dart
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 3,
      color: theme.colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.s16, vertical: Spacing.s8),
        child: Row(
          children: [
            Icon(Icons.edit_note, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: Spacing.s8),
            Expanded(
              child: Text(
                pendingCount == 1 ? '1 unsaved change' : '$pendingCount unsaved changes',
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              key: const Key('fridgeDiscardBar'),
              onPressed: onDiscard,
              child: const Text('Discard'),
            ),
            const SizedBox(width: Spacing.s8),
            FilledButton(
              key: const Key('fridgeSaveBar'),
              onPressed: onSave,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              child: isSaving
                  ? SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
```
Update its doc comment to say "full-width bar pinned to the bottom". Also update the `FridgePage` class doc comment, which mentions "per-card delete button", to "via the edit sheet or multi-select".

**Step 4: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 5: Verify visually** (screenshot each):
- the Fridge shows one green "Scan fridge" pill FAB with a small apricot "+" above it
- tiles have no X
- tapping a tile opens the edit sheet with a red "Delete item"
- after an edit, a bottom bar reads "1 unsaved change · Discard · Save" and the FABs sit above it
- long-press selects: tiles show empty or checked circles top-left, and the toolbar shows a red outlined bin and a filled "Add to meal"
- the delete dialog button reads "Delete 2 items"

**Step 6: Commit**
```bash
git add lib/main.dart lib/fridge test
git commit -m "feat(fridge): single scan FAB, bottom save bar, primary Add to meal, delete via edit sheet"
```

---

### Task 11: Auth page (identity, forgot password, show password, consistent wording)

**Files:**
- Modify: `lib/main.dart` (`_AuthPageState`: fields, `build`, `_signInWithGoogle` copy, new `_resetPassword`)
- Test: `test/auth_page_test.dart`

**Step 1: Write the failing test** (none of these paths touch Firebase)
```dart
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester) =>
      tester.pumpWidget(const MaterialApp(home: AuthPage()));

  testWidgets('says what the app is and offers recovery', (tester) async {
    await pump(tester);
    expect(find.text('Wellness Companion'), findsOneWidget);
    expect(find.text("Turn what's in your fridge into meal ideas."), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('password can be shown and hidden', (tester) async {
    await pump(tester);
    EditableText field() => tester.widget<EditableText>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Password'),
        matching: find.byType(EditableText),
      ),
    );
    expect(field().obscureText, isTrue);
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(field().obscureText, isFalse);
  });

  testWidgets('length rule applies to sign-up only', (tester) async {
    await pump(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'a@b.co');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter your password'), findsOneWidget);
    expect(find.text('Use at least 6 characters'), findsNothing);

    await tester.tap(find.text('New here? Create an account'));
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), '123');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    expect(find.text('Use at least 6 characters'), findsOneWidget);
  });

  testWidgets('forgot password without an email asks for it', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pump();
    expect(find.textContaining('Enter your email above'), findsOneWidget);
  });
}
```

**Step 2: Run** `flutter test test/auth_page_test.dart`. Expected: FAIL.

**Step 3: Implement** in `_AuthPageState` (add `bool _obscurePassword = true;`):
- Wrap the `Form`'s `Column` in `AutofillGroup(child: ...)`.
- Replace the headline `Text(_isSignUp ? 'Create Account' : 'Sign In', …headlineMedium…)` with:
```dart
                    Icon(Icons.eco, size: 48, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: Spacing.s8),
                    Text(
                      'Wellness Companion',
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Spacing.s4),
                    Text(
                      "Turn what's in your fridge into meal ideas.",
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: Spacing.s32),
                    Text(
                      _isSignUp ? 'Create account' : 'Sign in',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: Spacing.s16),
```
- Password field: `obscureText: _obscurePassword`, `autofillHints: _isSignUp ? const [AutofillHints.newPassword] : const [AutofillHints.password]`, and
```dart
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Enter your password';
                        if (_isSignUp && value.length < 6) return 'Use at least 6 characters';
                        return null;
                      },
```
- After the password field, in sign-in mode only:
```dart
                    if (!_isSignUp)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _isLoading ? null : _resetPassword,
                          child: const Text('Forgot password?'),
                        ),
                      ),
```
- Labels:
  - submit → `_isLoading ? 'Please wait…' : _isSignUp ? 'Create account' : 'Sign in'`
  - Google → `'Continue with Google'`
  - toggle → `_isSignUp ? 'Already have an account? Sign in' : 'New here? Create an account'`
- In `_signInWithGoogle`, change the new-user message to `'No account found for that Google address. Create an account with email first.'`.
- Add:
```dart
  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _authError = 'Enter your email above, then tap "Forgot password?" again.');
      return;
    }
    setState(() {
      _isLoading = true;
      _authError = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('If an account exists for $email, a reset link is on its way.')),
      );
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _authError = FriendlyErrors.auth(error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
```
- Replace the literal spacings in this `build` with `Spacing.*` (24 → s24, 12 → s12, 16 → s16).

**Step 4: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 5: Verify visually.**
- Signed out: the screen shows the leaf icon, "Wellness Companion", a one-line purpose, "Sign in", an eye toggle on the password, "Forgot password?" and "Continue with Google".
- A reset email arrives for a real account.
- Password managers offer to fill both fields on web.

Screenshot both sign-in and sign-up modes.

**Step 6: Commit**
```bash
git add lib/main.dart test/auth_page_test.dart
git commit -m "feat(auth): app identity, forgot password, show password, sign-up-only length rule"
```

---

### Task 12: Recipe card (`MealRecommendationCard`)

Changes: a metadata row, a visible ask signifier, real bullets, one primary action, and an AI-generated image label.

**Files:**
- Modify: `lib/main.dart`:
  - `MealRecommendationCard`: new `timeLabel`/`difficultyLabel`, `build`, `_askable`, new `_sectionHeader`/`_bullet`/`_step`
  - `_InfoPill`
  - delete `_FridgeAndCostRow`
  - `_AgentPageState.build` passes the labels
- Modify: `test/meal_qa_test.dart`
- Create: `test/meal_recommendation_card_test.dart`

**Step 1: Write the failing tests**

`test/meal_qa_test.dart`, in `'without onAsk the card has no chips and no tap targets'`: change `find.text('1. Rinse the quinoa.')` → `find.text('Rinse the quinoa.')` and add `expect(find.text('Tap a line to ask'), findsNothing);`.

`test/meal_recommendation_card_test.dart`:
```dart
import 'package:diabetes/design/app_theme.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _meal = MealRecommendation(
  dishName: 'Veggie omelette',
  imagePrompt: '',
  reason: 'Uses your eggs before they expire.',
  ingredients: ['2 eggs', '1 cup spinach'],
  instructions: ['Whisk the eggs.', 'Cook with spinach.'],
  estimatedCostPerServing: r'$2-3/serving',
  usedFridgeItems: ['Eggs'],
  imageUrl: 'https://example.com/omelette.png',
);

Future<void> pumpCard(WidgetTester tester, {bool withAsk = true}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: ListView(children: [
        MealRecommendationCard(
          recommendation: _meal,
          diabetesEnabled: false,
          timeLabel: '≤ 20 min',
          difficultyLabel: 'Beginner',
          onLogMeal: () {},
          onMakeBalanced: () {},
          onAsk: withAsk ? (scope, {String? initialQuestion}) {} : null,
        ),
      ]),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('decision facts sit directly under the dish name', (tester) async {
    await pumpCard(tester);
    final nameY = tester.getTopLeft(find.text('Veggie omelette')).dy;
    final reasonY = tester.getTopLeft(find.text(_meal.reason)).dy;
    for (final fact in ['≤ 20 min', r'$2-3/serving', 'Beginner']) {
      final y = tester.getTopLeft(find.text(fact)).dy;
      expect(y, greaterThan(nameY));
      expect(y, lessThan(reasonY));
    }
  });

  testWidgets('generated photo is labeled', (tester) async {
    await pumpCard(tester);
    expect(find.text('AI-generated image'), findsOneWidget);
  });

  testWidgets('ask affordance is visible when asking is possible', (tester) async {
    await pumpCard(tester);
    expect(find.text('Tap a line to ask'), findsNWidgets(2));
  });

  testWidgets('one filled action; balancing is tonal', (tester) async {
    await pumpCard(tester);
    expect(find.widgetWithText(FilledButton, 'Log this meal'), findsOneWidget);
    expect(find.text('Add a balancing tweak'), findsOneWidget);
    expect(find.text('Make it more balanced?'), findsNothing);
  });
}
```

**Step 2: Run** `flutter test test/meal_recommendation_card_test.dart test/meal_qa_test.dart`. Expected: FAIL.

**Step 3: Implement** in `MealRecommendationCard`:
- New fields with docs:
```dart
  /// Time budget the user asked for, e.g. "≤ 20 min". Null hides it.
  final String? timeLabel;

  /// Cooking difficulty the user asked for, e.g. "Beginner". Null hides it.
  final String? difficultyLabel;
```
  Add them as optional constructor params.
- `_askable`: replace the doc comment's "Intentionally adds no icon or tint…" paragraph with "Section headers carry the visible 'Tap a line to ask' signifier." In the `Padding`, wrap `child` in `ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: Align(alignment: Alignment.centerLeft, child: child))` so each line meets the 48dp target. Change `BorderRadius.circular(8)` → `AppRadius.sm`, and padding `vertical: 8, horizontal: 4` → `vertical: Spacing.s4, horizontal: Spacing.s4`.
- Add helpers:
```dart
  Widget _sectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        if (onAsk != null) ...[
          Icon(Icons.chat_bubble_outline, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: Spacing.s4),
          Text(
            'Tap a line to ask',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  Widget _bullet(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 9px top offset centers the dot on bodyLarge's first 24px line.
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(top: 9, right: Spacing.s12),
          decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
        ),
        Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
      ],
    );
  }

  Widget _step(BuildContext context, int number, String text) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          margin: const EdgeInsets.only(right: Spacing.s12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
      ],
    );
  }
```
- `build`: image area. Replace the `Container(height: 180, color: …, child: …)` with the block below. Keep the existing `Image.network(...)`/placeholder expression as the `ColoredBox` child, and add `semanticLabel: 'Photo of ${recommendation.dishName}'` to `Image.network`.
```dart
          SizedBox(
            height: 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: /* existing imageUrl == null ? placeholder : Image.network(...) */,
                ),
                if (recommendation.imageUrl != null)
                  Positioned(
                    left: Spacing.s8,
                    bottom: Spacing.s8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.s8,
                          vertical: Spacing.s4,
                        ),
                        child: Text(
                          'AI-generated image',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
```
- `build`: body order is dish name → metadata `Wrap` → evening chip (D/S, unchanged) → reason → fridge pill → glucose note (unchanged) → Ingredients → Instructions → question chips (unchanged) → actions:
```dart
                if (timeLabel != null ||
                    recommendation.estimatedCostPerServing != null ||
                    difficultyLabel != null) ...[
                  const SizedBox(height: Spacing.s8),
                  Wrap(
                    spacing: Spacing.s8,
                    runSpacing: Spacing.s8,
                    children: [
                      if (timeLabel != null) _InfoPill(icon: Icons.schedule, label: timeLabel!),
                      if (recommendation.estimatedCostPerServing != null)
                        _InfoPill(
                          icon: Icons.payments_outlined,
                          label: recommendation.estimatedCostPerServing!,
                        ),
                      if (difficultyLabel != null)
                        _InfoPill(icon: Icons.signal_cellular_alt, label: difficultyLabel!),
                    ],
                  ),
                ],
```
  - Fridge row: replace `_FridgeAndCostRow(...)` (guarded by `usedFridgeItems.isNotEmpty` only) with `_InfoPill(icon: Icons.kitchen_outlined, label: 'From your fridge: ${recommendation.usedFridgeItems.join(', ')}')`, then delete the `_FridgeAndCostRow` class.
  - Headers: replace `Text('Ingredients', …)` and `Text('Instructions', …)` with `_sectionHeader(context, 'Ingredients')` / `_sectionHeader(context, 'Instructions')`.
  - Line children: in the ingredient `_askable`, `child: Text('- ${…}')` → `child: _bullet(context, recommendation.ingredients[index])`. In the step `_askable`, `child: Text('${index + 1}. …')` → `child: _step(context, index + 1, recommendation.instructions[index])`.
  - Replace all three action blocks (`onMakeBalanced`, `onStartPostMealWalk`, `onLogMeal`) with:
```dart
                if (onStartPostMealWalk != null || onMakeBalanced != null || onLogMeal != null) ...[
                  const SizedBox(height: Spacing.s24),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    overflowAlignment: OverflowBarAlignment.end,
                    spacing: Spacing.s8,
                    overflowSpacing: Spacing.s8,
                    children: [
                      if (onStartPostMealWalk != null)
                        TextButton.icon(
                          onPressed: onStartPostMealWalk,
                          icon: const Icon(Icons.directions_walk),
                          label: const Text('Start a 10-minute walk'),
                        ),
                      if (onMakeBalanced != null)
                        FilledButton.tonalIcon(
                          onPressed: onMakeBalanced,
                          icon: const Icon(Icons.balance),
                          label: const Text('Add a balancing tweak'),
                        ),
                      if (onLogMeal != null)
                        FilledButton.icon(
                          onPressed: onLogMeal,
                          icon: const Icon(Icons.restaurant),
                          label: const Text('Log this meal'),
                        ),
                    ],
                  ),
                ],
```
  - Update the `onMakeBalanced` field doc to "Add a balancing tweak".
  - Replace the remaining literals with tokens: 8 → `Spacing.s8`, 12 → `Spacing.s12`, 16 → `Spacing.s16`, 20 → `Spacing.s24`, 4 → `Spacing.s4`.
- `_InfoPill.build`:
  - `surfaceContainerHighest` → `surfaceContainerHigh`
  - radius 10 → `AppRadius.md`
  - padding → `EdgeInsets.symmetric(horizontal: Spacing.s12, vertical: Spacing.s4)`
  - icon size 16
  - gap `Spacing.s4`
  - text style → `theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurface)` (was 11px muted at 4.01:1)
- `_AgentPageState.build`, in the `MealRecommendationCard(...)` call, add:
```dart
              timeLabel: (_lastRequest?.hasTimeShortage ?? false) &&
                      (_lastRequest?.timeAvailable?.isNotEmpty ?? false)
                  ? '≤ ${_lastRequest!.timeAvailable} min'
                  : null,
              difficultyLabel: _lastRequest?.cookingExperience.label,
```
  The Meal Lab button after the result list stays where it is. It is already a single entry, not one per card, and `test/diabetes_feature_navigation_test.dart` depends on it.

**Step 4: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 5: Verify visually.** Generate a recipe in both modes (in Preferences, turn on "I'm in a hurry" = 20).
- Under the title are the pills "≤ 20 min · $x–y · Beginner".
- The photo has an "AI-generated image" tag.
- Ingredients use green dots and steps use numbered circles in larger text.
- Both headers show "Tap a line to ask", and tapping a line opens the Q&A sheet.
- The bottom has a tonal "Add a balancing tweak" and a filled "Log this meal", stacked on narrow phones.

Screenshot a full card.

**Step 6: Commit**
```bash
git add lib/main.dart test/meal_qa_test.dart test/meal_recommendation_card_test.dart
git commit -m "feat(recipe-card): metadata row, ask signifier, bullets, single primary action, AI image label"
```

---

### Task 13: Home (informative banner, tap-to-edit, undo, skeleton, retry)

**Files:**
- Modify: `lib/home/mvp_home_page.dart`:
  - `MvpHomePage` (new params)
  - `_MvpHomePageState` (retryable stream, skeleton)
  - `_HomeContent` / `_HomeContentState` (`_commit` returns bool, `_rename`, `_remove` with undo, rows, localized date, tokens)
  - `_FridgeBanner` rebuilt
  - `_EmptyChecklist` copy
  - new `_HomeSkeleton`
- Modify: `lib/main.dart` (`_MainPageState._selectedPage` passes counts)
- Test: `test/mvp_home_page_test.dart`

**Step 1: Write/adjust failing tests** in `test/mvp_home_page_test.dart`:
- In the existing test, after `await tester.tap(find.byTooltip('Remove Check fridge')); await tester.pump(); expect(savedItems, isEmpty);` append:
```dart
    await tester.pumpAndSettle(); // snackbar appears after the async save
    expect(find.text('Undo'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(savedItems.single.name, 'Check fridge');
```
- Add:
```dart
  Widget home({
    required Stream<TodayTodoState> stream,
    int? fridgeItemCount,
    int expiringCount = 0,
  }) => MaterialApp(
    home: Scaffold(
      body: MvpHomePage(
        userId: 'user-1',
        now: DateTime(2026, 7, 21),
        todoStateStream: stream,
        onSaveTodos: (_) async {},
        onOpenFridge: () {},
        fridgeItemCount: fridgeItemCount,
        expiringCount: expiringCount,
      ),
    ),
  );

  testWidgets('banner summarizes the fridge', (tester) async {
    await tester.pumpWidget(home(
      stream: Stream.value(const TodayTodoState(isInitialized: true, items: [])),
      fridgeItemCount: 5,
      expiringCount: 2,
    ));
    await tester.pump();
    expect(find.text('5 items · 2 expiring soon'), findsOneWidget);
  });

  testWidgets('tapping a task opens the edit dialog', (tester) async {
    await tester.pumpWidget(home(
      stream: Stream.value(const TodayTodoState(
        isInitialized: true,
        items: [TodayTodo(id: 't1', name: 'Walk')],
      )),
    ));
    await tester.pump();
    await tester.tap(find.text('Walk'));
    await tester.pumpAndSettle();
    expect(find.text('Edit task'), findsOneWidget);
  });

  testWidgets('loading shows a skeleton, errors offer retry', (tester) async {
    await tester.pumpWidget(home(stream: const Stream<TodayTodoState>.empty()));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Loading your checklist'), findsOneWidget);

    // Unmount first: the page reads its stream once, in initState.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(home(stream: Stream.error(Exception('offline'))));
    await tester.pump();
    expect(find.byKey(const Key('loadErrorRetry')), findsOneWidget);
  });
```
  `Stream.empty()` never emits data, so it stays in the loading state.

**Step 2: Run** `flutter test test/mvp_home_page_test.dart`. Expected: FAIL.

**Step 3: Implement** in `lib/home/mvp_home_page.dart` (add imports `../design/app_radius.dart`, `../design/app_theme.dart`, `../design/load_error.dart`, `../design/spacing.dart`):

- `MvpHomePage`: add
```dart
  /// Fridge size for the banner; null while the fridge is still loading.
  final int? fridgeItemCount;

  /// Items expired or expiring within [kExpiringSoonThresholdDays].
  final int expiringCount;
```
  with constructor params `this.fridgeItemCount, this.expiringCount = 0`, and thread both through `_HomeContent` to `_FridgeBanner`.
- `_MvpHomePageState`:
  - Change `late final Stream<TodayTodoState> _todoState = …` to `late Stream<TodayTodoState> _todoState = _watch();` plus `Stream<TodayTodoState> _watch() => widget.todoStateStream ?? _repository!.watchTodos(widget.userId, _today);`.
  - Error branch → `Center(child: LoadErrorView(message: "Couldn't load your checklist.", onRetry: () => setState(() => _todoState = _watch())))`.
  - Loading branch → `const _HomeSkeleton()`.
- `_HomeContentState`:
  - `_commit` returns `Future<bool>`: `true` after a successful save, `false` in the catch (after reverting). Its error snackbar text becomes `"Couldn't save your checklist. Try again."`.
  - Add:
```dart
  Future<void> _rename(TodayTodo item) async {
    final name = await _taskName(item.name);
    if (name == null) return;
    await _commit([
      for (final current in _items)
        current.id == item.id ? current.copyWith(name: name) : current,
    ]);
  }

  /// Deletes immediately and offers Undo, instead of a confirmation dialog
  /// (NN/g: undo beats "Are you sure?" for frequent, reversible actions).
  Future<void> _remove(TodayTodo item) async {
    final index = _items.indexWhere((current) => current.id == item.id);
    final saved = await _commit([
      for (final current in _items)
        if (current.id != item.id) current,
    ]);
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed "${item.name}"'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => _commit(
              List.of(_items)..insert(index.clamp(0, _items.length), item),
            ),
          ),
        ),
      );
  }
```
  - Rows: replace `CheckboxListTile(… title: GestureDetector(onLongPress: …) …)`. The old long-press rename was invisible; a tap on the title now edits.
```dart
                child: ListTile(
                  leading: Checkbox(
                    value: item.isCompleted,
                    onChanged: _saving
                        ? null
                        : (value) => _commit([
                            for (final current in _items)
                              current.id == item.id
                                  ? current.copyWith(isCompleted: value ?? false)
                                  : current,
                          ]),
                  ),
                  title: Text(
                    item.name,
                    style: item.isCompleted
                        ? TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: scheme.onSurfaceVariant,
                          )
                        : null,
                  ),
                  onTap: _saving ? null : () => _rename(item),
                  trailing: IconButton(
                    tooltip: 'Remove ${item.name}',
                    onPressed: _saving ? null : () => _remove(item),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
```
  - Date: replace `_formattedDate()` with `MaterialLocalizations.of(context).formatFullDate(widget.today)` and delete the `_formattedDate` method and its weekday/month arrays.
  - Tokens:
    - `ListView` padding → `EdgeInsets.fromLTRB(Spacing.s16, Spacing.s12, Spacing.s16, Spacing.s24)` (no FAB lives here any more)
    - `SizedBox(height: 28)` → `Spacing.section`
    - `16` → `Spacing.s16`, `12` → `Spacing.s12`
    - row `bottom: 10` → `Spacing.s8`
    - `right: 4` → `Spacing.s4`
- `_FridgeBanner`: take `itemCount` (`int?`) and `expiringCount` (`int`), and rebuild at full contrast with theme type. This removes the 17/13 literals and the `white70`-on-78%-alpha subtitle that measured 2.17:1.
```dart
  String get _summary {
    final count = itemCount;
    if (count == null) return 'Snap a photo or pick foods to get recipes.';
    if (count == 0) return 'Empty — scan a photo to get started.';
    final items = count == 1 ? '1 item' : '$count items';
    return expiringCount == 0 ? '$items, all fresh' : '$items · $expiringCount expiring soon';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onBanner = theme.colorScheme.onPrimary;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenFridge,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [theme.colorScheme.primary, AppTheme.brandDark],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Spacing.s16),
            child: Row(
              children: [
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: onBanner.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(Icons.kitchen_outlined, color: onBanner, size: 28),
                ),
                const SizedBox(width: Spacing.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "What's in your fridge",
                        style: theme.textTheme.titleMedium?.copyWith(color: onBanner),
                      ),
                      const SizedBox(height: Spacing.s4),
                      Text(
                        _summary,
                        style: theme.textTheme.bodyMedium?.copyWith(color: onBanner),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, color: onBanner),
              ],
            ),
          ),
        ),
      ),
    );
  }
```
- `_EmptyChecklist`: vertical padding 28 → `Spacing.s24`, 12 → `Spacing.s12`, and change the text `'Tap + to add your first task for today.'` → `'Add your first task for today.'` (the whole card is the target).
- Add the skeleton:
```dart
/// Checklist-shaped placeholder shown while Home loads.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final block = Theme.of(context).colorScheme.surfaceContainerHigh;
    Widget box(double height, {double? width, double radius = AppRadius.md}) => Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: block,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
    return Semantics(
      label: 'Loading your checklist',
      child: ExcludeSemantics(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Spacing.s16, Spacing.s12, Spacing.s16, Spacing.s24),
          children: [
            box(16, width: 180),
            const SizedBox(height: Spacing.s16),
            box(80, radius: AppRadius.lg),
            const SizedBox(height: Spacing.section),
            box(24, width: 160),
            const SizedBox(height: Spacing.s12),
            for (var i = 0; i < 3; i++) ...[
              box(56, radius: AppRadius.lg),
              const SizedBox(height: Spacing.s8),
            ],
          ],
        ),
      ),
    );
  }
}
```
  A childless `Container` expands to the loose width `Align` offers, so `width: null` boxes render full-width.
- `lib/main.dart` → `_selectedPage` Home branch (add `import 'fridge/freshness.dart';`):
```dart
      final items = _fridgeItems;
      return MvpHomePage(
        // existing args, plus:
        fridgeItemCount: items?.length,
        expiringCount: items == null
            ? 0
            : items.where((stored) {
                final status = freshnessFor(stored.foodItem.expiryDate);
                return status == Freshness.expired || status == Freshness.expiringSoon;
              }).length,
      );
```

**Step 4: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 5: Verify visually** (both modes):
- Home opens with a grey skeleton (not a spinner).
- The date reads like "Saturday, September 26, 2026".
- The banner reads e.g. "6 items · 2 expiring soon" in solid white on a green-to-deep-green gradient.
- Tapping a task name opens "Edit task".
- The bin removes the task and shows "Removed … · Undo", which restores it at the same position.

Screenshot Home.

**Step 6: Commit**
```bash
git add lib/home/mvp_home_page.dart lib/main.dart test/mvp_home_page_test.dart
git commit -m "feat(home): live fridge summary banner, tap-to-edit, undo delete, skeleton and retry"
```

---

### Task 14: Large-text pass (200% without clipping)

**Files:**
- Create: `lib/design/text_scale.dart`, `test/large_text_test.dart`
- Modify:
  - `lib/fridge/selectable_fridge_grid.dart` (grid delegate)
  - `lib/fridge/fridge_item_card.dart` (padding, name lines)
  - `lib/main.dart` (`_MainPageState.build` toolbar height, `_HeaderTitle` gets `maxTitleLines`)

**Step 1: Write the failing test** (`test/large_text_test.dart`)
```dart
import 'package:diabetes/design/app_theme.dart';
import 'package:diabetes/exercise/data/today_todo_repository.dart';
import 'package:diabetes/home/mvp_home_page.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpAt200(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
      child: child!,
    ),
    home: Scaffold(body: body),
  ));
  await tester.pump();
}

StoredFoodItem _stored(String id, String name, int days) => StoredFoodItem(
  id: id,
  foodItem: FoodItem(
    name: name,
    amount: '1',
    foodType: FoodType.dairy,
    expiryDate: DateTime.now().add(Duration(days: days)),
  ),
);

void main() {
  testWidgets('Home', (tester) async {
    await pumpAt200(tester, MvpHomePage(
      userId: 'u',
      userName: 'Alexandria',
      todoStateStream: Stream.value(const TodayTodoState(
        isInitialized: true,
        items: [TodayTodo(id: 't', name: 'Prep lunch for tomorrow')],
      )),
      onSaveTodos: (_) async {},
      onOpenFridge: () {},
      fridgeItemCount: 12,
      expiringCount: 3,
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fridge grid', (tester) async {
    await pumpAt200(tester, FridgePage(
      initialItems: [
        _stored('a', 'Greek yogurt', 1),
        _stored('b', 'Chicken thighs', 5),
        _stored('c', 'Spinach', -1),
      ],
      onCommit: (_) async {},
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Greek yogurt'), findsOneWidget);
  });

  testWidgets('Fridge empty state', (tester) async {
    await pumpAt200(tester, FridgePage(initialItems: const [], onCommit: (_) async {}));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Agent', (tester) async {
    await pumpAt200(tester, const AgentPage(foodItems: []));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Recipe card', (tester) async {
    await pumpAt200(tester, ListView(children: [
      MealRecommendationCard(
        recommendation: const MealRecommendation(
          dishName: 'Spinach and feta omelette',
          imagePrompt: '',
          reason: 'Uses the spinach before it expires.',
          ingredients: ['2 eggs', '1 cup spinach'],
          instructions: ['Whisk the eggs.', 'Cook with spinach.'],
          estimatedCostPerServing: r'$2-3/serving',
        ),
        diabetesEnabled: false,
        timeLabel: '≤ 20 min',
        difficultyLabel: 'Beginner',
        onLogMeal: () {},
        onMakeBalanced: () {},
        onAsk: (scope, {String? initialQuestion}) {},
      ),
    ]));
    expect(tester.takeException(), isNull);
  });
}
```
Overflow errors ("A RenderFlex overflowed…") fail these tests automatically.

**Step 2: Run** `flutter test test/large_text_test.dart`. Expected: Fridge grid FAILs (the fixed-ratio tiles overflow). Note any other failures.

**Step 3: Implement**

`lib/design/text_scale.dart`:
```dart
import 'package:flutter/widgets.dart';

/// True when the user's text size is above 130%, the point where compact
/// layouts should switch to roomier ones (WCAG 1.4.4).
bool useLargeTextLayout(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) / 14 > 1.3;
```

`SelectableFridgeGrid.build`: replace the `const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 125, …, childAspectRatio: 0.95)` with
```dart
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: largeText ? 180 : 125,
                    mainAxisSpacing: Spacing.s12,
                    crossAxisSpacing: Spacing.s12,
                    mainAxisExtent: _tileExtent(context, largeText),
                  ),
```
with `final largeText = useLargeTextLayout(context);` at the top of `build`, plus:
```dart
  /// Tile height from the real text metrics, so names and pills never clip.
  double _tileExtent(BuildContext context, bool largeText) {
    final textTheme = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double line(TextStyle style) => scaler.scale(style.fontSize!) * (style.height ?? 1.2);
    return Spacing.s8 * 2 // card vertical padding
        + 36 + Spacing.s4 // icon tile + gap
        + line(textTheme.bodyMedium!) * (largeText ? 2 : 1) + Spacing.s4
        + line(textTheme.labelMedium!) + Spacing.s4; // pill text + its padding
  }
```
`FridgeItemCard.build`:
- padding `vertical: Spacing.s4` → `Spacing.s8`
- name `maxLines: 1` → `maxLines: useLargeTextLayout(context) ? 2 : 1`
- keep the pill's `vertical: 2` padding (2 + 2 is the `Spacing.s4` counted for the pill in `_tileExtent`)
- the `3` gap → `Spacing.s4`

The formula above assumes exactly these paddings, so keep them in sync.

`_MainPageState.build`: at the top add
```dart
    final largeText = useLargeTextLayout(context);
    final titleScale = math.min(MediaQuery.textScalerOf(context).scale(22) / 22, 2.0);
```
Set `toolbarHeight: 32 + (16 + 28 * (largeText ? 2 : 1)) * titleScale` (equal to 76 at 100%) and pass `maxTitleLines: largeText ? 2 : 1` to `_HeaderTitle`. That widget gets a `final int maxTitleLines;` field (default 1) used for the title `Text`'s `maxLines`.

Fix any other overflow the test reports with `Flexible`/`Expanded` + `maxLines`/wrap. Never lower the text scale.

**Step 4: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 5: Verify visually.** Set the OS or browser font to its largest (Chrome: Settings → Appearance → Font size "Very large", or Android display size + font size max). Fridge tiles grow to fit two-line names, the header shows the full name on two lines, and no screen shows yellow/black overflow stripes. Screenshot Fridge and Home.

**Step 6: Commit**
```bash
git add lib/design/text_scale.dart lib/fridge lib/main.dart test/large_text_test.dart
git commit -m "feat(a11y): adaptive fridge grid and header for large text, 200% overflow tests"
```

---

### Task 15: Meal log form (sections, chips/segments instead of dropdowns, carbs resolved)

The page currently has 5 dropdowns of 3–6 options, asks for carbs twice ("grams" and "band"), and has no headings.

**Files:**
- Modify: `lib/meals/screens/meal_log_page.dart` (`_MealLogPageState.build`, new label maps, `_SectionHeader`, `_FieldLabel`, `_formatTimestamp`)

`MealLogPage` constructs `MealRepository()` (Firestore) eagerly, so this task is verified in the running app.

**Step 1: Add label maps and helpers** to `_MealLogPageState`:
```dart
  static const _mealTypes = ['Meal', 'Breakfast', 'Lunch', 'Dinner', 'Snack', 'Drink'];
  static const _portionLabels = {
    MealPortion.smaller: 'Smaller',
    MealPortion.usual: 'Usual',
    MealPortion.larger: 'Larger',
  };
  static const _carbBandLabels = {
    CarbBand.unknown: 'Not sure',
    CarbBand.low: 'Low',
    CarbBand.medium: 'Medium',
    CarbBand.high: 'High',
  };
  static const _orderLabels = {
    MealOrder.together: 'All together',
    MealOrder.vegetablesFirst: 'Vegetables first',
    MealOrder.proteinFirst: 'Protein first',
    MealOrder.carbohydratesFirst: 'Carbs first',
    MealOrder.custom: 'Other',
  };
  static const _preparationLabels = {
    MealPreparation.fresh: 'Fresh',
    MealPreparation.leftover: 'Leftover',
    MealPreparation.reheated: 'Reheated',
  };

  String _formatTimestamp(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return '${localizations.formatMediumDate(_timestamp)}, '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(_timestamp))}';
  }
```
And these file-level widgets:
```dart
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Spacing.section, bottom: Spacing.s8),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Spacing.s12, bottom: Spacing.s8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}
```
Add `import '../../design/spacing.dart';`.

**Step 2: Restructure `build`'s `ListView` children** in this order. Keep the template `StreamBuilder` ("Quick log") first, unchanged except the spacing tokens.

1. `_SectionHeader('When')`
   - the meal-time `ListTile`, with `subtitle: Text(_formatTimestamp(context))`
   - `_FieldLabel('Meal type')`
   - `Wrap(spacing: Spacing.s8, runSpacing: Spacing.s8, children: [for (final type in _mealTypes) ChoiceChip(label: Text(type), selected: _mealType == type, onSelected: (_) => setState(() => _mealType = type))])`
2. `_SectionHeader('What')`
   - the photo `OutlinedButton.icon` + preview, with the preview wrapped in `ClipRRect(borderRadius: BorderRadius.circular(AppRadius.sm))`
   - the name field
   - `SizedBox(height: Spacing.s12)`
   - the restaurant field
   - `SizedBox(height: Spacing.s12)`
   - the components field
   - `_FieldLabel('Contains')`
   - three `FilterChip`s in a `Wrap` replacing the three `CheckboxListTile`s: `'Protein'` ↔ `_protein`, `'Substantial fat'` ↔ `_fat`, `'Fiber'` ↔ `_fiber`, each `onSelected: (value) => setState(() => _x = value)`
3. `_SectionHeader('How much')`
   - `_FieldLabel('Portion')`
   - `SegmentedButton<MealPortion>(showSelectedIcon: false, segments: [for (final v in MealPortion.values) ButtonSegment(value: v, label: Text(_portionLabels[v]!))], selected: {_portion}, onSelectionChanged: (s) => setState(() => _portion = s.first))`
   - `_FieldLabel('Carbohydrates')`, then the same `SegmentedButton<CarbBand>` shape with `_carbBandLabels`
   - `SizedBox(height: Spacing.s12)`
   - the carbs field, relabelled as an optional refinement:
```dart
            TextFormField(
              controller: _carbs,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Exact carbs in grams (optional)',
                helperText: 'Only if you know it. The band above is enough.',
                suffixText: 'g',
              ),
            ),
```
4. `_SectionHeader('Extras')`
   - `_FieldLabel('Eating order')`, then `Wrap` of `ChoiceChip`s over `MealOrder.values` with `_orderLabels`
   - `_FieldLabel('Preparation')`, then `SegmentedButton<MealPreparation>` with `_preparationLabels`
   - `SizedBox(height: Spacing.s12)`
   - the existing meal-balance `Card(ExpansionTile …)`, with margin → `EdgeInsets.symmetric(vertical: Spacing.s8)`
   - movement field
   - `SizedBox(height: Spacing.s12)`
   - notes field
5. `SizedBox(height: Spacing.s24)`, then the save button with label `_saving ? 'Saving…' : 'Save meal'`

Delete all five `DropdownButtonFormField`s and the three `CheckboxListTile`s. `ListView` padding → `Spacing.s16`. Also add `import '../../design/app_radius.dart';`.

**Step 3: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 4: Verify visually** (both modes). From a recipe, tap "Log this meal".
- The form reads in four headed sections (When / What / How much / Extras).
- The time shows as "Sep 26, 2026, 6:42 PM" (not ISO).
- Meal type and eating order are chips, and portion/carbs/preparation are segmented buttons.
- Carbs appear once as a band plus an optional grams field.
- Saving still works and the meal appears where it did before.

Screenshot the top and bottom of the form.

**Step 5: Commit**
```bash
git add lib/meals/screens/meal_log_page.dart
git commit -m "feat(meal-log): sectioned form with chips and segmented buttons; single carbs question"
```

---

### Task 16: Normalize tokens and remove dead code

**Files:**
- Modify:
  - `lib/main.dart` (auth, verification, fridge, camera, AddFood, Agent and card code)
  - `lib/fridge/fridge_item_card.dart`, `lib/fridge/selectable_fridge_grid.dart`
  - `lib/meals/screens/meal_qa_sheet.dart`

**Step 1: Radius literals → `AppRadius`**, in the in-scope files only:
```bash
grep -nE "circular\(([0-9]+)\)" lib/main.dart lib/fridge/*.dart lib/home/*.dart lib/meals/screens/meal_log_page.dart lib/meals/screens/meal_qa_sheet.dart
```
Mapping:
- 8 → `sm`
- 10 / 12 / 14 → `md`
- 16 / 18 / 20 → `lg`
- 24 → `xl`
- 999 → `full`

Skip `_GlucoseNoteChip` and `_EveningFitChip` (D/S).

**Step 2: Spacing literals → `Spacing`**, same files:
```bash
grep -nE "(EdgeInsets\.[a-zA-Z]+\([^)]*[0-9]|SizedBox\((height|width): [0-9])" lib/main.dart lib/fridge/*.dart lib/meals/screens/meal_qa_sheet.dart
```
Apply the mapping from `Spacing`'s doc comment (Task 2). Leave non-spacing sizes (icon sizes, the 180 image height, 36/48 boxes) literal.

**Step 3: Localized dates.** In `AddFoodSheet`, replace `_formatExpiryDate(_expiryDate!)` with `MaterialLocalizations.of(context).formatMediumDate(_expiryDate!)` and delete `_formatExpiryDate`. Confirm there are no other hand-built dates in scope:
```bash
grep -nE "padLeft\(2|weekdays|months = \[" lib/main.dart lib/home lib/fridge lib/meals/screens/meal_log_page.dart
```
Expected: no output.

**Step 4: Delete dead code.** `FoodItemTile` and `FoodImage` in `lib/main.dart` have been unused since the grid replaced them. Delete both, then check:
```bash
grep -rn "FoodItemTile\|FoodImage" lib test   # expect no output
```

**Step 5: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 6: Verify visually.** Click through Fridge (tile, edit sheet, camera sheet), Home, Meals (card, Q&A sheet) and Auth. Corners are consistent (16 on cards and tiles, 12 on buttons, fields and pills, 24 on sheets and dialogs), and the Add food expiry reads "Sep 28, 2026".

**Step 7: Commit**
```bash
git add lib
git commit -m "refactor(ui): apply radius and spacing tokens, localized dates, remove dead FoodItemTile"
```

---

### Task 17: Copy pass (sentence case, consistent verbs, no dev-speak)

**Files:**
- Modify: `lib/main.dart`, `lib/fridge/freshness.dart`, `lib/fridge/selectable_fridge_grid.dart`
- Tests: `test/fridge_item_card_test.dart`, `test/widget_test.dart`, `test/fridge_save_workflow_test.dart`, `test/fridge_camera_sheet_test.dart`

**Step 1: Update tests first** to the new strings:
- `'Expiring Soon'` → `'Expiring soon'` (`fridge_item_card_test.dart`)
- `'Save Food'` → `'Save food'`, `'Save Changes'` → `'Save changes'` (`widget_test.dart`, `fridge_save_workflow_test.dart`)
- `'Upload a screenshot/picture'` → `'Upload a photo'` (`fridge_camera_sheet_test.dart`)

Run them and they fail.

**Step 2: Apply the string changes**

| Where | Old | New |
|---|---|---|
| `Freshness.expiringSoon` | `'Expiring Soon'` | `'Expiring soon'` |
| `AddFoodSheet` title | `'Add Food'` / `'Edit Food'` | `'Add food'` / `'Edit food'` |
| `AddFoodSheet` photo button | `'Add Picture'` / `'Change Picture'` | `'Add photo'` / `'Change photo'` |
| `AddFoodSheet` save | `'Save Changes'` / `'Save Food'` | `'Save changes'` / `'Save food'` |
| `FridgeCameraSheet._buildChooser` | `'Upload a screenshot/picture'` | `'Upload a photo'` |
| `FridgeCameraSheet._buildCameraMode` | `'Take Picture'` / `'Scanning...'` | `'Take picture'` / `'Capturing…'` |
| `FridgeCameraSheet._buildCameraPreview` body (40 words) | `'The camera is usually in use by another app …'` | `'Close other apps using it, or upload a photo instead.'` |
| `_EmailVerificationPageState` | `'Checking...'` / `'Sending...'` | `'Checking…'` / `'Sending…'` |
| `_AgentPageState._setUseMealBalance` | `'Could not save that Agent preference.'` | `"Couldn't save that preference. Try again."` |
| `FridgePageState.confirmLeave` save button | `'Save'` | `'Save changes'` |

**Step 3: Hide unbuilt bulk actions.** In `FoodBulkAction`, delete `compareCarbs`, `totalCarbs`, `totalCalories`, `saveMeal` and `groceryList` (no UI reaches them). Then simplify `FridgePageState._handleBulkAction` to:
```dart
  Future<void> _handleBulkAction(
    BuildContext context,
    FoodBulkAction action,
    List<FoodItem> foods,
  ) async {
    if (action != FoodBulkAction.addToMeal) return;
    await widget.onAddSelectedToMeal?.call(foods);
  }
```

**Step 4: Check that no title-case labels remain** in scope:
```bash
grep -nE "Text\('([A-Z][a-z]+ )+[A-Z][a-z]+'\)" lib/main.dart lib/home lib/fridge lib/meals/screens/meal_log_page.dart
```
Expected: only proper nouns (`'Wellness Companion'`, `'Meal Lab'`), or nothing.

**Step 5: Run** `flutter test && flutter analyze`. Expected: PASS, no issues.

**Step 6: Verify visually.** Skim every in-scope screen in both modes. All buttons and titles are sentence case, auth uses "Sign in", "Create account" and "Sign out" consistently, and the camera error is one short line.

**Step 7: Commit**
```bash
git add lib test
git commit -m "copy: sentence case, consistent auth verbs, shorter camera error, drop unbuilt bulk actions"
```

---

### Task 18: Lock it in (accessibility guideline tests + full verification)

**Files:**
- Create: `test/accessibility_guidelines_test.dart`

**Step 1: Write the test**
```dart
import 'package:diabetes/design/app_theme.dart';
import 'package:diabetes/exercise/data/today_todo_repository.dart';
import 'package:diabetes/home/mvp_home_page.dart';
import 'package:diabetes/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> check(WidgetTester tester, Widget home) async {
  final semantics = tester.ensureSemantics();
  await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: home));
  await tester.pump();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  semantics.dispose();
}

void main() {
  testWidgets('Auth', (tester) => check(tester, const AuthPage()));

  testWidgets('Fridge', (tester) => check(tester, Scaffold(
    body: FridgePage(
      initialItems: const [
        StoredFoodItem(
          id: 'a',
          foodItem: FoodItem(name: 'Milk', amount: '1', foodType: FoodType.dairy),
        ),
      ],
      onCommit: (_) async {},
    ),
  )));

  testWidgets('Fridge empty', (tester) => check(tester, Scaffold(
    body: FridgePage(initialItems: const [], onCommit: (_) async {}),
  )));

  testWidgets('Home', (tester) => check(tester, Scaffold(
    body: MvpHomePage(
      userId: 'u',
      todoStateStream: Stream.value(const TodayTodoState(
        isInitialized: true,
        items: [TodayTodo(id: 't', name: 'Walk')],
      )),
      onSaveTodos: (_) async {},
      onOpenFridge: () {},
      fridgeItemCount: 3,
    ),
  )));

  testWidgets('Agent', (tester) => check(tester, const Scaffold(body: AgentPage(foodItems: []))));
}
```

**Step 2: Run** `flutter test test/accessibility_guidelines_test.dart`. Fix real failures in the widget rather than weakening the test:
- tap targets under 48dp: add `minimumSize` or wrap with a `ConstrainedBox`
- unlabeled icon buttons: add a `tooltip`
- low-contrast text: use `onSurface`/`onSurfaceVariant` on the right container

If `textContrastGuideline` flags the brand gradient because of its pixel sampling, confirm the pair with `test/support/contrast.dart` and note it in the commit message.

**Step 3: Full verification**
```bash
flutter test          # expect: All tests passed!
flutter analyze       # expect: No issues found!
```
Then run both modes (`flutter run -d chrome` and `flutter run -d chrome --dart-define=DIABETES_ENABLED=true`) and walk the whole loop:
1. sign up / sign in
2. empty fridge → scan (dialog, cancel, retry)
3. edit/delete via sheet → save bar
4. Home banner counts, task undo
5. Meals: example chip → recommend (skeleton) → card → ask a line → log meal (sectioned form)
6. account sheet → sign out with unsaved-changes guard

Repeat steps 2, 4 and 5 at the largest browser font size. Screenshot each step for the user.

**Step 4: Commit**
```bash
git add test/accessibility_guidelines_test.dart lib
git commit -m "test(a11y): tap-target, label and contrast guideline tests for in-scope screens"
```
