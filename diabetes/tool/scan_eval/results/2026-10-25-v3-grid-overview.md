# Scan eval: v3-grid-overview

Date: 2026-10-25T17:20:50.973008

Ledger total spent: $2.0844 of $4.50

## Photo: clear

3/3 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 11/11 (100%) | 17/18 (94%) | 9/9 (100%) | 28/29 (97%) | 8 | 0 | 79% | 46.7s | $0.1469 |
| 2 | 11/11 (100%) | 17/18 (94%) | 9/9 (100%) | 28/29 (97%) | 8 | 0 | 71% | 73.6s | $0.1437 |
| 3 | 11/11 (100%) | 17/18 (94%) | 9/9 (100%) | 28/29 (97%) | 4 | 1 | 70% | 63.4s | $0.1486 |

Median recall: 
- readable 100%, recognizable 94%, hidden 100%, readable+recognizable 97%
- sure precision 71%
- false items 8.0, leaks 0.0
- latency 63.4s, cost $0.1469 per call

Per run details:

### Run 1
- hits: knik_cheese, brown_eggs, orange_food_strainer, hummus, greek_yogurt, tuna, tomato_stew, soup_pot, avocado, brown_jar, butter, chopped_salad, white_eggs, bread, yellow_item_behind, eggplant, corn, black_pot_dish, orange_lid_tub, dill, bulgur, figs, garlic_onions, cucumbers, cheese_block, spices, honey, sparkling_water, kvass, flax_seeds, peppercorn_dressing, ketchup, philadelphia, ranch, lactose_free_milk, milk_2pct, red_jam
- misses: melon
- false items: Pomegranate juice, Jarred condiment, Condiment, Pantry staple, Produce in bag, Canned drink, Lettuce, Artichokes
- non-food leaks: 
- duplicates: Cooked grains, Sliced cheese, Meat, Carrots, Zucchini, Condiment jar, Sauce bottle, Broth, Pepper sauce, Snack pouch, Cooked dish, Leftovers, Nordex Piknik white cheese, Soft cheese, Butter, Jarred sauce, White mushrooms, Cheese wheel, Seasoning, Canned drink, Organic glaze, Milk, Red sauce, Dark liquid, Condiment, Flax seeds, Cooked vegetable stew, Garlic, Mushrooms, Cheese block, Lemonade, Pita bread, Tomatoes, Hummus, Melon slice, Avocados, Peanut butter, Ketchup, Milk, Packaged snack
- out of scope (neutral): 

### Run 2
- hits: knik_cheese, brown_eggs, butter, greek_yogurt, hummus, tuna, tomato_stew, black_pot_dish, brown_jar, honey, yellow_item_behind, white_eggs, cheese_block, garlic_onions, bread, corn, spices, soup_pot, orange_lid_tub, dill, bulgur, figs, avocado, cucumbers, orange_food_strainer, red_jam, kvass, milk_2pct, ketchup, philadelphia, ranch, lactose_free_milk, peppercorn_dressing, chopped_salad, melon, flax_seeds, eggplant
- misses: sparkling_water
- false items: Pomegranate Juice, Cut vegetables, Dry Ingredient, Condiment, Maple Syrup, Leafy greens, Gardenia condiment, Sauerkraut
- non-food leaks: 
- duplicates: Greek yogurt, Hummus, Jarred condiment, Zucchini, Spice, Condiment, Canned food, Hot sauce, Honey, Pepper sauce, Tahini, Clipped pouch, Reduced fat milk, Nordex Piknik White Cheese, Cooked Meal, Tomato Sauce, Cooked Food, Broth, Condiment, White bottle, Red sauce, Butter, Jarred condiment, Jarred food, Mushrooms, Cheese block, Bread, Hummus, Tomatoes, Melon slice, Peanut butter, Ketchup, Condiment bottle, Frozen peas
- out of scope (neutral): 

### Run 3
- hits: knik_cheese, brown_eggs, yellow_item_behind, brown_jar, hummus, greek_yogurt, tuna, tomato_stew, soup_pot, avocado, red_jam, butter, black_pot_dish, white_eggs, bread, corn, garlic_onions, cheese_block, eggplant, dill, bulgur, figs, cucumbers, melon, spices, kvass, honey, flax_seeds, ketchup, philadelphia, ranch, lactose_free_milk, milk_2pct, chopped_salad, sparkling_water, peppercorn_dressing, orange_food_strainer
- misses: orange_lid_tub
- false items: Mushrooms, Green Drink, Produce in bag, Beverage can
- non-food leaks: Syrup
- duplicates: White Cheese, Sliced Cheese, Cooked Stew, Wrapped Cheese, White Cheese, Lemons, Lavash, Pomegranate, Zucchini, Condiment Jar, Mustard, Seasoning, Sauce, Fontana Farms Pepper Sauce, Tahini, Snack Pouch, Cooked meal, Leftovers, Nordex Piknik White Cheese, Flour, Canned fish, Cooked stew, Dairy spread, Honey, Kirkland Grass-Fed Butter, Garlic bulbs, Leftovers in bag, Cheese wheel, Condiment jar, Jam, salsa, jam, condiment, Cooked vegetable stew, Mushrooms, Cabbage, Jarred condiment, Cooked greens soup, Flatbread, Grains in bag, Blueberries, Jarred sauce, Ketchup, Condiment bottle, Fontana Farms Pepper-Caramel, Hidden Valley Homestyle Ranch, Bagged food, Lactose-Free 2% Milk
- out of scope (neutral): 
