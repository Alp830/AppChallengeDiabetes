# Scan eval (re-scored): baseline

Date: 2026-10-25T22:50:22.804888

Re-scored 6 saved raw outputs against the current answer key. No API calls; the ledger was not touched. Cost is computed from saved token counts.

## Photo: blurry

3/3 runs succeeded. Recall counts only items with visibleInBlurryPhoto=true.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2/6 (33%) | 3/12 (25%) | n/a | 5/18 (28%) | 2 | 1 | 63% | 9.5s | $0.0089 |
| 2 | 3/6 (50%) | 2/12 (17%) | n/a | 5/18 (28%) | 4 | 1 | 50% | 20.9s | $0.0102 |
| 3 | 2/6 (33%) | 3/12 (25%) | n/a | 5/18 (28%) | 2 | 1 | 63% | 11.3s | $0.0090 |

Median recall: 
- readable 33%, recognizable 25%, hidden n/a, readable+recognizable 28%
- sure precision 63%
- false items 2.0, leaks 1.0
- latency 11.3s, cost $0.0090 per call

Per run details:

### Run 1
- hits: white_eggs, butter, greek_yogurt, red_jam, tomato_stew
- misses: knik_cheese, sparkling_water, tuna, orange_lid_tub, hummus, black_pot_dish, brown_jar, chopped_salad, brown_eggs, garlic_onions, kvass, peppercorn_dressing, honey
- false items: Cauliflower, Cinnamon Rolls Dough
- non-food leaks: Liquid Iron Supplement
- duplicates: 
- out of scope (neutral): 

### Run 2
- hits: white_eggs, butter, greek_yogurt, peppercorn_dressing, black_pot_dish
- misses: knik_cheese, sparkling_water, tuna, orange_lid_tub, hummus, tomato_stew, red_jam, brown_jar, chopped_salad, brown_eggs, garlic_onions, kvass, honey
- false items: Cauliflower, Juice Boxes, Hot Sauce or Red Sauce, Condiment Jars
- non-food leaks: Liquid Iron Supplement
- duplicates: 
- out of scope (neutral): 

### Run 3
- hits: white_eggs, butter, greek_yogurt, red_jam, black_pot_dish
- misses: knik_cheese, sparkling_water, tuna, orange_lid_tub, hummus, tomato_stew, brown_jar, chopped_salad, brown_eggs, garlic_onions, kvass, peppercorn_dressing, honey
- false items: Cauliflower, Hot Sauce or Red Condiment
- non-food leaks: Liquid Iron Supplement
- duplicates: 
- out of scope (neutral): 

## Photo: clear

3/3 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 7/11 (64%) | 5/18 (28%) | 2/9 (22%) | 12/29 (41%) | 2 | 1 | 78% | 22.9s | $0.0150 |
| 2 | 7/11 (64%) | 5/18 (28%) | 3/9 (33%) | 12/29 (41%) | 2 | 1 | 83% | 26.4s | $0.0144 |
| 3 | 7/11 (64%) | 4/18 (22%) | 4/9 (44%) | 11/29 (38%) | 1 | 1 | 75% | 21.5s | $0.0160 |

Median recall: 
- readable 64%, recognizable 28%, hidden 33%, readable+recognizable 41%
- sure precision 78%
- false items 2.0, leaks 1.0
- latency 22.9s, cost $0.0150 per call

Per run details:

### Run 1
- hits: knik_cheese, white_eggs, greek_yogurt, butter, red_jam, spices, dill, bulgur, cucumbers, honey, ketchup, philadelphia, ranch, milk_2pct
- misses: sparkling_water, orange_food_strainer, tuna, orange_lid_tub, hummus, tomato_stew, black_pot_dish, brown_jar, yellow_item_behind, chopped_salad, brown_eggs, garlic_onions, corn, soup_pot, melon, cheese_block, eggplant, bread, avocado, kvass, peppercorn_dressing, lactose_free_milk, flax_seeds, figs
- false items: Mushrooms, Pomegranate
- non-food leaks: Kvass Gut Tonic
- duplicates: Hot Pepper Sauce
- out of scope (neutral): 

### Run 2
- hits: knik_cheese, white_eggs, greek_yogurt, butter, red_jam, bread, garlic_onions, dill, cheese_block, cucumbers, spices, ketchup, philadelphia, ranch, milk_2pct
- misses: sparkling_water, orange_food_strainer, tuna, orange_lid_tub, hummus, tomato_stew, black_pot_dish, brown_jar, yellow_item_behind, chopped_salad, brown_eggs, corn, soup_pot, melon, eggplant, bulgur, avocado, kvass, peppercorn_dressing, lactose_free_milk, honey, flax_seeds, figs
- false items: Pomegranate Juice, Pomegranate
- non-food leaks: Sauerkraut Tonic (Kvass)
- duplicates: 
- out of scope (neutral): 

### Run 3
- hits: knik_cheese, white_eggs, greek_yogurt, butter, bread, yellow_item_behind, spices, dill, cheese_block, cucumbers, flax_seeds, ketchup, philadelphia, ranch, milk_2pct
- misses: sparkling_water, orange_food_strainer, tuna, orange_lid_tub, hummus, tomato_stew, black_pot_dish, red_jam, brown_jar, chopped_salad, brown_eggs, garlic_onions, corn, soup_pot, melon, eggplant, bulgur, avocado, kvass, peppercorn_dressing, lactose_free_milk, honey, figs
- false items: Pomegranate
- non-food leaks: Kvass Sauerkraut Tonic
- duplicates: Fresh White Cheese, Pepper Sauce, Blue Cheese Crumbles
- out of scope (neutral): 
