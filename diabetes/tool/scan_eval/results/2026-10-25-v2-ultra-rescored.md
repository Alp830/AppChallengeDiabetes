# Scan eval (re-scored): v2-ultra

Date: 2026-10-25T15:01:48.848044

Re-scored 3 saved raw outputs against the current answer key. No API calls; the ledger was not touched. Cost is computed from saved token counts.

## Photo: blurry

2/2 runs succeeded. Recall counts only items with visibleInBlurryPhoto=true.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 3/6 (50%) | 11/13 (85%) | n/a | 14/19 (74%) | 4 | 0 | 100% | 81.5s | $0.0378 |
| 3 | 3/6 (50%) | 11/13 (85%) | n/a | 14/19 (74%) | 1 | 0 | 100% | 89.7s | $0.0532 |

Median recall: 
- readable 50%, recognizable 85%, hidden n/a, readable+recognizable 74%
- sure precision 100%
- false items 2.5, leaks 0.0
- latency 85.6s, cost $0.0455 per call

Per run details:

### Run 1
- hits: peppercorn_dressing, hummus, orange_lid_tub, butter, tomato_stew, black_pot_dish, red_jam, honey, chopped_salad, white_eggs, garlic_onions, sparkling_water, brown_jar, knik_cheese
- misses: dark_sauce, greek_yogurt, tuna, brown_eggs, kvass
- false items: Rolled Oats, Juice Boxes, Fresh Produce, Guacamole
- non-food leaks: 
- duplicates: Salad Dressing, Tomato Sauce
- out of scope (neutral): Cream Cheese, Mustard, Cheddar Cheese, Hot Sauce

### Run 3
- hits: dark_sauce, knik_cheese, hummus, orange_lid_tub, butter, tomato_stew, black_pot_dish, red_jam, honey, chopped_salad, white_eggs, garlic_onions, brown_jar, peppercorn_dressing
- misses: sparkling_water, greek_yogurt, tuna, brown_eggs, kvass
- false items: Oats
- non-food leaks: 
- duplicates: Juice boxes, Peeled garlic, Guacamole, Cheddar cheese, Maple syrup, Dark glass bottle, Snack pouch, Condiment bottle
- out of scope (neutral): Eggs, Cheese block, Ghee, Chili sauce, Tomato pasta sauce

## Photo: clear

1/1 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 10/11 (91%) | 14/19 (74%) | 7/8 (88%) | 24/30 (80%) | 4 | 0 | 86% | 76.1s | $0.0939 |

Median recall: 
- readable 91%, recognizable 74%, hidden 88%, readable+recognizable 80%
- sure precision 86%
- false items 4.0, leaks 0.0
- latency 76.1s, cost $0.0939 per call

Per run details:

### Run 1
- hits: knik_cheese, butter, brown_eggs, hummus, dark_sauce, greek_yogurt, tomato_stew, soup_pot, red_jam, honey, black_pot_dish, white_eggs, garlic_onions, bread, eggplant, spices, dill, bulgur, brown_jar, avocado, cucumbers, yellow_item_behind, kvass, flax_seeds, peppercorn_dressing, ketchup, philadelphia, ranch, cheese_block, lactose_free_milk, milk_2pct
- misses: sparkling_water, orange_food_strainer, tuna, orange_lid_tub, chopped_salad, corn, melon
- false items: Canned Fish, Frozen Meat, Jarred Condiment, Green Drink Carton
- non-food leaks: 
- duplicates: Mashed Potatoes, Cooked Lentils, Grass-Fed Butter, Soup, Bulgur, White Rice, Zucchini, Spice Jar, Condiment Jar, Dark Glass Jar, Seasoning, Beverage Bottle, Honey, Pepper Sauce
- out of scope (neutral): 
