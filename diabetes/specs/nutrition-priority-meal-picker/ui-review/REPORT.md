# Phase 4.2 — Playwright UI verification (nutrition priorities)

Date: 2026-10-24 · Reviewer route: isolated `playwright-cli` 0.1.22 session `nutrition-ui-review`, `--browser=chrome`, default in-memory profile. No `attach`, CDP, `--persistent`, `--profile`, imported storage, Claude in Chrome or regular-browser harness.

## Setup

- Fixture entry point (test-only, outside `lib/`): `test_driver/nutrition_ui_fixture.dart`. It renders the real `AgentPage` and `SavedRecipesPage` with in-memory preference/saved-recipe stores, `userId: fixture-user`, and a `MockClient` Gemini that builds deterministic responses from the outgoing prompt (count, budget, selected priorities). Firebase is never initialized; production auth is untouched; no live model calls; Q&A calls are stubbed; no images are fetched.
- Build: `flutter build web -t test_driver/nutrition_ui_fixture.dart --no-tree-shake-icons -o build/nutrition_fixture_web`
- Serve: `python -m http.server 8080 --bind 127.0.0.1` from the build directory (stopped afterwards).
- Open: `playwright-cli -s=nutrition-ui-review open http://127.0.0.1:8080 --browser=chrome`. Flutter semantics are enabled by the fixture (`SemanticsBinding.instance.ensureSemantics()`), so every control was targeted through the accessibility snapshot, not coordinates.
- Fixture scenarios: Feasible (all `allPreferences`, cost 0.8× budget), Conflict (approved split; budget-first 0.8× budget with relaxed-preference notice, nutrition-first 1.5× budget with overrun notice; the mock returns nutrition-first meals FIRST to prove the app reorders), Always invalid (count + 1).

## Results (budget $6.50 per serving unless noted)

| Check | Observed | Result |
|---|---|---|
| Three independent checkboxes | Protein and fiber toggled independently; later all three on; carbs toggled off/on | Pass |
| Budget label / validation | Label "Budget per serving"; `0` → inline "Enter a budget above 0, like 7.50, or turn budget off" and `[invalid]`; `6.50` accepted | Pass |
| Failed save | "Fail next nutrition save" → High carbs reverted to unchecked, inline "Couldn't save your nutrition priorities. Try again."; next toggle saved | Pass |
| Persistence across remount | "Remount picker" → all three boxes checked from store | Pass |
| Persistence across browser reload | Not testable: the fixture store is in memory, so reload resets it (no web storage dependency added). Firestore persistence is covered by unit/widget tests only | Limitation |
| Conflict, count 1 | `Fixture Dish 1 (budgetFirst) $5.20` + prominent "I couldn't meet all your preferences within your budget / Relaxed: High fiber", "Budget-first option", notice, "Costs are estimates." | Pass |
| Conflict, count 2 | budgetFirst $5.20 → nutritionFirst $9.75 (1/1) | Pass |
| Conflict, count 3 | 2 budgetFirst → 1 nutritionFirst | Pass |
| Conflict, count 4 | 2 budgetFirst → 2 nutritionFirst | Pass |
| Conflict, count 5 | 3 budgetFirst → 2 nutritionFirst; each nutrition-first card shows "Nutrition-first option", "Over your budget" (icon + text) and overrun notice | Pass |
| Budget-first ordering | Mock emitted nutrition-first first; UI always showed budget-first first, stable within group | Pass |
| Feasible, counts 1/3/5 | All `allPreferences` at $5.20, no mode label, notice or over-budget label | Pass |
| Exactly one model call per generation | Gemini call counter +1 per feasible/conflict generation | Pass |
| Invalid responses | Always invalid: 5 bounded attempts, then "Couldn't get a meal idea after a few tries. Check your connection and try again." + Try again; no meals shown | Pass (see note) |
| Diabetes disabled | All flows above ran with diabetes off | Pass |
| Diabetes enabled | Conflict count 1 shows identical heading/label/notice | Pass |
| Saved recipe with metadata | "Budget-first option", notice, unmet heading, "Costs are estimates. Budget fit is from when this was suggested ($3 per serving)." | Pass |
| Legacy saved recipe (no metadata) | Opens and renders without tradeoff UI | Pass |
| Mobile 390×844 | Sheet and card notices wrap, no clipping | Pass |
| 200% text (root font-size 32px) | Card heading/notice and sheet wrap and scroll; no clipping | Pass |
| Keyboard | Tab order through sheet; Space toggles boxes. **Found:** focus jumped back to "Balance my meal" after each nutrition toggle (boxes are disabled while saving). **Fixed** (focus restored to the toggled box after save) and re-verified: focus stays on "High carbs", next Tab → "High fiber" | Pass after fix |
| Console | 0 errors, 0 warnings (both runs) | Pass |

## Screenshots (second capture round after independent review)

An independent reviewer (run 26cb8328) found evidence gaps in the first round: the nutrition-first screenshot had been overwritten by a later, further-scrolled capture, and the focus screenshots were ambiguous. Those files were moved to `superseded/` and recaptured on a fresh session with unique filenames, each verified right after capture. Accessibility-tree excerpts backing the ordering and focus claims are in `evidence-snapshots.txt`.

| Requirement | Screenshot(s) |
|---|---|
| Sheet: section, 3 independent boxes, helper text, "Budget per serving" | `desktop-preferences-sheet.png`, `mobile-preferences-sheet.png`, `mobile-200pct-preferences-sheet-heading.png`, `mobile-200pct-preferences-sheet.png` |
| Budget validation (`0`) | `desktop-budget-validation-zero.png` |
| Single conflict: heading + relaxed list + label + notice + estimates | `desktop-conflict-1.png`, `desktop-diabetes-on-conflict-1.png`, `mobile-conflict-1.png`, `mobile-conflict-1-notice.png`, `mobile-200pct-conflict-1.png`, `mobile-200pct-conflict-1-label.png` (label at 200%), `mobile-200pct-conflict-1-notice.png` |
| Nutrition-first: "Nutrition-first option" + "Over your budget" (icon + text) + overrun notice | `desktop-conflict-5-nutrition-first-card.png`, `mobile-conflict-5-nutrition-first-card.png`, `mobile-200pct-conflict-5-nutrition-first-card.png` |
| Feasible: no tradeoff labels, only "Costs are estimates." | `desktop-feasible-1-top.png` (full card top; snapshot count of tradeoff nodes = 0), `desktop-feasible-3.png` (lower part of a 3-result run) |
| Failed save | `desktop-save-failure.png`, `mobile-200pct-save-failure.png` |
| Exhausted retries | `desktop-always-invalid-error.png` |
| Saved recipe with metadata / legacy | `desktop-saved-recipe-metadata.png`, `mobile-saved-recipe-metadata.png`, `mobile-200pct-saved-recipe-metadata.png` (detail view) / `desktop-saved-recipe-legacy.png`; saved list at 200%: `mobile-200pct-saved-recipes-list.png` |
| Keyboard focus after save (mouse parked at 5,890 so the highlight is focus, not hover) | `desktop-keyboard-focus-after-save.png` (focus on High carbs), `desktop-keyboard-focus-next-tab.png` (next Tab → High fiber) |

Snapshot-only (no screenshot can show these): per-count card order for 1–5 and Gemini call counts (sequences in `evidence-snapshots.txt`), remount persistence, console status.

Capture integrity: `playwright-cli screenshot` writes files with a variable delay (5–10 s observed), and one late write overwrote a file I had already checked (`superseded/mobile-200pct-saved-recipe-metadata.overwritten-by-list.png`). Third-round captures were written to a temp folder, inspected, then copied in after the browser closed. SHA-256 hashes of every screenshot are listed in `SHA256SUMS.txt`.

200% method: the root `<html>` font-size was set to 32px (browser default 16px). Flutter web derives its text scale factor from that value, and the screenshots show text doubled, while the fixture code applies no scaling of its own.

## Notes and limitations

- Mocked responses demonstrate the UI and validation contract, not nutritional or price accuracy.
- Reload persistence not exercised in the browser (see table).
- The exhausted-retry message mentions the connection even when the cause is an invalid model response (existing shared retry copy; not changed).
- Saved-recipe original budget renders as "$3" while notices use "$3.00" (cosmetic).
- Fixture control bar takes vertical space at 200% text; it is test-only.
- Saved-recipes **list** at 200% text: titles are limited to two lines without an ellipsis, so "Seeded Budget-First Lentil Bowl" shows as "Seeded Budget-First" (`mobile-200pct-saved-recipes-list.png`). Pre-existing list code (`saved_recipes_page.dart:172`, `maxLines: 2`), outside this plan; recommend adding `overflow: TextOverflow.ellipsis`.
- Small type: helper text, "Costs are estimates." and the inline save error use the theme's small body style (~11px at 100%); they scale correctly at 200%. Worth a later design pass; not changed here.
- Snapshot logs from the CLI remain under `.playwright-cli/`; superseded first-round captures remain under `superseded/` (a safety hook blocks recursive deletes).
