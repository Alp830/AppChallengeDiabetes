# Technical Overview — AI Fridge-to-Meal Companion (with optional Diabetes Mode)

> A cross-platform Flutter app that turns a photo of your fridge into budget-aware,
> nutrition-aware meal ideas. In its diabetes build, it can also read real
> continuous glucose monitor (CGM) data and use what happened on past nights to
> shape tonight's dinner suggestions.

---

## 1. At a glance

| | |
|---|---|
| **Framework** | Flutter / Dart 3.12 — one codebase for Android, iOS, Web, Windows, macOS, Linux |
| **Backend** | Firebase Authentication, Cloud Firestore, Firebase Storage |
| **AI** | Google Gemini API: `gemini-4-argon` (vision) and `gemini-3-flash-preview` (text), plus generated dish photos |
| **Size** | ~20,800 lines of app code in `lib/`, ~10,500 lines of tests |
| **Tests** | 400+ automated unit and widget tests (`flutter test`) |
| **History** | 62 commits since June 2026, built feature by feature from written plans (`docs/plans/`, `OutlienFridgeV2.md`) |
| **Accessibility** | Atkinson Hyperlegible font, tests that check WCAG contrast, layouts tested at 200% text size, reduced-motion support |

---

## 2. The problem

Healthy eating fails in three places:

1. **People don't know what they can make** with what's already in the fridge, so food goes to waste.
2. **Generic recipe apps ignore real limits:** a budget, little time, cooking skill, and nutrition goals.
3. **For people with diabetes**, dinner matters a lot. Overnight glucose depends on what and when you eat, and most apps never connect the meal to the night that follows.

This app ties those three together: **Fridge → Meals → (optionally) Glucose and Sleep insight → better future meals.**

---

## 3. Architecture

```
┌──────────────────────────── Flutter UI (lib/) ─────────────────────────────┐
│  Fridge tab        Home tab               Meals tab           Diabetes Mode │
│  (scan, grouped    (today checklist,      (AI agent, recipe   (CGM, sleep,  │
│   grid, drafts)     first-meal guide)      cards, Q&A, saved)  exercise)    │
└───────┬───────────────────┬──────────────────────┬───────────────┬─────────┘
        │                   │                      │               │
        ▼                   ▼                      ▼               ▼
  ┌────────────┐     ┌──────────────┐      ┌──────────────┐  ┌─────────────────┐
  │ AI layer   │     │ Repositories │      │ Pure-Dart    │  │ Importers       │
  │ lib/ai/    │     │ (Firestore)  │      │ analysis     │  │ LibreView CSV,  │
  │ retry,     │     │ per-user     │      │ services     │  │ demo CGM data   │
  │ cancel,    │     │ collections  │      │ (no network, │  └─────────────────┘
  │ errors     │     └──────┬───────┘      │  fully tested)│
  └─────┬──────┘            │              └──────────────┘
        ▼                   ▼
  Google Gemini API   Firebase Auth + Firestore + Storage
                      (security rules: each user can only reach their own data)
```

**Design rules that run through the whole codebase**

- **Feature folders:** `fridge/`, `meals/`, `cgm/`, `sleep/`, `exercise/`, `onboarding/`, `design/`, `ai/`. Each one splits into `models/`, `data/` (repositories), `services/` (logic) and `screens/` (UI).
- **Logic stays separate from UI.** The health math (glucose analysis, meal scoring, safety checks) is plain Dart with no Flutter or network code, so it can be unit-tested directly.
- **Dependency injection for testing.** HTTP clients, clocks (`now`), storage and sleep functions can be swapped in, so tests run the real code against fake servers (`MockClient`) without spending API quota.
- **Feature flag at build time.** Diabetes features are compiled in only with `--dart-define=DIABETES_ENABLED=true` (`lib/app_features.dart`). One codebase ships as either a general dieting and budgeting app or a diabetes-focused app. A navigation guard (`lib/navigation/app_feature_navigation.dart`) stops diabetes-only screens from opening in the general build, even through an old callback.

---

## 4. Feature deep-dives

### 4.1 Fridge Vision Scan — photo → structured inventory

`FridgeScanPipeline.scan` (`lib/fridge/scan/`), measured with a live eval harness (`tool/scan_eval/`)

- The user takes up to 3 photos of a fridge, a pantry or a grocery bag. They are read by **Gemini 4 Argon**, Google's flagship model, at its lowest thinking level. It replaced Gemini 3.1 Pro: on Roboflow's real-world text-reading benchmark, Argon low scored 85.7% in 7.7 s against Pro's 73.1% in 18.6 s, at about a fifth of the cost. Lighter "flash" models were ruled out earlier because they mistook uncommon foods (dried linden flowers) for bread.
- **Measured, not guessed.** An eval harness scores the real scan against a hand-written answer key for two hard photos: a motion-blurred, tilted, back-lit webcam frame and a sharp 24 MP phone photo with 40+ small items. It reports recall per tier, "sure" precision, medicine leaks, latency and cost from real token counts. Every number is the median of 3 runs, and a spend ledger caps the eval budget.

  | | Blurry photo | Clear 24 MP photo |
  | --- | --- | --- |
  | Before: recall (readable + recognizable) | 28% | 41% |
  | After: recall | **83%** | **93%** |
  | After: "sure" items correct | 100% | 82% |
  | After: medicine or supplements added as food | 0 | 0 |
  | After: first item on screen / whole scan | ~12 s / ~25 s | ~9 s / ~30 s |
  | After: cost per scan | $0.03 | $0.09 |

- **List everything, mark what's unsure.** The old prompt told the model to leave out anything uncertain, so blurry items silently vanished. The new prompt works zone by zone with a count first and never omits an item. Each item carries a confidence (sure / likely / guess), up to two alternatives, a bounding box and an `isFood` flag. Non-food (medicine, supplements, skincare) is dropped in code. Unsure items reach the fridge with an amber **Maybe** badge, alternative chips and "Looks right", and the tile ✕ deletes in one press. The meal agent sees them as unconfirmed.
- **Research idea 1 — native-pixel tiles for large photos.** Gemini gives every image about the same token budget, so a 24 MP photo shrunk to fit leaves a door label a fraction of a token. Following Shi et al. (arXiv 2610.09313: splitting is safe if no view zooms out and views overlap by about one object), photos of 3072 px and more are cut into 2×2 overlapping tiles from the kept original and read in parallel. Tile boxes are mapped back to the full photo and merged, including the same object named differently by two tiles. On the clear photo this raised recall from 86% (one call) to 93%.
- **Research idea 2 — capture a better frame instead of repairing a bad one.** Blur cut the odds of a correct product ID by 88% in a CHI '26 study, and deblurring or upscaling before the model doesn't recover the loss ("Visual Quality Paradox"). So the shutter takes a short burst and keeps the sharpest frame (Laplacian variance, as in Apple's sample code), and a quality check warns "Looks blurry, hold steady and retake" or "Bright light behind". On the owner's webcam clip every frame had the same hand-shake: the best frame did not beat the still (78% vs 83%), so the warning is the part that matters there.
- **Streaming and the original pixels.** Calls use `streamGenerateContent`; the dialog shows "Found 34 items so far… Reading part 2 of 4" as items arrive. Photos are no longer shrunk at pick time; the engine's image codec decodes them once, and the original is kept (capped at 4096 px) for tiles while only a ≤2048 px overview or tile is ever uploaded.
- **What didn't make it:** more image tokens (ULTRA_HIGH: worse), more thinking (no gain), a zoom pass on unsure regions (no gain, +26 s), Gemini's own agentic zoom (≈376k tokens per image in the literature, over budget). No configuration reaches 15 s for a full list: output speed (~100 tokens/s) bounds it, which is why the scan streams.
- **Structured output and safety nets kept:** a JSON response schema, the app's 7 food categories, placeholder names filtered in code, and the model's "days until it spoils" turned into an expiry date that `fridge/freshness.dart` labels Fresh, Expiring Soon or Expired.

### 4.2 Fridge as an editable draft with atomic saves

`FridgePage`, `FridgeChangeSet` (`lib/main.dart`), `fridge/selectable_fridge_grid.dart`

- Edits (add, edit, delete) go into a **local copy** first, the same way git stages changes before a commit. Nothing touches the database until the user presses **Save**.
- On Save, all changes are sent together as **one Firestore `WriteBatch`** (`_commitFridgeChanges`). Either every change is saved or none is, so the fridge is never left half-updated.
- An **unsaved-changes bar** counts pending edits. If the user tries to leave, a guard asks them to Save, Discard or Cancel.
- Items are **grouped by food type**, sorted by expiry inside each group, with long-press **drag-to-select** on mobile and Ctrl/Shift-click on desktop for bulk actions.
- Deletes can be undone. In the UI code's own words: "undo beats 'Are you sure?'" (Nielsen Norman Group guidance).

### 4.3 The Meal Agent — the AI prompt is built from the user's whole situation

`GeminiMealService.generate` and `_buildPrompt` (`lib/main.dart`)

The app doesn't send a fixed prompt. It builds a **structured request** (`AgentRequest`) from:

- fridge items, each with **days until expiry** ("expires in 1 day — use soon"), so ingredients about to go bad get used first and less food is wasted
- meal type, cooking experience, available time, and budget per serving
- **nutrition priorities** (high protein, carbs or fiber) saved to the user's profile
- optional **meal-balance targets** (~20–30 g protein, ~7–8 g fiber, half the plate as produce)
- **feedback from earlier suggestions**, so the agent learns within a session
- in Diabetes Mode: **evening-meal guidance** and a summary of the user's **own recent overnight glucose pattern** (see 4.6)

It also writes an explicit **priority order** into the prompt for when goals conflict:
1. the dish the user asked for, allergies, food safety, time
2. the budget
3. the selected nutrition priorities
4. soft guidance (meal balance, evening suggestions)

**When the budget and nutrition goals can't both be met**, the agent doesn't fail silently. A deterministic rule (`fallbackSplit` in `meals/services/meal_priority_policy.dart`) decides how many meals are "budget-first" and how many are "nutrition-first" (for example, 3 meals → 2 budget-first and 1 nutrition-first). Each fallback meal carries a friendly first-person note explaining the trade-off.

**The app checks the model's answer before showing it.** `validateMealResponse` confirms the JSON has the right number of meals, valid priority modes, and costs under budget where required. If the model breaks the contract, it raises a `FormatException`, which the retry layer (4.5) treats as worth asking again. **A bad AI answer never reaches the screen.**

Each recipe card shows the ingredients, steps, which fridge items it uses, the estimated cost per serving, an AI-generated photo of the dish, and three suggested follow-up questions.

### 4.4 "Ask about this meal" — Q&A tied to one recipe

`meals/services/meal_qa_service.dart`

- The full recipe goes into every request, and the behavior rules go in Gemini's **`systemInstruction`** rather than the user message. The code comments explain why: when the rules were in the user message, the model sometimes repeated them back as answers.
- **Handles a thinking model correctly:** Gemini returns its internal reasoning as parts marked `thought: true`. The service drops those so the user only sees the final answer, never the model's reasoning.
- **Medical safety:** the model is told it does *not* know the user's glucose, medications or history, and must decline insulin or medication dosing questions and point to the user's care team.
- Answers are concrete: "How do I know it's done?" gets what to *see, hear or smell* plus a time, not "until done."

### 4.5 One shared retry engine for every AI call

`lib/ai/ai_retry.dart`

Network calls fail. Instead of each screen handling that on its own, all three AI features (scan, recommendations, Q&A) go through **`runWithAiRetry<T>`**:

- **Up to 5 attempts, 2 s apart, with a timeout per feature** (scan 60 s, recommendations 45 s, Q&A 30 s).
- **Smart about what to retry:** HTTP 408, 429 and 5xx, timeouts, network drops and malformed model output are retried. A **400, 401 or 403, a missing API key, or a safety block is not retried**, because sending the same request again would fail the same way. Neither is a 429 that means the quota is used up (`limit: 0` or a daily quota), or a response cut off at `MAX_TOKENS`.
- **Timed-out scans are really stopped:** Dart's `Future.timeout` only stops *waiting*; the HTTP call keeps running. The scan passes an abort signal into an `http.AbortableRequest`, so a hung attempt is cancelled before the next one starts and can't be billed twice.
- **Cancellation:** when the user leaves the screen, an `AiCancellation` token stops the loop, so an old result never appears on the wrong screen.
- The UI shows **"AI request failed. Retrying 2/5"** only after the first failure. Raw errors are written to the debug log and never shown to users (`design/friendly_errors.dart`).
- Works on the web too: `dart:io` isn't imported, so web builds compile, and socket errors are recognized from their text instead.

### 4.6 Diabetes Mode — real CGM data analysis

**Importing real device data:** `cgm/data/libreview_csv_importer.dart`

- Parses CSV exports from **Abbott FreeStyle Libre** (LibreView). It auto-detects the delimiter (comma or semicolon for European exports), finds the header row, handles mg/dL and mmol/L, separates historic, scan and fingerprick-strip readings, removes duplicates by device serial + timestamp, and counts rejected rows.

**Overnight analysis:** `sleep/services/overnight_analysis_service.dart`

Using the user's sleep log and glucose readings, it computes standard CGM metrics:

- **Time in range**, time below 70, time below 54 mg/dL, and time above range. Each gap between readings is credited to the earlier reading's range, capped at 30 minutes, so missing data isn't counted as healthy time.
- **Coefficient of variation (CV)** against the **36% consensus target** for glucose swings.
- **Low events:** separate dips below the low threshold lasting at least 15 minutes.
- **Bedtime trend:** rising, flat or falling, from readings between 60 minutes before and 30 minutes after bedtime.

It then sorts each night into a plain-language **pattern**, with **safety-first ordering** (lows are checked first):

| Pattern | Rule |
|---|---|
| Some overnight lows | >4% of the night below 70, or ≥2 sustained low events |
| Drifting down at bedtime | falling trend and lowest value within 20 mg/dL of the low line |
| A bumpier night | CV > 36% |
| Higher after a late dinner | dinner ≤3 h before bed **and** mean glucose in the first 3 hours of sleep above range |
| Steady night | none of the above |

**Bedtime safety advice:** `sleep/services/bedtime_advisor_service.dart`, a small rules engine that shows its reasoning.

- Flags overnight lows as **mild (54–70)** or **severe (<54)**.
- Suggests a bedtime snack **only** when glucose before bed is low-normal **and** falling. The code is deliberately narrow because routine late-night snacking makes overnight glucose worse. Every suggestion comes with a "talk to your care team" note. **The app never doses.**

**Closing the loop: tonight's dinner learns from past nights**
`sleep/services/evening_food_context_service.dart`

- It summarizes the user's recent nights into one **pattern summary** (when tied, a real pattern wins over "steady," so calm nights don't hide a problem). That summary goes into the Meal Agent's prompt for dinners and snacks.
- So if late dinners keep leading to high glucose overnight, tonight's dinner suggestions lean lighter and earlier-friendly, and add an optional "glucose note" such as pairing a carb with something already in the fridge. If lows keep happening, the agent knows not to push very low-carb dinners.

**Meal glucose fingerprint:** `meals/services/meal_analysis_service.dart` measures each logged meal's glucose response: baseline (median of the 15 minutes before eating), peak, rise, time to peak, time to recover (back within 10% of baseline), and delayed rises.

**Exercise:** `exercise/services/exercise_safety_service.dart` runs a pre-workout checklist (stop for chest pain or dizziness, bring fast-acting carbs if the user takes medication that can cause lows, check feet). `movement_analysis_service.dart` measures glucose before, at the end of, 2 h after, and overnight after a workout, and labels the evidence "Preliminary → Developing → Repeated" by how many sessions back it up.

**AI meal grouping:** `meals/services/meal_grouping_service.dart` uses Gemini to recognize repeat meals ("this is your usual oatmeal") and learns from the user's own corrections. Results are cached by a hash of the meal and photo, so the same question isn't sent twice.

### 4.7 Saved recipes and first-time onboarding

- **Saved recipes** are stored as full JSON in Firestore (`MealRecommendation.toJson` / `fromJson`), so a recipe reopens instantly **without another AI call**, which saves cost and time.
- **First-meal guide:** new accounts get a "Let's get started" card. A pulsing highlight points to the controls in the order they're used and holds still when the device asks for reduced motion. Existing users never see it: only accounts created after the guide shipped are marked `pending`.

---

## 5. Security and privacy

- **Firebase Auth** with email + password (email verification required) and Google sign-in.
- **Firestore security rules** (`firestore.rules`): every collection (fridge items, glucose days, meal events, sleep logs, saved recipes, and others, 15 in all) lives under `users/{userId}`. Only the signed-in owner can read or write it. Meal photos in **Storage** follow the same rule (`storage.rules`).
- The meal-grouping prompt sends only what it needs (`safeMeal`: name, components, portion, preparation). No glucose data or personal identifiers go to the model.
- Language is **observational, never diagnostic**: "Consider sharing these with your care team," never "you have X."

---

## 6. Accessibility and design quality

- **Atkinson Hyperlegible** font, from the Braille Institute, designed for readers with low vision.
- **Automated WCAG checks:** `test/accessibility_guidelines_test.dart` runs Flutter's `textContrastGuideline`, `androidTapTargetGuideline`, `iOSTapTargetGuideline` and `labeledTapTargetGuideline` on the main screens. `test/support/contrast.dart` computes the WCAG contrast ratio from relative luminance.
- **Large text:** `test/large_text_test.dart` renders the main screens at large text sizes and checks nothing overflows. Above 130% text size, layouts switch to roomier versions (WCAG 1.4.4, `design/text_scale.dart`).
- **Reduced motion** support, skeleton loading screens, and screen-reader labels and tooltips (for example, "Delete item" can't be mistaken for "close").
- **Design tokens:** spacing, corner radius, motion, and status colors live in `lib/design/`. A test (`input_style_guard_test.dart`) fails the build if any text field overrides the shared input style.

---

## 7. Engineering process

- **Planned before coding:** features start as written plans (`OutlienFridgeV2.md`, `docs/plans/2026-09-28-fridge-v2.md`) listing problems, options, the chosen option and acceptance criteria.
- **Feature branches merged into main** (`fv2/fridge`, `fv2/api`, `fv2/onboarding`) with focused commits (`feat(ai): ...`, `fix(meals): ...`, `test(v2): ...`).
- **Tests for every layer:**
  - *Pure logic:* CSV parsing, overnight patterns, meal-balance scoring, retry rules, budget fallback split, freshness.
  - *AI calls:* run against `MockClient` fake servers, covering success, 5xx then success, safety blocks, and malformed JSON.
  - *Widgets and whole flows:* fridge save workflow, leave guard, retry status UI, first-meal guide, combined Fridge-to-Meals flows.
  - *Accessibility:* contrast, tap targets, large text.

---

## 8. Suggested talking points for the video (≈60–90 s of technical content)

1. **"One photo becomes structured data."** Show the scan. Mention Gemini 4 Argon, picked on benchmark data because it's more accurate, faster and cheaper than the model it replaced, with a strict JSON schema, high-resolution image reading, and code that rejects uncertain guesses.
2. **"The AI is checked, not trusted blindly."** Every recipe response is validated against rules (meal count, budget, nutrition goals). A bad answer is retried automatically and never shown.
3. **"It handles failure gracefully."** One retry engine, 5 attempts, which only retries errors that can recover, can be cancelled, and shows "Retrying 2/5" on screen.
4. **"It learns from your own nights."** Real FreeStyle Libre data → time-in-range, CV, low events → a nightly pattern → tonight's dinner suggestions adapt.
5. **"Safety is designed in."** Lows are checked first, the AI won't answer dosing questions, and bedtime snack suggestions are narrow and clinically cautious.
6. **"Built for everyone."** Low-vision font, WCAG checks in the test suite, 200% text support, reduced motion.
7. **"Engineered like production software."** 400+ automated tests, atomic database writes, per-user security rules, one codebase for 6 platforms.

### Good code to show on screen

| What | Where |
|---|---|
| Retry engine (short and readable) | `lib/ai/ai_retry.dart` — `runWithAiRetry` |
| Vision scan pipeline (tiles, streaming, merge) | `lib/fridge/scan/fridge_scan_pipeline.dart`, `fridge_scan_service.dart`, `scan_merge.dart`; eval in `tool/scan_eval/` |
| Overnight pattern rules | `lib/sleep/services/overnight_analysis_service.dart` — `_classify` |
| Bedtime safety rules engine | `lib/sleep/services/bedtime_advisor_service.dart` — `evaluate` |
| Per-user security rules | `firestore.rules` |
| Tests running green | terminal: `flutter test` |
