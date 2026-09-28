# OutlineForV2

## Goal
Make the fridge and meals flow easier to understand and use. This is mostly a visual and user experience update, with a few small behavior changes for retries and saved recipes. Keep the current look and feel of the app.

## Some problems

* First time users may not know where to start or how to make their first meal.
* A failed API call leaves the user to retry it themselves.
* Fridge items get messy when there are many items.
* A user may want to make a recipe they already like without asking the agent again.
* It is easy to leave while a fridge change is unsaved or a recipe is still loading.

## Solution

### A first time user entry

When the user enters the app for the first time, show a `Let's get started` card on Home, similar to the fridge card. It should take them through making their first meal. Do not show it again once they finish or dismiss it. Returning users should go straight to the normal Home page.

Go through these options when planning the flow:

* **Short walkthrough:** the card opens Meals and points out the prompt, meal type, and `Recommend a meal` button. The user makes their own first request.
* **Guided first meal:** the card asks them to add a food to the Fridge first, then takes them to Meals with a suggested prompt they can edit.
* **Example first:** the card opens Meals with an example prompt already filled in, so the user can try a recommendation without adding fridge items.

Pick the option that takes the least work for a new user to understand. The walkthrough should be skippable, and a user with an empty fridge should still be able to make a meal request.

### API consistency

If a user-facing AI request fails for a temporary reason, retry it automatically, up to **5 attempts total**. The first request is attempt 1. Only show the retry state after that first request fails.

* While attempt 1 is running, show the normal loading state.
* On attempts 2 through 5, tell the user what is happening: `Retrying 2/5`, `Retrying 3/5`, and so on.
* If a retry succeeds, show the result normally and remove the retry message.
* If attempt 5 fails, show a friendly error and a manual `Try again` button. The manual button starts a new request with a new set of attempts.
* Only retry errors that might recover, such as a timeout or temporary service error. Do not retry a bad request, a missing API key, or a permission error five times.

Apply this to the fridge photo scan, meal recommendations, and meal questions where it makes sense. Keep the user's request and preferences the same across attempts. If they leave or cancel, stop the retry and do not show an old result on a different screen.

### Fridge item organization

Group fridge items under headers based on their existing food type. For example:

```text
Grain
  Rice  Bread  Oats

Other
  Items that do not fit another type
```

Use the app's current food types: Produce, Protein, Dairy, Grain, Snack, Drink, and Other. Show only groups that have items. Keep the existing expiry order inside each group, and show the item count at the top. Changing an item's food type should move it into the right group immediately in the draft view.

Keep the existing way to add, edit, scan, and select foods. Make `Delete item` easy to find in the top right of the edit sheet, with a clear label or accessible tooltip so it is not mistaken for closing the sheet. Deleting an item should be a draft change until the user saves the fridge.

The app already has Save, Discard, and an unsaved changes bar. Keep that behavior with the new grouped view: users can make several changes, save them together, or discard them together. Selection and bulk delete should still work across groups.

### Saved recipes

Add a `Save recipe` button on each recipe card in Meals. Once saved, the button should show that the recipe is saved and let the user remove it from saved recipes if they choose.

Show a `Saved recipes` card on Home. Tapping it opens a list of the user's saved recipes. Tapping one recipe opens the full recipe with its ingredients and steps, without making another AI request. If there are no saved recipes yet, show a simple empty state that points the user to Meals.

Save the recipe itself, not just the name or the prompt. Keep saved recipes with the signed-in user's account so they are there when the app is opened again. A saved recipe is separate from logging a meal or saving a meal template.

### Leaving with work in progress

If the fridge has unsaved changes, ask before leaving. Give the user `Save changes`, `Discard`, and `Keep editing`. This should also cover leaving by switching tabs or signing out. If saving fails, keep them on the Fridge with their changes still there.

If a recipe is still loading and the user tries to leave Meals, ask if they want to stop waiting. `Keep waiting` stays on the page; `Leave` cancels or ignores the result. Do not say that saved recipes or fridge changes will be discarded when only a recipe request is loading.

If both situations happen at once, make sure the user understands what will be lost before leaving. Do not show a warning when there is nothing in progress.

## UI

Make the new UI feel production quality and fit the UI I have currently. Use the same colors, spacing, cards, buttons, and friendly language. The new Home cards, group headers, recipe buttons, and retry messages should feel like they belong in the app.

Check the small phone layout, large text, loading and empty states, and touch targets. Do not leave placeholder text or buttons that do nothing.

## Priming

Before adding, please prime yourself with `C:/AppChallengeDiabetes/subsets/contents/${SpecificContent}.md` please do this after reading all of this outline on all of the topics you need to know to implement. Feel free prime on more than one, you can simply do this by reading multiple.

## Workflow

1. **Plan:** ask me the questions needed to settle the first time flow and any unclear behavior. Use the `pi-superpowers:writing-plans` skill. Give each worktree its own part of the plan and Definition of Done.
2. **Ask me for feedback:** show me the plan before implementing, and update it based on my feedback.
3. **Implement in 3 git worktrees, in parallel:**
   * **Fridge:** grouping, delete placement, and Save/Discard behavior with groups.
   * **API:** retry rules, retry progress, final errors, and stopping a request when the user leaves.
   * **First user experience:** the first time Home entry, saved recipes on Meals and Home, and the leave warning while a recipe loads.
   * Give each worktree a root agent primed on its task, its part of the plan, and its own Definition of Done. Root agents execute with workers, then verify their work against that Definition of Done.
4. **Merge:** once all three root agents are done and verified, merge their work. Resolve shared-file conflicts carefully, especially where Fridge and Meals code meet.
5. **Final check:** run the app's relevant checks, go through the full Definition of Done yourself, and fix anything the merged version missed.

## Implementation Notes

* Use the current Flutter Material 3 design and the app's existing food types. This outline does not call for a new visual theme or changes to the diabetes features.
* Fridge Save/Discard, edit-sheet delete, and the fridge leave warning already exist. Update those flows for grouping and placement instead of building a second copy.
* Keep retries in one place for the AI calls so the attempt count and rules are consistent. Space retries out briefly instead of sending five calls at once. Avoid automatic retries for writes that could create duplicate data.
* The first time entry and saved recipes need to persist per user. Saved recipes should still open if the AI service is unavailable.
* Keep loading, empty, error, and large-text states readable on a phone.
* Worktrees may touch some of the same files. Each root agent should keep its changes scoped to its part, and the final check should cover the combined flow after merging.

## Deliverables

* A first time entry from Home to the user's first meal, with the chosen option and a way to skip it.
* Visible retry progress and a useful final error for the in-scope AI requests.
* A fridge grouped by food type, with delete, Save, Discard, and selection working together.
* Save/remove recipe controls, a Saved recipes entry on Home, and a full saved recipe view.
* Leave confirmations for unsaved fridge changes and an in-progress recipe request.
* A short note on the onboarding option chosen and why.

### Definition of Done

* A new user can get from Home to their first recipe without guessing what to tap; a returning user does not see the first time card again.
* A temporary AI failure shows `Retrying 2/5` through the last attempt as needed, then either succeeds or ends with `Try again`. A non-retryable error stops promptly.
* Fridge items appear under the correct type header, including after editing their type. Save persists changes; Discard restores the last saved fridge.
* A deleted fridge item is not permanently removed until Save. Leaving with unsaved changes gives the three choices above.
* A recipe can be saved, reopened after restarting the app, viewed without another AI call, and removed from saved recipes.
* Leaving while a recipe loads requires a choice, and a result from the old request does not appear after leaving.
* The main flow works on a small phone and with larger text, with labels a screen reader can understand.

## What you are graded on

* How clear the first time experience is.
* Whether retries explain what is happening without making duplicate or unnecessary requests.
* Whether a crowded fridge is easier to scan and edit.
* Whether saving a recipe actually removes the need to prompt the agent again.
* Whether users keep control of their unsaved changes and in-progress requests.
* How well the changes fit the app's current style.
