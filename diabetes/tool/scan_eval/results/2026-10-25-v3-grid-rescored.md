# Scan eval (re-scored): v3-grid

Date: 2026-10-25T22:50:16.238799

Re-scored 12 saved raw outputs against the current answer key. No API calls; the ledger was not touched. Cost is computed from saved token counts.

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

9/9 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 10/11 (91%) | 16/18 (89%) | 9/9 (100%) | 26/29 (90%) | 7 | 0 | 80% | 31.9s | $0.0947 |
| 1 | 9/11 (82%) | 17/18 (94%) | 8/9 (89%) | 26/29 (90%) | 6 | 1 | 75% | 30.6s | $0.0954 |
| 1 | 11/11 (100%) | 15/18 (83%) | 8/9 (89%) | 26/29 (90%) | 1 | 0 | 75% | 45.6s | $0.0920 |
| 2 | 11/11 (100%) | 16/18 (89%) | 9/9 (100%) | 27/29 (93%) | 2 | 0 | 75% | 32.6s | $0.0944 |
| 2 | 10/11 (91%) | 17/18 (94%) | 8/9 (89%) | 27/29 (93%) | 4 | 0 | 79% | 39.9s | $0.0911 |
| 2 | 10/11 (91%) | 18/18 (100%) | 8/9 (89%) | 28/29 (97%) | 2 | 0 | 92% | 28.1s | $0.0937 |
| 3 | 11/11 (100%) | 16/18 (89%) | 8/9 (89%) | 27/29 (93%) | 5 | 0 | 75% | 49.6s | $0.0927 |
| 3 | 11/11 (100%) | 16/18 (89%) | 9/9 (100%) | 27/29 (93%) | 1 | 0 | 69% | 38.6s | $0.0898 |
| 3 | 10/11 (91%) | 17/18 (94%) | 8/9 (89%) | 27/29 (93%) | 2 | 0 | 82% | 29.6s | $0.0924 |

Median recall: 
- readable 91%, recognizable 89%, hidden 89%, readable+recognizable 93%
- sure precision 75%
- false items 2.0, leaks 0.0
- latency 32.6s, cost $0.0927 per call

Per run details:

### Run 1
- hits: black_pot_dish, knik_cheese, brown_jar, brown_eggs, spices, orange_lid_tub, hummus, greek_yogurt, cheese_block, tomato_stew, soup_pot, red_jam, yellow_item_behind, honey, butter, chopped_salad, white_eggs, garlic_onions, bread, eggplant, kvass, peppercorn_dressing, flax_seeds, dill, bulgur, corn, figs, avocado, orange_food_strainer, cucumbers, ketchup, milk_2pct, philadelphia, ranch, lactose_free_milk
- misses: sparkling_water, tuna, melon
- false items: Condiment, Maple syrup, jarred item, jarred item, bagged item, Walnuts, Romaine lettuce
- non-food leaks: 
- duplicates: Juice, Tortillas, Apple sauce, sauce jar, green cartons, condiment packet, yellow jar, broth jar, Cooked vegetable stew, Mushrooms, Flatbread, Fresh cheese, Pickled peppers, Lemon juice, Herb soup, Marinated meat, White cheese, Tomatoes, Rice, Cucumbers, Eggplant, Peanut butter, Sauerkraut, Fontana Farms Pepper Jelly, Spice, Trader Joe's Organic Ketchup, Organic seeds, Lactose-Free 2% Milk
- out of scope (neutral): 

### Run 1
- hits: soup_pot, black_pot_dish, knik_cheese, brown_eggs, brown_jar, hummus, greek_yogurt, tuna, tomato_stew, bulgur, butter, honey, orange_lid_tub, corn, white_eggs, figs, bread, dill, sparkling_water, red_jam, spices, yellow_item_behind, peppercorn_dressing, flax_seeds, chopped_salad, cheese_block, avocado, garlic_onions, cucumbers, orange_food_strainer, ketchup, philadelphia, ranch, lactose_free_milk
- misses: melon, eggplant, kvass, milk_2pct
- false items: Dry staple, Canned drink, Sauce Packet, Lettuce, Mushrooms, Walnuts
- non-food leaks: Beet Kvass Tonic
- duplicates: Organic Greek yogurt, Red pepper paste, Round cheese, Sauce, Honey, Sauce, Jam, Hot Sauce, Lemonade, Herb stew, Flatbread, White cheese, Dill, Chickpeas, Bulgur, Blueberries, Tomatoes, Pomegranate, Sesame seeds, Cucumbers, Garlic, Peanut butter, Condiment bottle, Seasoning, Trader Joe's Organic Ketchup, Snack bag
- out of scope (neutral): 

### Run 1
- hits: black_pot_dish, knik_cheese, brown_jar, brown_eggs, spices, lactose_free_milk, greek_yogurt, hummus, tuna, tomato_stew, soup_pot, red_jam, yellow_item_behind, honey, butter, chopped_salad, white_eggs, garlic_onions, bread, cheese_block, dill, milk_2pct, kvass, flax_seeds, bulgur, figs, orange_food_strainer, avocado, cucumbers, melon, peppercorn_dressing, ketchup, philadelphia, ranch
- misses: sparkling_water, orange_lid_tub, corn, eggplant
- false items: Greens
- non-food leaks: 
- duplicates: Greek yogurt, Sauce, Vinegar, Honey, Condiment, Sauce, Sauce, Pepper sauce, Mushrooms, Pickled peppers, Green soup, Sauce, Shredded cheese, White cheese, Dill, Hummus, Carrots, Cucumbers, Condiment, Blue snack bag, Lactose-free milk
- out of scope (neutral): 

### Run 2
- hits: black_pot_dish, orange_food_strainer, knik_cheese, brown_eggs, spices, brown_jar, greek_yogurt, hummus, tuna, tomato_stew, soup_pot, red_jam, yellow_item_behind, honey, butter, chopped_salad, white_eggs, garlic_onions, cheese_block, bread, corn, sparkling_water, kvass, flax_seeds, avocado, dill, peppercorn_dressing, bulgur, figs, cucumbers, eggplant, ketchup, milk_2pct, philadelphia, ranch, lactose_free_milk
- misses: orange_lid_tub, melon
- false items: condiment, Lettuce
- non-food leaks: 
- duplicates: Stonyfield organic Greek yogurt, cheese wheel, condiment, balsamic glaze, apple sauce, salsa, juice box, condiment, condiment, jam, mustard, pepper sauce, hot sauce, Vegetable stew, Mushrooms, Pickled peppers, Cheese, Pomegranate, White cheese, Dill, Chickpeas, Pomegranate, Carrots, Bulgur, Cucumbers, Peanut butter, Organic ketchup, Snack
- out of scope (neutral): 

### Run 2
- hits: soup_pot, orange_food_strainer, knik_cheese, brown_eggs, spices, brown_jar, greek_yogurt, hummus, tuna, tomato_stew, bulgur, red_jam, yellow_item_behind, honey, butter, chopped_salad, white_eggs, garlic_onions, bread, dill, peppercorn_dressing, kvass, flax_seeds, black_pot_dish, cheese_block, avocado, orange_lid_tub, corn, figs, cucumbers, melon, ketchup, philadelphia, ranch, lactose_free_milk
- misses: sparkling_water, eggplant, milk_2pct
- false items: Green tea, Balsamic glaze, Jarred sauce, Mushrooms
- non-food leaks: 
- duplicates: Organic Greek yogurt, Cheese wheel, Apple sauce, Sauce in small jar, Green boxed item, Jarred condiment, Mustard, Fontana Farms pepper sauce, Cheese block, Pickled peppers, Green soup, Lemonade, Flatbread, Dill, Bulgur, Pomegranate, Cucumbers, Peanut butter, Condiment bottle, Liquid condiment, Trader Joe's organic ketchup, Snack
- out of scope (neutral): 

### Run 2
- hits: soup_pot, knik_cheese, peppercorn_dressing, brown_eggs, brown_jar, hummus, greek_yogurt, tuna, tomato_stew, black_pot_dish, red_jam, butter, honey, orange_lid_tub, chopped_salad, white_eggs, garlic_onions, cheese_block, corn, melon, sparkling_water, yellow_item_behind, kvass, flax_seeds, spices, bread, bulgur, dill, figs, avocado, cucumbers, orange_food_strainer, ketchup, philadelphia, ranch, lactose_free_milk
- misses: eggplant, milk_2pct
- false items: Dry staple, Produce
- non-food leaks: 
- duplicates: Lentil soup, Condiment, Carton, Sauce, Honey, salsa, pickles, jam, Lettuce, Pickled peppers, Lemonade, Green soup, White cheese, Chickpeas, Tomatoes, Melon, Zucchini, Cream bottle, Seasoning, Organic ketchup, Snack bag
- out of scope (neutral): 

### Run 3
- hits: knik_cheese, black_pot_dish, brown_jar, brown_eggs, greek_yogurt, hummus, tuna, tomato_stew, soup_pot, red_jam, honey, yellow_item_behind, butter, chopped_salad, white_eggs, garlic_onions, bread, eggplant, melon, spices, milk_2pct, cheese_block, kvass, flax_seeds, peppercorn_dressing, dill, corn, bulgur, figs, avocado, cucumbers, ketchup, philadelphia, ranch, lactose_free_milk
- misses: sparkling_water, orange_food_strainer, orange_lid_tub
- false items: Dry staple, Pickles, Lettuce, Braised meat, Apple
- non-food leaks: 
- duplicates: Pomegranate juice, Stonyfield Organic Greek Yogurt, Frozen meat, Cheese wheel, Grated cheese, Balsamic glaze, Apple cider vinegar, Red sauce, Condiment, Mustard, Broth, Pepper sauce, Mushrooms, White cheese, Pickled peppers, Green soup, Chickpeas, Melon, Cucumbers, Peanut butter, Sauce, Organic Ketchup, Snack
- out of scope (neutral): 

### Run 3
- hits: black_pot_dish, orange_food_strainer, knik_cheese, brown_eggs, spices, brown_jar, greek_yogurt, hummus, tuna, tomato_stew, soup_pot, red_jam, butter, honey, cheese_block, chopped_salad, white_eggs, garlic_onions, bread, eggplant, lactose_free_milk, yellow_item_behind, kvass, flax_seeds, peppercorn_dressing, dill, bulgur, corn, figs, avocado, cucumbers, melon, ketchup, milk_2pct, philadelphia, ranch
- misses: sparkling_water, orange_lid_tub
- false items: Lettuce
- non-food leaks: 
- duplicates: Greek yogurt, Cheese wheel, Condiment, Broth, Sauce, Pepper sauce, Vegetable stew, Mushrooms, Pickled peppers, Green soup, Hummus, White cheese, Carrots, Cucumbers, Sauce, Organic ketchup, Blue bag snack, Lactose-free reduced fat milk
- out of scope (neutral): 

### Run 3
- hits: black_pot_dish, yellow_item_behind, knik_cheese, brown_eggs, brown_jar, greek_yogurt, hummus, tuna, tomato_stew, soup_pot, red_jam, butter, honey, orange_lid_tub, chopped_salad, white_eggs, figs, bread, cheese_block, dill, peppercorn_dressing, sparkling_water, kvass, spices, flax_seeds, garlic_onions, bulgur, avocado, orange_food_strainer, cucumbers, melon, ketchup, philadelphia, ranch, lactose_free_milk
- misses: corn, eggplant, milk_2pct
- false items: Condiment, Drink can
- non-food leaks: 
- duplicates: Stonyfield Greek yogurt, Honey, sauce, condiment, condiment, condiment, condiment, condiment, sauce packet, Tortillas, Lemonade, Green herb soup, Flatbread, Blueberries, White cheese, Hummus, Fresh dill, Tomatoes, Cucumbers, Condiment bottle, Organic ketchup, Shredded cheese
- out of scope (neutral): 
