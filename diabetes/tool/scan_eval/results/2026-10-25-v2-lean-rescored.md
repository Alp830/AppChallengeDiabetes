# Scan eval (re-scored): v2-lean

Date: 2026-10-25T17:06:03.953723

Re-scored 6 saved raw outputs against the current answer key. No API calls; the ledger was not touched. Cost is computed from saved token counts.

## Photo: blurry

3/3 runs succeeded. Recall counts only items with visibleInBlurryPhoto=true.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 4/6 (67%) | 12/12 (100%) | n/a | 16/18 (89%) | 6 | 0 | 50% | 26.9s | $0.0331 |
| 2 | 3/6 (50%) | 10/12 (83%) | n/a | 13/18 (72%) | 4 | 0 | 100% | 25.7s | $0.0304 |
| 3 | 3/6 (50%) | 12/12 (100%) | n/a | 15/18 (83%) | 5 | 0 | 100% | 28.6s | $0.0337 |

Median recall: 
- readable 50%, recognizable 100%, hidden n/a, readable+recognizable 83%
- sure precision 100%
- false items 5.0, leaks 0.0
- latency 26.9s, cost $0.0331 per call

Per run details:

### Run 1
- hits: brown_eggs, sparkling_water, hummus, orange_lid_tub, tomato_stew, brown_jar, black_pot_dish, red_jam, honey, butter, chopped_salad, white_eggs, garlic_onions, knik_cheese, peppercorn_dressing, greek_yogurt
- misses: tuna, kvass
- false items: Quaker Oats, Produce in bag, Bagged greens, Guacamole, Relish, Dark bottle sauce
- non-food leaks: 
- duplicates: Produce in bag, Orange juice, Electrolyte drink, Dark jar condiment, Peanut butter, Tomato sauce, Blue snack bag
- out of scope (neutral): Butter, Mustard, Mustard, Hot sauce

### Run 2
- hits: white_eggs, sparkling_water, hummus, orange_lid_tub, tomato_stew, brown_jar, red_jam, black_pot_dish, brown_eggs, butter, knik_cheese, chopped_salad, peppercorn_dressing
- misses: greek_yogurt, tuna, garlic_onions, kvass, honey
- false items: Oats, Cauliflower, Guacamole, Sauce bottle
- non-food leaks: 
- duplicates: Mustard, Orange juice, Condiment, Electrolyte drink, Sauce, Jam, Tomato sauce, Snack bag
- out of scope (neutral): Cooked food, Cheese, Cooked meal

### Run 3
- hits: brown_eggs, sparkling_water, black_pot_dish, hummus, orange_lid_tub, tomato_stew, brown_jar, honey, butter, chopped_salad, white_eggs, garlic_onions, knik_cheese, peppercorn_dressing, red_jam
- misses: greek_yogurt, tuna, kvass
- false items: Oats canister, Cooked meal, Guacamole, Soy sauce, Marinade
- non-food leaks: 
- duplicates: Peanut butter, Tomato sauce, Electrolyte drink, Tortilla chips
- out of scope (neutral): Butter, Cheese block, Leafy greens, Berry jam, Mustard, Orange juice, Milk, Hot sauce

## Photo: clear

3/3 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 10/11 (91%) | 17/18 (94%) | 8/9 (89%) | 27/29 (93%) | 1 | 1 | 83% | 51.2s | $0.0621 |
| 2 | 11/11 (100%) | 14/18 (78%) | 9/9 (100%) | 25/29 (86%) | 2 | 0 | 92% | 46.0s | $0.0504 |
| 3 | 10/11 (91%) | 15/18 (83%) | 8/9 (89%) | 25/29 (86%) | 3 | 0 | 93% | 48.3s | $0.0493 |

Median recall: 
- readable 91%, recognizable 83%, hidden 89%, readable+recognizable 86%
- sure precision 92%
- false items 2.0, leaks 0.0
- latency 48.3s, cost $0.0504 per call

Per run details:

### Run 1
- hits: knik_cheese, black_pot_dish, brown_eggs, brown_jar, orange_lid_tub, hummus, greek_yogurt, tuna, tomato_stew, bulgur, avocado, butter, chopped_salad, white_eggs, bread, eggplant, corn, soup_pot, peppercorn_dressing, dill, figs, garlic_onions, cucumbers, spices, yellow_item_behind, red_jam, honey, sparkling_water, flax_seeds, ketchup, philadelphia, ranch, cheese_block, lactose_free_milk, milk_2pct
- misses: orange_food_strainer, melon, kvass
- false items: Syrup bottle
- non-food leaks: Sauerkraut tonic kvass
- duplicates: Tomato sauce, Sliced cheese, Frozen meat, Cheese wheel, White cheese, Bulgur, Zucchini, Honey, Pepper sauce, Peanut butter
- out of scope (neutral): 

### Run 2
- hits: knik_cheese, brown_eggs, black_pot_dish, hummus, orange_lid_tub, greek_yogurt, tuna, tomato_stew, soup_pot, brown_jar, red_jam, butter, yellow_item_behind, white_eggs, bread, cheese_block, eggplant, corn, peppercorn_dressing, dill, bulgur, figs, avocado, cucumbers, orange_food_strainer, spices, kvass, honey, flax_seeds, ketchup, philadelphia, ranch, lactose_free_milk, milk_2pct
- misses: sparkling_water, chopped_salad, garlic_onions, melon
- false items: Dark juice, Juice box
- non-food leaks: 
- duplicates: Sausages, Cheese slices, Meat, Soup, Fresh cheese, Zucchini, Condiment jar, Seasoning, Dressing bottle, Pepper sauce, Tahini, Shredded cheese
- out of scope (neutral): 

### Run 3
- hits: cheese_block, brown_eggs, knik_cheese, hummus, greek_yogurt, tuna, tomato_stew, soup_pot, yellow_item_behind, red_jam, butter, white_eggs, bread, garlic_onions, eggplant, spices, black_pot_dish, bulgur, dill, avocado, orange_food_strainer, cucumbers, brown_jar, honey, sparkling_water, kvass, flax_seeds, ketchup, philadelphia, ranch, corn, lactose_free_milk, milk_2pct
- misses: orange_lid_tub, chopped_salad, melon, peppercorn_dressing, figs
- false items: Red wine, Roasted nuts, Jarred condiment
- non-food leaks: 
- duplicates: Fruit jam, Sliced cheese, Cheese wheel, White cheese, Zucchini, Spice jar, Seasoning container, Hot sauce, Broth concentrate, Pepper sauce, Tahini
- out of scope (neutral): 
