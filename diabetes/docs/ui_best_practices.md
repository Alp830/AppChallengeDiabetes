# UI Best Practices: Wellness Companion

Audit of the Flutter app in `diabetes/lib` (September 2026) against mobile, Material 3 (M3), accessibility and health-app practice. Scores: 5 = nothing to change, 1 = actively hurts the app. Contrast ratios were measured on the real seeded `ColorScheme` (probe at `/tmp/schemeprobe`). Items tagged **(D/S)** are diabetes or sleep surfaces. They are covered here but excluded from the implementation plan, which is limited to the meal tracker, Agent, Fridge and Home.

## Best Practice (1): Color roles and palette coherence

### Description (1)
M3 assigns every color a semantic role (primary, secondary, tertiary, their containers, `on*` foregrounds, and tone-based `surfaceContainer*` levels). Each `X`/`onX` pair is generated to meet contrast, so overriding one half of a pair without the other breaks that guarantee. Surfaces should be separated by tonal container roles, not ad-hoc shadows or borders, and custom components should map to existing roles instead of literal colors. *Sources: M3 Color roles; M3 Advanced color customizations; M3 Tone-based surfaces blog; M3 Elevation.*

### Application to App (1)
* **2/5: `AppTheme.light()` secondary pair** (`lib/design/app_theme.dart`). *Why:* `secondary` is overridden to apricot `#F2A65A` but `onSecondary` stays white (2.02:1), while `secondaryContainer` stays seed mint `#CFE9D9`. Every tonal component (`IconButton.filledTonal` on Home, M3 nav indicator, tonal buttons) therefore renders green, not apricot, and the "warm accent" is a single token nobody sees. *How:* either drop the apricot override and let the seed generate secondary, or override the whole family (`secondary` #A15C0E, `onSecondary` white, `secondaryContainer` #FFDCC0, `onSecondaryContainer` #3A1D00) so the accent works in tonal components.
* **2/5: Hard-coded colors outside the scheme** (`_GlucoseTimelinePainter` `Colors.orange`/`Colors.purple` in `lib/cgm/screens/glucose_context_card.dart`; five hex colors in `lib/meals/screens/meal_balance_page.dart` lines 590–774) **(D/S)**. *Why:* they ignore the theme and clash with the green palette. *How:* map meal markers to `tertiary` and workouts to `secondary`, and put balance-component colors in a single `AppChartColors` extension.
* **3/5: Page vs card surfaces** (`_scaffold #F5F7F4` vs white `CardThemeData`). *Why:* white cards on sage are 1.08:1 apart, so the 1.23:1 hairline does all the separating and cards visually melt into the page. *How:* keep the hairline but set `scaffoldBackgroundColor` to `surfaceContainerLow` (#EFF5EF) so cards read as raised by tone, per M3 tone-based surfaces.
* **4/5: Freshness palette** (`lib/fridge/freshness.dart`). *Why:* a distinct, high-contrast status set is exactly right. *How:* move it into a `ThemeExtension` so the palette lives in one theme file.

## Best Practice (2): Text and non-text contrast

### Description (2)
WCAG 2.2 AA requires 4.5:1 for normal text and 3:1 for large text (≥18pt, or ≥14pt bold). Button labels count as text. Visual boundaries that identify a control, such as an input's border and focus indicators, need 3:1 against adjacent colors (SC 1.4.11). Apple repeats the 4.5:1 rule for text up to 17pt, and M3 notes that low-vision users depend on these pairings. This matters more here because CDC puts diabetic retinopathy at 28.4% of people with diabetes aged 65–79, and it is the leading cause of blindness in working-age US adults. *Sources: W3C Understanding 1.4.3; W3C Understanding 1.4.11; Apple HIG Accessibility; M3 Accessibility–color contrast; CDC VEHSS DR prevalence; CDC Vision loss and diabetes.*

### Application to App (2)
* **1/5: White on brand green `#2F8F6B` = 3.99:1** (every `FilledButton`, FAB, selected `CirclePageButton`, `_FridgeBanner`). *Why:* it fails AA on the most-pressed element in the app, for the audience most likely to have low vision. *How:* set `primary` to `#267A5B` (5.23:1 on white, same hue). Keep `#2F8F6B` only as a decorative `brand` constant.
* **1/5: `_FridgeBanner` subtitle** (`lib/home/mvp_home_page.dart`). *Why:* `Colors.white70` 13px text on a gradient that fades to 78% alpha over the page measures 2.17:1, and the title at the light end measures 2.89:1. *How:* gradient from `primary` to `#1F6B4E` at full opacity with a solid white subtitle (≥5.2:1 everywhere).
* **2/5: Input boundaries** (`InputDecorationTheme.enabledBorder` uses hairline `#E4E9E4`). *Why:* white fields on white sheets (`AddFoodSheet`, preferences sheet) have a 1.23:1 boundary and are near-invisible. *How:* enabled border = `scheme.outline` (#707973, 4.5:1), keeping the 2px primary focus ring.
* **2/5: `_InfoPill`** (`lib/main.dart`, "From your fridge…", "$2-3/serving"). *Why:* 11px `labelSmall` muted text on `surfaceContainerHighest` = 4.01:1, which fails. *How:* `onSurface` text on `surfaceContainerHigh` at `labelMedium`.
* **4/5: Body, muted and freshness text.** *Why:* ink ≥13:1, muted `#63706A` 4.81–5.18:1, and freshness colors on their tints 5.0–7.7:1 all pass AA. *How:* nothing required. Correct the "AAA" comment in `freshness.dart` (Expired and Expiring Soon are AA only).

## Best Practice (3): Never use color as the only signal (design for diabetic color vision)

### Description (3)
Color must not be the only means of conveying information (WCAG 1.4.1), so pair it with text, shape, position or pattern. Diabetes specifically causes an acquired blue–yellow (tritan) deficit that appears even before visible retinopathy and grows with severity, so blue/green and yellow/violet distinctions are the least reliable pairs for this audience. When glucose is charted, users and clinicians already know the standardized AGP color language (green in range, yellow/orange high, red low), so reuse it rather than inventing one. *Sources: W3C WCAG 2.2 (1.4.1); PubMed 3495070 (blue–yellow deficits in diabetes); PMC7914308 (review, psychophysics of DR); NEI Types of color vision deficiency; NIDDK Clinical targets for CGM data (Battelino 2019).*

### Application to App (3)
* **4/5: Fridge freshness** (`FridgeItemCard`). *Why:* color is always paired with a text label. *How:* keep. Also consider adding a leading glyph (✕ expired, ! soon) so the pill works for tritan users at a glance.
* **3/5: Selected fridge tile.** *Why:* the selection state is a green border plus `check_circle`, which is good, but the unselected corner shows an X in the same spot, so "selected" and "delete" swap in one position. *How:* see BP 10. Put selection in a fixed top-left checkbox slot.
* **2/5: `_GlucoseTimelinePainter` legend and in-range band (D/S).** *Why:* meal dots vs workout bars rely on orange vs purple, and the in-range band is `primaryContainer` at 45% alpha, which is faint mint that tritan users lose against white. *How:* use AGP green for the band at stronger alpha, keep shape (dot vs bar) as the primary cue, and add labels on tap.
* **2/5: `_GlucoseNoteChip` (D/S)** uses tertiary slate-blue, a hue family diabetic users discriminate worst. *How:* use `secondaryContainer` (warm) with the lightbulb icon.

## Best Practice (4): Typography scale and typeface

### Description (4)
M3 defines five roles (display, headline, title, body, label) × three sizes, so all text should come from `textTheme` roles rather than literal sizes, and emphasis should use the scale's weights. Body text should stay ≥16/24, and Apple's HIG sets 11pt as the absolute floor. A single well-chosen family is enough. For low-vision audiences, Atkinson Hyperlegible Next (Braille Institute, 2025, variable 200–800) differentiates commonly confused glyphs (1/l/I, 0/O), which matters for numbers like "2 cups", "$2-3" and glucose values. *Sources: M3 Typography overview; M3 Type scale tokens; Flutter `text_theme.dart` spec table; Apple HIG Accessibility; Braille Institute Atkinson Hyperlegible; Google Fonts Atkinson Hyperlegible Next.*

### Application to App (4)
* **2/5: `AppTheme` text theme only restyles 4 of 15 roles**, and the platform font gives Roboto on Android, SF on iOS and whatever the browser has on web. *Why:* the app has no typographic identity and looks different per platform. *How:* bundle Atkinson Hyperlegible Next as an asset font (no runtime fetch, works offline and on web) and set weights for all title/label roles.
* **2/5: Literal font sizes bypass the scale.** `_FridgeBanner` uses `TextStyle(fontSize: 17)` and `13`, `FridgeItemCard` freshness pill uses `fontSize: 10`, and `_HeaderTitle` uses `fontSize: 22`, six literals in total. *Why:* 10px is below Apple's 11pt floor on the most-glanced label in the Fridge, and literals drift from the theme. *How:* banner → `titleMedium`/`bodyMedium`, pill → `labelMedium`, header → `titleLarge`.
* **3/5: Recipe card body text** (`MealRecommendationCard`). *Why:* ingredients and steps are `bodyMedium` (14/20) and the reason paragraph has no emphasis, which is readable but dense. *How:* `bodyLarge` for steps, since people cook from this card at arm's length.

## Best Practice (5): Support large text and display scaling

### Description (5)
Users must be able to scale text to 200% without loss of content (WCAG 1.4.4, Apple Dynamic Type). Flutter `Text` honors the OS setting, and Flutter's checklist says to test the smallest phone at the largest font setting. Avoid fixed heights and `maxLines: 1` on meaningful text. `MediaQuery.textScalerOf` replaces the deprecated `textScaleFactor` because Android scales nonlinearly. *Sources: W3C WCAG 2.2 (1.4.4); Apple HIG Accessibility; Flutter docs UI design & styling; Flutter docs SafeArea & MediaQuery; Flutter Accessibility testing.*

### Application to App (5)
* **2/5: `SelectableFridgeGrid`** (`maxCrossAxisExtent: 125`, `childAspectRatio: 0.95`) with `FridgeItemCard` names at `maxLines: 1`. *Why:* at 200% text, "Greek yogurt" truncates to "Gr…" and the pill clips inside a fixed-ratio tile. *How:* when `textScaler.scale(1) > 1.3`, widen to `maxCrossAxisExtent: 180`, allow 2 name lines, and use `mainAxisExtent` sized from text metrics instead of a fixed ratio.
* **3/5: `_HeaderTitle`** (`toolbarHeight: 76`, both lines `maxLines: 1`). *Why:* long display names ellipsize at large text sizes. *How:* compute `toolbarHeight` from `textScaler` and allow wrapping at >1.3.
* **3/5: 225 `height: <literal>` sites across `lib/`.** *Why:* each is a potential clip at large text (e.g., the 180px recipe image is fine, a text container is not). *How:* add a widget test that pumps Home, Fridge and Agent at `TextScaler.linear(2.0)` and asserts no overflow.

## Best Practice (6): Spacing and layout grid

### Description (6)
M3 spacing is built on an 8dp base (`space100`) with 4dp half-steps. The standard compact-window margin is 16dp, and phones (<600dp) use a single column. Consistent spacing is itself a grouping signal: related items sit closer together than unrelated ones (proximity). *Sources: M3 Spacing tokens; M3 Grids & spacing; M3 Breakpoints; NN/g 5 Principles of Visual Design.*

### Application to App (6)
* **3/5: `Spacing` tokens exist but are opt-in** (`lib/design/spacing.dart`). *Why:* `lib/` has 64 literal `16`s plus off-grid `20`, `28`, `10`, `6`, `3` (e.g., `_HomeContent` gap 28, `_FridgeBanner` padding 20, `titleSpacing: 20`), so rhythm drifts between screens. *How:* add `s20`→`s24` mapping rules, replace literals in the four in-scope screens, and add `Spacing.section = 24`.
* **2/5: `SelectableFridgeGrid` bottom padding `280`.** *Why:* 280px of dead scroll under the grid, sized for two stacked FABs and a toolbar. *How:* `96` plus `MediaQuery.paddingOf(context).bottom` once the FAB count is one (BP 8).
* **3/5: Web/desktop uses the phone layout stretched** (only Auth has `maxWidth: 420`). *Why:* at ≥600dp the Agent field and recipe cards span the whole window. *How:* wrap tab bodies in `ConstrainedBox(maxWidth: 640)` centered.

## Best Practice (7): Visual hierarchy and action emphasis

### Description (7)
Hierarchy tells the eye what matters first through size, color/contrast and grouping, and the "squint test" checks that the most important thing is still visible. M3 reserves one high-emphasis action per screen or group (filled button or FAB): tonal/outlined for secondary actions, text buttons for tertiary, and only one FAB per screen because multiple FABs compete. *Sources: NN/g Visual hierarchy in UX; NN/g Squint test; M3 All buttons; M3 Buttons overview; M3 Extended FAB guidelines.*

### Application to App (7)
* **1/5: Two stacked FABs on `FridgePage`** (camera + add). *Why:* M3 explicitly says one FAB per screen, and here the primary job (scan) and a secondary job (type an item) look equally important. *How:* one `FloatingActionButton.extended` "Scan fridge" (camera icon), with "Add manually" as a small tonal FAB above it or inside the scan sheet's chooser.
* **2/5: `MealRecommendationCard` action stack.** *Why:* up to four full-width buttons (Make it more balanced?, post-meal walk, Log this meal, Meal Lab) plus chips, and with 5 recommendations the page shows 5 filled "Log this meal" buttons. *How:* one filled "Log this meal" per card, "Make it more balanced" as a tonal button beside it, and Meal Lab moved out of the per-results area to a single entry (Agent header).
* **2/5: `SelectableFridgeGrid` selection toolbar.** *Why:* the destructive "Remove" is the filled (primary-looking) button while the useful "Meal" is a text button, which inverts the hierarchy. *How:* "Add to meal" filled, "Remove" as an outlined error-colored button.
* **2/5: `_FridgeSaveControls` pinned top-right.** *Why:* an unsaved-changes bar at the top corner is the hardest spot to reach and overlaps the grid header; with two FABs bottom-right, the screen has three competing action clusters. *How:* move Save/Discard into a bottom bar (same slot as the selection toolbar) with "N unsaved changes" text visible, not in a tooltip.
* **3/5: `MvpHomePage`.** *Why:* the loudest element is `_FridgeBanner`, a shortcut to a tab already one tap away in the nav, while the actual Home content (checklist) is secondary. *How:* keep the banner but make it tell you something (item count, "3 expiring soon"), which turns navigation chrome into information.

## Best Practice (8): Navigation

### Description (8)
Bottom navigation bars suit 3–5 equal top-level destinations. With three destinations M3 shows icons and text labels on all items, and the selected item is marked by an active-indicator pill plus label weight. NN/g finds that icons alone are rarely universal: labels make targets faster to recognize and larger to hit, and tooltips don't exist on touch. The same icon must never mean two things (consistency). *Sources: Android Developers Navigation bar (M3); Android NavigationBarItem API; NN/g Icon usability; NN/g Top 10 application-design mistakes; NN/g Consistency and standards.*

### Application to App (8)
* **1/5: `CirclePageButton` bar in `MainPage.build`.** *Why:* three unlabeled circles (kitchen, home, robot), so "Agent" behind a robot icon is a guess. The custom bar is ~88px + safe area tall, has no active-indicator convention, and double-scales the icon (see BP 16). *How:* replace it with M3 `NavigationBar` + `NavigationDestination` labels "Fridge / Home / Meals", with `selectedIcon` filled and `icon` outlined, and keep Home in the middle.
* **2/5: Header actions in `MainPage.appBar`.** *Why:* the `tune` icon means "Glucose & data settings" in the header and "Preferences" on the Agent tab (the same icon for two meanings), and Log out is a one-tap icon next to it. *How:* replace both header icons with one avatar/`account_circle` button opening an account sheet (name, email, Glucose & data sources (D/S), Log out).
* **3/5: Pushed pages center their titles** (`AppBarTheme.centerTitle: true`) while the shell is left-aligned. *Why:* Android convention is start-aligned, and the app mixes both. *How:* remove the override and let Flutter use the platform default.

## Best Practice (9): Touch targets and thumb reach

### Description (9)
Minimum targets are 48×48dp (M3, Flutter's `androidTapTargetGuideline`) and 44×44pt (Apple). WCAG 2.2 AA sets 24×24 CSS px as the absolute floor. Hoober's field study of 1,333 users found 49% operate one-handed with a thumb, and people tap most accurately in the center half to two-thirds of the screen, so corners are the worst place for small or frequent targets. *Sources: W3C Understanding 2.5.8; Apple HIG Accessibility; Flutter Accessibility testing; Hoober 2013 UXmatters; Hoober 2015 ACM Interactions.*

### Application to App (9)
* **1/5: `FridgeItemCard` delete X.** *Why:* a 28×28 target (17px icon) in the tile's top-right corner, directly beside the tap-to-edit area, below M3/Apple minimums and in the least accurate zone. *How:* remove per-tile delete (delete lives in the edit sheet and selection toolbar) and show a 48dp selection checkbox slot only in selection mode.
* **3/5: `_FridgeSaveControls` buttons** are 40px tall and top-right. *How:* 48px, in the bottom bar (BP 7).
* **3/5: `MvpHomePage` task rename is long-press on the title.** *Why:* it's an invisible gesture, and the only visible actions (checkbox, trash) sit at opposite edges. *How:* tap the title to edit (open the dialog) and keep the checkbox for completion.
* **4/5: `FilledButton` minimum 52px and header `IconButton`s at 48px.** *How:* keep.

## Best Practice (10): Loading and system-status feedback

### Description (10)
Response-time limits: 0.1s feels instant, 1s keeps flow (show that the system is working), and after 10s show progress and allow cancel. Use skeleton screens for full-page loads, spinners only for short localized waits (<~3s), and no indicator for loads under 1s since a flash is worse than nothing. Never add artificial delay to real work. *Sources: NN/g Response time limits; NN/g Skeleton screens 101; NN/g Designing for waits and interruptions.*

### Application to App (10)
* **1/5: `_MainPageState._selectedPage` creates a new Firestore `snapshots()` stream on every build.** *Why:* each tab switch re-subscribes, so `StreamBuilder` returns to `waiting` and flashes a full-screen `CircularProgressIndicator` over the tab-change animation. *How:* create the fridge stream once in `initState` (keyed by uid) and pass it down.
* **2/5: `_AgentPageState._loadRecommendation` wraps Gemini in `Future.wait([..., Future.delayed(1s)])`.** *Why:* it adds up to 1s of fake latency to every request, including "Make it more balanced". *How:* remove the delay, and replace the inline spinner with a skeleton recipe card (image block plus three text lines) so the wait previews the result.
* **2/5: `FridgePageState._takeFridgePhoto` feedback is only a snackbar, "Scanning fridge photo...".** *Why:* a 5–15s AI scan shows only a snackbar, with no progress, no cancel, and the grid stays editable, so users re-tap the camera. *How:* keep the camera sheet open in a "Finding foods…" state with the captured photo dimmed, a `LinearProgressIndicator`, and a Cancel button.
* **3/5: `MvpHomePage` and `MealRecommendationCard` image load.** *Why:* Home uses a centered spinner (a skeleton checklist would fit), while the recipe image's determinate progress is good. *How:* skeleton rows on Home.

## Best Practice (11): Empty states and first run

### Description (11)
Empty states should say what the space is for, why it's empty, and give a direct path to fill it: they are the cheapest teaching moment in the product. Skip up-front onboarding tours where possible, since NN/g found tutorial skippers performed as well. Contextual, task-based hints beat slideshows, and the login screen should still say what the app does. *Sources: NN/g Designing empty states in complex applications; NN/g Mobile-app onboarding; NN/g Mobile tutorials; NN/g Onboarding: skip it when possible.*

### Application to App (11)
* **1/5: `FridgePage` empty state `Center(child: Text('No food added yet.'))`.** *Why:* this is step 2 of the core loop for every new user, and it's one plain sentence with no icon, no action and no explanation. *How:* an icon, the title "Your fridge is empty", the line "Scan a photo of your fridge or add foods one by one — we'll suggest meals from them.", a filled "Scan fridge" button and a text "Add manually" button.
* **2/5: `AuthPage`.** *Why:* the headline is "Sign In" with no app name, logo or purpose, and there's no forgot-password path at all (no `sendPasswordResetEmail` anywhere in `lib/`). *How:* add the wordmark "Wellness Companion", the one line "Turn what's in your fridge into meal ideas.", and a "Forgot password?" text button.
* **3/5: `AgentPage` initial state.** *Why:* the only guidance is the hint "e.g., Something with eggs", and the page below the Preferences button is blank. *How:* add 3 example `ActionChip`s ("Quick breakfast", "Use what's expiring", "Under $5") that fill the prompt.
* **4/5: `_EmptyChecklist`** has an icon, title and hint, and is tappable. *How:* keep. Change "Tap + to add" to "Add your first task", since the whole card is the target.

## Best Practice (12): Error messages and recovery

### Description (12)
Errors should be visible, in plain human language, precise about what happened, constructive about the fix, and never blame the user or expose internals (NN/g heuristic #9). Form errors belong next to the field. M3 snackbars are for brief status with at most one action and must not be the only way to reach a core task. For AI, "errors" include wrong or unexpected output, so offer a graceful path forward. *Sources: NN/g Error-message guidelines; NN/g Hostile patterns in error messages; NN/g 10 guidelines for reporting errors in forms; M3 Snackbar guidelines; Google PAIR Errors + graceful failure.*

### Application to App (12)
* **1/5: Raw exceptions shown to users.** `'Could not load fridge items: ${snapshot.error}'` (`MainPage`), `'Could not scan fridge photo: $error'`, `'Could not save changes: $error'`, `'Authentication failed: $error'`, `'Google sign-in failed: $error'` (`lib/main.dart`), plus 3 more in `exercise_page.dart` (D/S). *Why:* stack-trace text such as `[cloud_firestore/unavailable]…` is noise to users. *How:* map to fixed messages ("Couldn't reach the server. Check your connection and try again.") with a Retry action, and `debugPrint` the raw error.
* **1/5: `_AgentPageState` error text is "Gemini was not available. Check your API key and try again. ($error)".** *Why:* end users have no API key. It's a developer message, shown in red text with no retry. *How:* "Couldn't get a meal idea right now." with a "Try again" button that re-runs `_lastRequest`.
* **2/5: `MvpHomePage` "Could not load your home screen."** *Why:* a dead end with no retry. *How:* add a Retry button that re-subscribes.
* **3/5: `AuthPage` validators.** *Why:* errors appear inline, which is good, but Firebase's `error.message` strings are technical. *How:* map `invalid-credential`, `email-already-in-use`, `weak-password` and `network-request-failed` to plain text.

## Best Practice (13): Destructive actions, confirmation and undo

### Description (13)
Prefer immediate action plus a visible Undo (snackbar) for frequent, reversible deletes, and reserve confirmation dialogs for rare, high-impact, irreversible actions, since users habituate to "Are you sure?". A confirmation must name the object and consequence and label the button with the verb ("Delete 3 items"), not "OK". *Sources: NN/g Confirmation dialogs; NN/g UI accelerators; M3 Snackbar guidelines (Undo action).*

### Application to App (13)
* **1/5: Log out** (`_HeaderAction` → `FirebaseAuth.instance.signOut()`). *Why:* one tap, no confirmation, and it bypasses `FridgePageState.confirmLeave()`, so unsaved fridge drafts are silently lost. *How:* move it into the account sheet (BP 8) and run the same unsaved-changes guard before signing out.
* **2/5: `MvpHomePage` task delete.** *Why:* the trash icon deletes instantly with no undo. *How:* delete, then show a snackbar "Task removed" with an Undo action that restores the previous list.
* **2/5: `_MealLabView` "Delete meal" popup item** (`lib/meals/screens/meal_lab_page.dart`) **(D/S)**. *Why:* it permanently deletes a Firestore meal with no confirmation and no undo. *How:* snackbar undo, or a named confirmation.
* **4/5: `SelectableFridgeGrid` bulk delete dialog "Delete N items?" / "Delete".** *How:* keep, and change the button to "Delete N items".

## Best Practice (14): Forms and inputs

### Description (14)
Use visible labels above or inside fields (never placeholder-only), and mark optional fields. Show errors inline. Use radio buttons, chips or segmented buttons instead of dropdowns for short option sets (NN/g: avoid dropdowns below ~5 options), and group long forms into titled sections. On login, offer "show password" (masked by default) and support autofill. Choose keyboard types that match the data. *Sources: NN/g Placeholders in form fields are harmful; NN/g Website forms usability top 10; NN/g Dropdowns design guidelines; NN/g Does your form really need a dropdown?; NN/g Checklist for registration and login forms on mobile; NN/g Group form elements with white space.*

### Application to App (14)
* **1/5: 28 fields override the theme with `border: OutlineInputBorder()`** (`AuthPage`, `AddFoodSheet`, `_AgentPageState` prompt, preferences and feedback fields). *Why:* this silently replaces the themed 14px radius, fill and hairline with a 4px default, so the app has two input styles, and `CURRENT_UI.md` documents only one. *How:* delete the `border:` line in all 28 sites and fix the theme borders once (BP 2).
* **2/5: `MealLogPage`.** *Why:* one long form with 5 dropdowns (meal type, portion, carb band, meal order, preparation) of 3–5 options each, "Carbohydrate grams" and "Carbohydrate band" asking the same thing twice, and no section headings. *How:* group into When / What / How much / Extras, convert ≤5-option dropdowns to `SegmentedButton` or `ChoiceChip`s, and show carb grams as an optional refinement beneath the band.
* **2/5: `AuthPage` password.** *Why:* no show/hide toggle, no forgot-password path, the login validator says "Use at least 6 characters" (a sign-up rule shown at login), and `AutofillGroup` is missing. *How:* add a visibility `IconButton` suffix, "Forgot password?" and `AutofillGroup`, and apply the length rule on sign-up only.
* **3/5: `AddFoodSheet` expiry field** shows `2026-09-26` ISO text. *How:* format with `MaterialLocalizations.of(context).formatMediumDate`.
* **3/5: `_showMealTypePicker`.** *Why:* a bottom sheet with custom radio icons, for 5 options. *How:* a `ChoiceChip` row inline under the prompt (saves a sheet and a tap).

## Best Practice (15): Motion

### Description (15)
Motion should be brief, purposeful and use system tokens: M3's suggested pairs are emphasized 500ms (on-screen), emphasized-decelerate 400ms (enter), emphasized-accelerate 200ms (exit), standard 300ms (utility). M3 Expressive is migrating to spring physics. When Reduce Motion is on, replace slides, scales and bounces with fades, and never make users wait for an animation. *Sources: M3 Easing and duration (applying + tokens); M3 Motion overview (physics system); Apple HIG Motion; Apple HIG Accessibility.*

### Application to App (15)
* **3/5: `CirclePageButton` scales twice.** *Why:* `TweenAnimationBuilder` scales the circle to 1.08 *and* `AnimatedScale` scales the icon to 1.08 inside it, with `easeOutBack` overshoot, so the bounce is doubled. *How:* removed when the bar is replaced with `NavigationBar` (BP 8).
* **4/5: `MainPage` `AnimatedSwitcher` fade + 7% slide, 238ms, zero duration under `disableAnimations`.** *Why:* subtle and respects reduce-motion, which is good. *How:* under reduce-motion, keep a 150ms fade instead of an instant cut, per Apple, and move the magic number to an `AppMotion` token class (`short = 200ms`, `medium = 300ms`, `emphasized = Easing.emphasizedDecelerate`).
* **3/5: No shared transitions.** *Why:* pushed pages (`MealLogPage`) use the default route while sheets animate in, so there's no spatial link between a recipe card and its log page. *How:* optional. Set `pageTransitionsTheme` to `FadeForwardsPageTransitionsBuilder` for consistency.

## Best Practice (16): Copy, tone and capitalization

### Description (16)
Tone has four dimensions (funny–serious, formal–casual, respectful–irreverent, enthusiastic–matter-of-fact), so pick a point and hold it everywhere. Button labels should be short, specific verbs in sentence case ("Save changes"), and the same action must keep the same word across the app (not "Sign in" in one place and "Log in" in another). Put information-carrying words first. *Sources: NN/g Four dimensions of tone of voice; NN/g Impact of tone of voice on brand perception; USWDS Button; Apple HIG Writing; NN/g Consistency and standards; NN/g How users read on the web.*

### Application to App (16)
* **2/5: Mixed capitalization.** "Recommend a Meal", "Suggest Something Else", "Take Picture", "Save Food", "Save Changes", "Add Picture", "Expiring Soon", "Create Account", "Sign In", "Log In", "Sign Up" (title case) sit beside "Log this meal", "Make it more balanced?" and "Add a task" (sentence case). *How:* sentence case everywhere.
* **2/5: `AuthPage` uses "Sign In" (headline), "Log In" (button) and "Log in with Google" on one screen.** *How:* "Sign in" / "Create account" / "Continue with Google" consistently.
* **3/5: Voice is warm but uneven.** "Let's get cooking" and "Finding a meal for you…" are friendly, while "Nutrition values are not stored for these fridge items yet." and "A grocery list has not been configured for this app yet." (`_handleBulkAction`) read like developer notes. *How:* hide unbuilt bulk actions instead of explaining them.
* **2/5: `FridgeCameraSheet` error copy** mentions "Spotify, OBS…" and is 40 words. *How:* "Can't open the camera. Close other apps using it, or upload a photo instead." (15 words).

## Best Practice (17): Health and diabetes language

### Description (17)
The ADA/ADCES consensus asks for language that is neutral, nonjudgmental, based on facts or physiology, strengths-based and person-first ("person with diabetes"), avoiding moral words like good/bad, control or compliance. The CDC Clear Communication Index asks for one main message, plain everyday words and explicit next steps. *Sources: Dickinson et al., Diabetes Care 2017 (ADA/ADCES consensus); CDC Language guidance tip sheet; NHS England Language matters; CDC Clear Communication Index.*

### Application to App (17)
* **2/5: `_EveningFitChip` "Good evening fit · 4/5" / "Heavier this close to bed · 2/5" (D/S).** *Why:* a numeric score out of 5 on a dinner is a grade, and "good" is exactly the judgment word the consensus flags. *How:* drop the number from the label ("Lighter option for evening" / "Heavier option for evening"), keep the score for sorting only, and let tapping explain why.
* **4/5: `_GlucoseNoteChip` "heads-up", "historical", repeated "not medical advice" (D/S).** *Why:* neutral and factual, which is well done. *How:* keep. Use one disclaimer string constant so wording can't drift.
* **3/5: Dieting build wording** ("Balance my meal", "Make it more balanced?"). *Why:* "more balanced" implies the current meal is unbalanced (a mild judgment). *How:* "Add a balancing tweak" states the action, not a verdict.
* **3/5: Hard-coded "mg/dL" in `meal_lab_page.dart` (lines 424, 427, 509) and `movement_lab_page.dart` (223, 227) (D/S).** *Why:* users who chose mmol/L in Glucose settings still see mg/dL here, which is inconsistent and confusing health data. *How:* route through `glucoseForDisplay` with `settings.displayUnit`.

## Best Practice (18): AI transparency and user control

### Description (18)
Tell users what the AI can and can't do so they calibrate trust, explain why an output was given, make outputs easy to correct or regenerate, and plan the failure path before the happy path (Google PAIR). NN/g found the ✨ sparkle icon is not understood as "AI" on its own, so pair it with a task label. Generated imagery should be disclosed, because users scrutinize product-like photos as real content. *Sources: Google PAIR Guidebook patterns; PAIR Errors + graceful failure; PAIR Crafting helpful explanations; NN/g The ✨ sparkles icon problem; NN/g Photos as web content.*

### Application to App (18)
* **2/5: `MealRecommendationCard` banner is a generated dish photo with no disclosure.** *Why:* users read a food photo as "this is what it will look like", and a generated image may show ingredients the recipe doesn't use. *How:* add a small "AI-generated image" label overlaid bottom-left on the image (`labelSmall` on a scrim), and a `semanticLabel` for the dish name.
* **3/5: "Recommend a Meal" with `auto_awesome` sparkle.** *Why:* the label carries it, so the sparkle alone is fine here. The tab itself is "Agent" with a robot icon. *How:* rename the tab "Meals" (labelled, BP 8) and keep the sparkle on the action button only.
* **4/5: Explanations and correction exist.** The reason paragraph, "From your fridge:", the Ask-about-this-meal sheet and "What should be different?" all do this well. *How:* make the ask affordance visible (BP 19).

## Best Practice (19): Scannable content and discoverable interactions

### Description (19)
People scan rather than read (79% in NN/g's study), so chunk content under descriptive headings, front-load key words, and put decision metadata (time, cost, difficulty) where the eye lands first. Gestures and hidden tap targets have no natural signifiers, so a feature users can't see effectively doesn't exist. Cards should group one object's content and actions. *Sources: NN/g How users read on the web; NN/g Text scanning patterns; NN/g F-shaped pattern; NN/g 3D Touch (gesture signifiers); NN/g Contextual swipe; NN/g Cards component.*

### Application to App (19)
* **2/5: `MealRecommendationCard` has no metadata row.** *Why:* cost is buried in a pill after the reason paragraph, and time and difficulty (which the user set in Preferences) aren't echoed at all, so every card must be read to compare. *How:* directly under the dish name, a `Wrap` of 3 compact facts (time icon "≈20 min", cost "$2–3", "Beginner") before the reason.
* **2/5: `_askable` lines are deliberately invisible** (code comment: "Intentionally adds no icon or tint"). *Why:* tap-to-ask on every ingredient is a signature feature with zero signifier, rescued only by the one-time tip. *How:* add a trailing `chat_bubble_outline` 16px icon at `onSurfaceVariant` on the section headers ("Ingredients · tap any line to ask").
* **3/5: Ingredients rendered as `Text('- $ingredient')`.** *Why:* hyphen bullets are typewriter-style and don't align on wrap. *How:* a `Row` with a 6px dot and `Expanded` text; steps with a circled number.

## Best Practice (20): Consistency and design tokens

### Description (20)
Same function, same look, same word (NN/g heuristic #4). Follow platform conventions unless there's evidence to deviate. M3 recommends using few elevation levels and not changing component defaults piecemeal. The practical tool is design tokens: radius, spacing, motion and color defined once and referenced everywhere. All sheets of the same kind should share the same affordances (e.g., a 32×4dp drag handle with a 48dp touch area). *Sources: NN/g Ten usability heuristics; NN/g Consistency and standards; M3 Elevation; Flutter `BottomSheet.showDragHandle` API; Android M3 BottomSheet docs.*

### Application to App (20)
* **2/5: Ten different corner radii** (3, 8, 10, 12, 14, 16, 18, 20, 24, 999). *Why:* cards 18, fridge tiles 16, banner 20, buttons/inputs 14, chips 12, pills 10, images 8, so nothing quite matches. *How:* an `AppRadius` token set of `sm 8 / md 12 / lg 16 / xl 24 / full`, mapped to M3's shape scale.
* **2/5: Only 4 of 11 `showModalBottomSheet` calls set `showDragHandle: true`.** *How:* set `showDragHandle: true` in `BottomSheetThemeData` once and remove per-call flags.
* **3/5: Dates hand-formatted.** `_HomeContentState._formattedDate` has its own weekday/month arrays and `AddFoodSheet` uses ISO. *How:* `MaterialLocalizations.formatFullDate` / `formatMediumDate` everywhere.
* **3/5: `FoodItemTile` in `lib/main.dart` is dead code** (unused since the grid replaced it). *How:* delete it so nobody restyles the wrong widget.

## Applications to App
1. Fix the color foundation in `AppTheme.light()`: `primary` #267A5B, a full secondary family (or none), enabled input border = `outline`, scaffold = `surfaceContainerLow`, and a `ThemeExtension` for freshness/chart colors (BP 1, 2).
2. Replace `CirclePageButton` with a labeled M3 `NavigationBar` (Fridge / Home / Meals) and replace the header's tune + logout icons with one account button and sheet whose Log out runs the unsaved-fridge guard (BP 8, 13).
3. Delete all 28 `border: OutlineInputBorder()` overrides so every field uses the theme (BP 14).
4. Replace every raw-exception and developer-facing error string with plain messages plus Retry (BP 12).
5. Stop the Fridge stream re-subscribing on every build, remove the Agent's artificial 1s delay, and give the fridge scan a real progress state with Cancel (BP 10).
6. Design the Fridge empty state (scan / add) and fix `AuthPage` (wordmark, purpose line, forgot password, show password, consistent "Sign in") (BP 11, 14, 16).
7. Rework the Fridge action layout: one extended "Scan fridge" FAB, Save/Discard moved to a bottom bar, "Add to meal" as primary in the selection toolbar, and per-tile 28px delete X removed (BP 7, 9).
8. Restructure `MealRecommendationCard`: metadata row, visible ask signifier, proper bullets, one filled action per card, and an "AI-generated image" label (BP 7, 18, 19).
9. Complete the type system: bundle Atkinson Hyperlegible Next, style all roles, and remove the six literal font sizes, including the 10px freshness pill (BP 4).
10. Make Home informative and safe: banner with live fridge counts at full contrast, tap-to-edit tasks, undo on delete, skeleton loading, retry on error (BP 2, 7, 9, 10, 13).
11. Large-text pass: adaptive fridge grid, header height from `textScaler`, and a 200% overflow test for the four in-scope screens (BP 5).
12. Rework `MealLogPage` into titled sections with chips/segmented buttons instead of dropdowns, and resolve the carb grams vs band duplication (BP 14).
13. Tokenize and normalize: `AppRadius`, spacing literals → `Spacing`, drag handle in the theme, localized dates, `centerTitle` default, delete `FoodItemTile` (BP 6, 20).
14. Copy pass: sentence case everywhere, hide unbuilt bulk actions, shorten the camera error, "Add a balancing tweak", and Agent example chips (BP 11, 16, 17).
15. Motion tokens: an `AppMotion` class, a short fade under reduce-motion, and a consistent page transition (BP 15).
16. (D/S, not in plan) Diabetes/sleep fixes: AGP-colored glucose band and themed markers, warm glucose-note chip, number-free evening-fit label, display-unit-aware Meal Lab/Movement Lab text, and undo on Meal Lab delete (BP 1, 3, 17, 13).

### Other notes
* **Where `CURRENT_UI.md` and the code disagree (code wins):**
  * "Inputs: filled white, 14px corners": true only where fields don't pass `border: OutlineInputBorder()`, which is 28 fields, including every in-scope form.
  * "Warm apricot secondary": the seeded `secondaryContainer` is mint `#CFE9D9` and tertiary is slate-blue `#3E6373`, so apricot appears almost nowhere.
  * "Selected nav circles scale up slightly": it's a double scale with overshoot.
  * "Loading is a centered spinner": the Agent also pads every request with an artificial 1s minimum.
  * `freshness.dart` claims AAA: Expired (5.83:1) and Expiring Soon (5.00:1) are AA only.
* **Why #267A5B and not `_brandDark` #1F6B4E for primary:** #1F6B4E (6.42:1) also passes but reads nearly forest-green on large surfaces. #267A5B keeps the current hue at 5.23:1 on white and 4.85:1 on the sage background, which is closer to "refresh, not rebrand".
* **Font choice:** Atkinson Hyperlegible Next is chosen for legibility (numbers, 1/l/I) for an audience where retinopathy is common. If it feels too utilitarian, the fallback is keeping Roboto/SF and doing only item 9's scale work, which gets ~70% of the benefit. Bundle the files (`assets/fonts/`) rather than fetching at runtime, so it works offline and on web without a Google request.
* **Orphaned screens:** `TodayDashboard`, Sleep, Exercise and Meal Balance are unreachable. Surfacing them is an IA decision, not a refresh, so nothing here depends on it. If you later add them, the new `NavigationBar` fits up to 5 destinations.
* **Not UI, but you need to know:** `pubspec.yaml` bundles `.env` as an asset and `AppEnvironment` reads `GEMINI_API_KEY` from it at runtime, so the key ships inside every APK/IPA/web build and can be extracted. Move Gemini calls behind a backend (e.g., Firebase Functions / Firebase AI Logic) before any public release.
* **Testing aids:** Flutter's `meetsGuideline(textContrastGuideline)`, `androidTapTargetGuideline` and `labeledTapTargetGuideline` can lock in BP 2 and 9 in widget tests. The plan should add them.

## Sources
* https://m3.material.io/styles/color/roles: color role pairing and accessibility guarantee
* https://m3.material.io/styles/color/advanced/apply-colors: mapping custom components to roles
* https://m3.material.io/blog/tone-based-surface-color-m3: surface container roles instead of elevation tint
* https://m3.material.io/styles/elevation/overview: few elevation levels, don't change defaults
* https://m3.material.io/foundations/designing/color-contrast: M3 contrast guidance for low vision
* https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html: 4.5:1 / 3:1 and large-text definition
* https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast: 3:1 for input boundaries, how to test
* https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum: 24px AA target floor
* https://www.w3.org/TR/WCAG22/: 1.4.1 use of color, 1.4.4 resize text
* https://developer.apple.com/design/human-interface-guidelines/accessibility: 44pt targets, 11pt floor, contrast, Dynamic Type, reduce motion
* https://developer.apple.com/design/human-interface-guidelines/motion: brief, non-blocking motion
* https://developer.apple.com/design/human-interface-guidelines/writing: consistent labels
* https://www.cdc.gov/vision-health-data/prevalence-estimates/dr-prevalence.html: DR prevalence by age
* https://www.cdc.gov/diabetes/diabetes-complications/diabetes-and-vision-loss.html: DR leading cause of blindness
* https://pubmed.ncbi.nlm.nih.gov/3495070/: blue–yellow deficits in diabetes
* https://pmc.ncbi.nlm.nih.gov/articles/PMC7914308/: review, color deficits predominantly tritan and worsen with DR
* https://www.nei.nih.gov/eye-health-information/eye-conditions-and-diseases/color-blindness/types-color-vision-deficiency: tritan definition
* https://www.niddk.nih.gov/health-information/professionals/diabetes-discoveries-practice/clinical-targets-for-continuous-glucose-monitoring-data: AGP / time-in-range consensus
* https://m3.material.io/styles/typography/overview: five type roles
* https://m3.material.io/styles/typography/type-scale-tokens: baseline/emphasized scale
* https://github.com/flutter/flutter/blob/main/packages/flutter/lib/src/material/text_theme.dart: exact M3 sizes/line heights in Flutter
* https://www.brailleinstitute.org/freefont/: Atkinson Hyperlegible purpose and Next family
* https://fonts.google.com/specimen/Atkinson+Hyperlegible+Next: weights 200–800 availability
* https://github.com/flutter/packages/blob/main/packages/google_fonts/README.md: bundling fonts, disabling runtime fetch
* https://docs.flutter.dev/ui/accessibility/ui-design-and-styling: large-font testing
* https://docs.flutter.dev/ui/adaptive-responsive/safearea-mediaquery: `TextScaler` over `textScaleFactor`
* https://docs.flutter.dev/ui/accessibility/accessibility-testing: guideline API for contrast/targets/labels
* https://m3.material.io/styles/spacing/tokens: 8dp base spacing
* https://m3.material.io/foundations/layout/grids-spacing/grids: grid and margins
* https://m3.material.io/foundations/layout/breakpoints: compact <600dp
* https://www.nngroup.com/articles/principles-visual-design/: proximity, hierarchy
* https://www.nngroup.com/articles/visual-hierarchy-ux-definition/: hierarchy via color, scale, grouping
* https://www.nngroup.com/videos/squint-test/: squint test
* https://m3.material.io/components/all-buttons: one prominent action per screen
* https://m3.material.io/components/buttons/overview: filled/tonal/outlined/text emphasis
* https://m3.material.io/components/extended-fab/guidelines: one FAB per screen
* https://developer.android.com/develop/ui/compose/components/navigation-bar: 3–5 destinations, labels for 3
* https://developer.android.com/reference/kotlin/androidx/compose/material3/NavigationBarItem.composable: label behavior
* https://www.nngroup.com/articles/icon-usability/: icons need text labels
* https://www.nngroup.com/articles/top-10-application-design-mistakes/: unlabeled icons
* https://www.uxmatters.com/mt/archives/2013/02/how-do-users-really-hold-mobile-devices.php: 49% one-thumb use
* https://interactions.acm.org/archive/view/may-june-2015/fingers-thumbs-and-people: center taps most accurate
* https://www.nngroup.com/articles/response-times-3-important-limits/: 0.1 / 1 / 10 s
* https://www.nngroup.com/articles/skeleton-screens/: skeleton vs spinner vs progress bar
* https://www.nngroup.com/articles/designing-for-waits-and-interruptions/: long waits need progress and cancel
* https://www.nngroup.com/articles/empty-state-interface-design/: empty-state guidelines
* https://www.nngroup.com/articles/mobile-app-onboarding/: onboarding components
* https://www.nngroup.com/articles/mobile-tutorials/: tutorial skippers perform as well
* https://www.nngroup.com/videos/onboarding-skip-it-when-possible/: skip onboarding
* https://www.nngroup.com/articles/error-message-guidelines/: error-message guidelines
* https://www.nngroup.com/articles/hostile-error-messages/: hostile error patterns
* https://www.nngroup.com/articles/errors-forms-design-guidelines/: inline form errors
* https://m3.material.io/components/snackbar/guidelines: single action, Undo, not the only path
* https://pair.withgoogle.com/chapter/People%20+%20AI%20Guidebook%20-%20Errors%20+%20Graceful%20Failure.pdf: AI error handling
* https://www.nngroup.com/articles/confirmation-dialog/: confirmations sparingly, specific labels
* https://www.nngroup.com/articles/ui-accelerators/: undo over confirm
* https://www.nngroup.com/articles/form-design-placeholders/: placeholders harmful
* https://www.nngroup.com/articles/web-form-design/: form top-10, avoid dropdowns for few options
* https://www.nngroup.com/articles/drop-down-menus/: dropdown guidelines
* https://www.nngroup.com/articles/dropdown-list/: radio below ~5 options
* https://www.nngroup.com/articles/checklist-registration-login/: show-password option
* https://www.nngroup.com/articles/form-design-white-space/: grouping form sections
* https://m3.material.io/styles/motion/easing-and-duration/applying-easing-and-duration: easing/duration pairs
* https://m3.material.io/styles/motion/easing-and-duration/tokens-specs: easing tokens
* https://m3.material.io/styles/motion/overview/how-it-works: springs replacing easing
* https://www.nngroup.com/articles/tone-of-voice-dimensions/: four tone dimensions
* https://www.nngroup.com/articles/tone-voice-users/: tone affects brand perception
* https://designsystem.digital.gov/components/button/: verb-first, sentence-case labels
* https://diabetesjournals.org/care/article/40/12/1790/36977/The-Use-of-Language-in-Diabetes-Care-and-Education: ADA/ADCES language consensus
* https://www.cdc.gov/diabetes-toolkit/media/pdfs/speaking-the-language-guidance.pdf: CDC language tip sheet
* https://www.england.nhs.uk/long-read/language-matters-language-and-diabetes/: nonjudgmental diabetes language
* https://www.cdc.gov/ccindex/index.html: Clear Communication Index
* https://pair.withgoogle.com/guidebook-v2/patterns: set expectations for AI
* https://pair.withgoogle.com/guidebook/chapters/trust-and-explanations/crafting-helpful-explanations: AI explanations
* https://www.nngroup.com/articles/ai-sparkles-icon-problem/: sparkle icon not understood alone
* https://www.nngroup.com/articles/photos-as-web-content/: users scrutinize content photos
* https://www.nngroup.com/articles/how-users-read-on-the-web/: 79% scan
* https://www.nngroup.com/articles/text-scanning-patterns-eyetracking/: layer-cake scanning, chunking
* https://www.nngroup.com/articles/f-shaped-pattern-reading-web-content/: F-pattern
* https://www.nngroup.com/articles/3d-touch/: gestures lack signifiers
* https://www.nngroup.com/articles/contextual-swipe/: hidden gesture problems
* https://www.nngroup.com/articles/cards-component/: card definition
* https://www.nngroup.com/articles/ten-usability-heuristics/: heuristics #4, #5, #9
* https://www.nngroup.com/articles/consistency-and-standards/: consistency heuristic
* https://api.flutter.dev/flutter/material/BottomSheet/showDragHandle.html: drag handle spec
* https://github.com/material-components/material-components-android/blob/master/docs/components/BottomSheet.md: 48dp handle target
