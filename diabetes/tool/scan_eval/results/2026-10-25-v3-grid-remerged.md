# Scan eval (re-merged): v3-grid

Date: 2026-10-25T17:30:10.338384

Re-merged 3 saved raw outputs with the current mergeScans and re-scored them against the current answer key. No API calls; the ledger was not touched. Cost is computed from saved token counts.

- clear run 1: 67 items saved, 73 before merge (4 calls), 61 after re-merge, 21 duplicates.
- clear run 2: 61 items saved, 66 before merge (4 calls), 56 after re-merge, 17 duplicates.
- clear run 3: 55 items saved, 65 before merge (4 calls), 53 after re-merge, 16 duplicates.

## Photo: clear

3/3 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 9/11 (82%) | 17/18 (94%) | 8/9 (89%) | 26/29 (90%) | 5 | 1 | 75% | 30.6s | $0.0954 |
| 2 | 10/11 (91%) | 17/18 (94%) | 8/9 (89%) | 27/29 (93%) | 4 | 0 | 79% | 39.9s | $0.0911 |
| 3 | 11/11 (100%) | 16/18 (89%) | 9/9 (100%) | 27/29 (93%) | 1 | 0 | 69% | 38.6s | $0.0898 |

Median recall: 
- readable 91%, recognizable 94%, hidden 89%, readable+recognizable 93%
- sure precision 75%
- false items 4.0, leaks 0.0
- latency 38.6s, cost $0.0911 per call

Per run details:

### Run 1
- hits: soup_pot, black_pot_dish, knik_cheese, brown_eggs, brown_jar, hummus, greek_yogurt, tuna, tomato_stew, bulgur, butter, honey, orange_lid_tub, chopped_salad, white_eggs, figs, bread, cheese_block, avocado, spices, sparkling_water, red_jam, yellow_item_behind, peppercorn_dressing, flax_seeds, garlic_onions, dill, corn, cucumbers, orange_food_strainer, ketchup, philadelphia, ranch, lactose_free_milk
- misses: melon, eggplant, kvass, milk_2pct
- false items: Dry staple, Canned drink, Sauce Packet, Lettuce, Mushrooms
- non-food leaks: Beet Kvass Tonic
- duplicates: Organic Greek yogurt, Red pepper paste, Sauce, Condiment, Sauce, Jam, Hot Sauce, Lemonade, Flatbread, White cheese, Dill, Bulgur, Blueberries, Tomatoes, Pomegranate, Sesame seeds, Cucumbers, Garlic, Condiment bottle, Trader Joe's Organic Ketchup, Snack bag
- out of scope (neutral): 

### Run 2
- hits: black_pot_dish, orange_food_strainer, knik_cheese, brown_eggs, spices, brown_jar, greek_yogurt, hummus, tuna, tomato_stew, bulgur, red_jam, yellow_item_behind, honey, butter, chopped_salad, white_eggs, garlic_onions, bread, cheese_block, avocado, peppercorn_dressing, kvass, flax_seeds, soup_pot, orange_lid_tub, dill, corn, figs, cucumbers, melon, ketchup, philadelphia, ranch, lactose_free_milk
- misses: sparkling_water, eggplant, milk_2pct
- false items: Green tea, Balsamic glaze, Jarred sauce, Mushrooms
- non-food leaks: 
- duplicates: Organic Greek yogurt, Apple sauce, Sauce in small jar, Green boxed item, Jarred condiment, Mustard, Fontana Farms pepper sauce, Cabbage, Pickled peppers, Lemonade, Flatbread, Bulgur, Pomegranate, Cucumbers, Condiment bottle, Trader Joe's organic ketchup, Snack
- out of scope (neutral): 

### Run 3
- hits: black_pot_dish, orange_food_strainer, knik_cheese, brown_eggs, spices, brown_jar, greek_yogurt, hummus, tuna, tomato_stew, soup_pot, red_jam, butter, honey, cheese_block, chopped_salad, white_eggs, garlic_onions, bread, eggplant, lactose_free_milk, yellow_item_behind, kvass, flax_seeds, peppercorn_dressing, dill, bulgur, corn, figs, avocado, cucumbers, melon, ketchup, milk_2pct, philadelphia, ranch
- misses: sparkling_water, orange_lid_tub
- false items: Lettuce
- non-food leaks: 
- duplicates: Greek yogurt, Cheese wheel, Condiment, Broth, Sauce, Pepper sauce, Pickled peppers, Green soup, Hummus, White cheese, Carrots, Cucumbers, Sauce, Organic ketchup, Blue bag snack, Lactose-free reduced fat milk
- out of scope (neutral): 
