# Final eval: shipped configuration

Shipped 2026-10-25: `FridgeScanPipeline.scan(plan: ScanPlan.grid, style: ScanStyle.lean)` (one lean call below 3072 px, 2x2 tiles above), streamed in the app. Eval variant `v3-grid` (same pipeline, non-streamed). Median of 3 runs per photo. Baseline for comparison: `2026-10-25-baseline-rescored.md` (blurry 28%, clear 41% read+recog).

## Success targets

| Metric | Target | Result | Met? |
| --- | --- | --- | --- |
| Recall, blurry photo (readable + recognizable) | ≥ 70% | 83% | yes |
| Recall, clear photo (readable + recognizable) | ≥ 90% | 93% | yes |
| Hidden tier | reported only | clear 89% | — |
| Sure precision | ≥ 90% | blurry 100%, clear 82% | **no** on the clear photo: cross-tile duplicates and generic names ("condiment", "sauce") marked sure. Single-call v2-lean reached 92%. |
| Non-food leaks | 0 | 0 / 0 | yes |
| Latency (median wall time) | ≤ 15 s | 25 s / 30 s whole scan; first item on screen ~12 s / ~9 s with streaming | **no**: output speed (~100 tokens/s for ~50 items) bounds it; streaming added instead (plan revision 3) |
| Cost | ≤ $0.10 per scan (revision 3) | $0.028 / $0.092 | yes |

Total real eval spend: $3.20 of the $5 budget (ledger.json; one manual web run estimated, not metered).

Web check (2026-10-25, release build in Chrome): streaming progress, Maybe badges, alternative chip, one-press delete with Undo, Discard, and the blurry-photo warning all worked. Known issue: on web, preparing a 24 MP photo blocked the page for more than 5 s (photo prep runs on the page's single thread); fix by moving web prep to a Web Worker.

# Scan eval: v3-grid

Date: 2026-10-25T17:55:25.852748

Ledger total spent: $3.1039 of $4.50

## Photo: blurry

3/3 runs succeeded. Recall counts only items with visibleInBlurryPhoto=true.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 4/6 (67%) | 11/12 (92%) | n/a | 15/18 (83%) | 1 | 0 | 100% | 24.0s | $0.0268 |
| 2 | 4/6 (67%) | 11/12 (92%) | n/a | 15/18 (83%) | 1 | 1 | 67% | 27.0s | $0.0298 |
| 3 | 4/6 (67%) | 10/12 (83%) | n/a | 14/18 (78%) | 4 | 0 | 100% | 25.1s | $0.0282 |

Median recall: 
- readable 67%, recognizable 92%, hidden n/a, readable+recognizable 83%
- sure precision 100%
- false items 1.0, leaks 0.0
- latency 25.1s, cost $0.0282 per call

Per run details:

### Run 1
- hits: greek_yogurt, brown_eggs, black_pot_dish, orange_lid_tub, tomato_stew, brown_jar, honey, butter, chopped_salad, white_eggs, garlic_onions, knik_cheese, hummus, peppercorn_dressing, red_jam
- misses: sparkling_water, tuna, kvass
- false items: Pickles
- non-food leaks: 
- duplicates: Juice, Condiment, Tomato sauce, Snack bag, Sauce
- out of scope (neutral): Drink, Butter, Cooked meal, Mustard, Hot sauce

### Run 2
- hits: brown_eggs, hummus, orange_lid_tub, tomato_stew, black_pot_dish, brown_jar, honey, chopped_salad, white_eggs, garlic_onions, butter, red_jam, knik_cheese, peppercorn_dressing, greek_yogurt
- misses: sparkling_water, tuna, kvass
- false items: Rolled oats
- non-food leaks: Dark bottle
- duplicates: Sauce, Aloe vera drink, Pasta sauce, Tomato sauce, Snack bag
- out of scope (neutral): Milk, Lentil soup, Cheese, Produce, Vegetables, Green apple, Hot sauce

### Run 3
- hits: greek_yogurt, brown_eggs, hummus, orange_lid_tub, butter, tomato_stew, black_pot_dish, chopped_salad, white_eggs, brown_jar, red_jam, garlic_onions, knik_cheese, peppercorn_dressing
- misses: sparkling_water, tuna, kvass, honey
- false items: Produce, Electrolyte drink, Pickles, Dark sauce
- non-food leaks: 
- duplicates: Condiment, Salsa, Snack bag, Condiment
- out of scope (neutral): Juice, Butter, Mustard, Green apple, Hot sauce, Hot sauce

## Photo: clear

3/3 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 11/11 (100%) | 15/18 (83%) | 8/9 (89%) | 26/29 (90%) | 1 | 0 | 75% | 45.6s | $0.0920 |
| 2 | 10/11 (91%) | 18/18 (100%) | 8/9 (89%) | 28/29 (97%) | 2 | 0 | 92% | 28.1s | $0.0937 |
| 3 | 10/11 (91%) | 17/18 (94%) | 8/9 (89%) | 27/29 (93%) | 2 | 0 | 82% | 29.6s | $0.0924 |

Median recall: 
- readable 91%, recognizable 94%, hidden 89%, readable+recognizable 93%
- sure precision 82%
- false items 2.0, leaks 0.0
- latency 29.6s, cost $0.0924 per call

Per run details:

### Run 1
- hits: black_pot_dish, knik_cheese, brown_jar, brown_eggs, spices, lactose_free_milk, greek_yogurt, hummus, tuna, tomato_stew, soup_pot, red_jam, yellow_item_behind, honey, butter, chopped_salad, white_eggs, garlic_onions, bread, cheese_block, dill, milk_2pct, kvass, flax_seeds, bulgur, figs, orange_food_strainer, avocado, cucumbers, melon, peppercorn_dressing, ketchup, philadelphia, ranch
- misses: sparkling_water, orange_lid_tub, corn, eggplant
- false items: Greens
- non-food leaks: 
- duplicates: Greek yogurt, Sauce, Vinegar, Honey, Condiment, Sauce, Sauce, Pepper sauce, Mushrooms, Pickled peppers, Green soup, Sauce, Shredded cheese, White cheese, Dill, Hummus, Carrots, Cucumbers, Condiment, Blue snack bag, Lactose-free milk
- out of scope (neutral): 

### Run 2
- hits: soup_pot, knik_cheese, peppercorn_dressing, brown_eggs, brown_jar, hummus, greek_yogurt, tuna, tomato_stew, black_pot_dish, red_jam, butter, honey, orange_lid_tub, chopped_salad, white_eggs, garlic_onions, cheese_block, corn, melon, sparkling_water, yellow_item_behind, kvass, flax_seeds, spices, bread, bulgur, dill, figs, avocado, cucumbers, orange_food_strainer, ketchup, philadelphia, ranch, lactose_free_milk
- misses: eggplant, milk_2pct
- false items: Dry staple, Produce
- non-food leaks: 
- duplicates: Lentil soup, Condiment, Carton, Sauce, Honey, salsa, pickles, jam, Lettuce, Pickled peppers, Lemonade, Green soup, White cheese, Chickpeas, Tomatoes, Melon, Zucchini, Cream bottle, Seasoning, Organic ketchup, Snack bag
- out of scope (neutral): 

### Run 3
- hits: black_pot_dish, yellow_item_behind, knik_cheese, brown_eggs, brown_jar, greek_yogurt, hummus, tuna, tomato_stew, soup_pot, red_jam, butter, honey, orange_lid_tub, chopped_salad, white_eggs, figs, bread, cheese_block, dill, peppercorn_dressing, sparkling_water, kvass, spices, flax_seeds, garlic_onions, bulgur, avocado, orange_food_strainer, cucumbers, melon, ketchup, philadelphia, ranch, lactose_free_milk
- misses: corn, eggplant, milk_2pct
- false items: Condiment, Drink can
- non-food leaks: 
- duplicates: Stonyfield Greek yogurt, Honey, sauce, condiment, condiment, condiment, condiment, condiment, sauce packet, Tortillas, Lemonade, Green herb soup, Flatbread, Blueberries, White cheese, Hummus, Fresh dill, Tomatoes, Cucumbers, Condiment bottle, Organic ketchup, Shredded cheese
- out of scope (neutral): 
