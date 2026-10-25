# Scan eval (re-scored): baseline

Date: 2026-10-25T15:01:24.929280

Re-scored 6 saved raw outputs against the current answer key. No API calls; the ledger was not touched. Cost is computed from saved token counts.

## Photo: blurry

3/3 runs succeeded. Recall counts only items with visibleInBlurryPhoto=true.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2/6 (33%) | 3/13 (23%) | n/a | 5/19 (26%) | 2 | 1 | 63% | 9.5s | $0.0089 |
| 2 | 3/6 (50%) | 3/13 (23%) | n/a | 6/19 (32%) | 3 | 1 | 60% | 20.9s | $0.0102 |
| 3 | 2/6 (33%) | 4/13 (31%) | n/a | 6/19 (32%) | 1 | 1 | 75% | 11.3s | $0.0090 |

Median recall: 
- readable 33%, recognizable 23%, hidden n/a, readable+recognizable 32%
- sure precision 63%
- false items 2.0, leaks 1.0
- latency 11.3s, cost $0.0090 per call

Per run details:

### Run 1
- hits: white_eggs, butter, greek_yogurt, red_jam, tomato_stew
- misses: knik_cheese, sparkling_water, dark_sauce, tuna, orange_lid_tub, hummus, black_pot_dish, brown_jar, chopped_salad, brown_eggs, garlic_onions, kvass, peppercorn_dressing, honey
- false items: Cauliflower, Cinnamon Rolls Dough
- non-food leaks: Liquid Iron Supplement
- duplicates: 
- out of scope (neutral): 

### Run 2
- hits: white_eggs, butter, greek_yogurt, dark_sauce, peppercorn_dressing, black_pot_dish
- misses: knik_cheese, sparkling_water, tuna, orange_lid_tub, hummus, tomato_stew, red_jam, brown_jar, chopped_salad, brown_eggs, garlic_onions, kvass, honey
- false items: Cauliflower, Juice Boxes, Condiment Jars
- non-food leaks: Liquid Iron Supplement
- duplicates: 
- out of scope (neutral): 

### Run 3
- hits: white_eggs, butter, greek_yogurt, dark_sauce, red_jam, black_pot_dish
- misses: knik_cheese, sparkling_water, tuna, orange_lid_tub, hummus, tomato_stew, brown_jar, chopped_salad, brown_eggs, garlic_onions, kvass, peppercorn_dressing, honey
- false items: Cauliflower
- non-food leaks: Liquid Iron Supplement
- duplicates: 
- out of scope (neutral): 

## Photo: clear

3/3 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 8/11 (73%) | 6/19 (32%) | 2/8 (25%) | 14/30 (47%) | 1 | 0 | 89% | 22.9s | $0.0150 |
| 2 | 8/11 (73%) | 6/19 (32%) | 3/8 (38%) | 14/30 (47%) | 1 | 0 | 94% | 26.4s | $0.0144 |
| 3 | 8/11 (73%) | 5/19 (26%) | 4/8 (50%) | 13/30 (43%) | 0 | 0 | 85% | 21.5s | $0.0160 |

Median recall: 
- readable 73%, recognizable 32%, hidden 38%, readable+recognizable 47%
- sure precision 89%
- false items 1.0, leaks 0.0
- latency 22.9s, cost $0.0150 per call

Per run details:

### Run 1
- hits: knik_cheese, white_eggs, greek_yogurt, butter, red_jam, spices, dill, bulgur, dark_sauce, cucumbers, kvass, honey, ketchup, philadelphia, ranch, milk_2pct
- misses: sparkling_water, orange_food_strainer, tuna, orange_lid_tub, hummus, tomato_stew, black_pot_dish, brown_jar, yellow_item_behind, chopped_salad, brown_eggs, garlic_onions, corn, soup_pot, melon, cheese_block, eggplant, bread, avocado, peppercorn_dressing, lactose_free_milk, flax_seeds
- false items: Mushrooms
- non-food leaks: 
- duplicates: Hot Pepper Sauce
- out of scope (neutral): 

### Run 2
- hits: knik_cheese, white_eggs, greek_yogurt, butter, red_jam, bread, garlic_onions, dill, cheese_block, dark_sauce, cucumbers, kvass, spices, ketchup, philadelphia, ranch, milk_2pct
- misses: sparkling_water, orange_food_strainer, tuna, orange_lid_tub, hummus, tomato_stew, black_pot_dish, brown_jar, yellow_item_behind, chopped_salad, brown_eggs, corn, soup_pot, melon, eggplant, bulgur, avocado, peppercorn_dressing, lactose_free_milk, honey, flax_seeds
- false items: Pomegranate Juice
- non-food leaks: 
- duplicates: 
- out of scope (neutral): 

### Run 3
- hits: knik_cheese, white_eggs, greek_yogurt, butter, bread, yellow_item_behind, spices, dill, cheese_block, dark_sauce, cucumbers, kvass, flax_seeds, ketchup, philadelphia, ranch, milk_2pct
- misses: sparkling_water, orange_food_strainer, tuna, orange_lid_tub, hummus, tomato_stew, black_pot_dish, red_jam, brown_jar, chopped_salad, brown_eggs, garlic_onions, corn, soup_pot, melon, eggplant, bulgur, avocado, peppercorn_dressing, lactose_free_milk, honey
- false items: 
- non-food leaks: 
- duplicates: Fresh White Cheese, Pepper Sauce, Blue Cheese Crumbles
- out of scope (neutral): 
