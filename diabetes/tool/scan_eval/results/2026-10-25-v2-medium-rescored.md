# Scan eval (re-scored): v2-medium

Date: 2026-10-25T17:03:11.700337

Re-scored 6 saved raw outputs against the current answer key. No API calls; the ledger was not touched. Cost is computed from saved token counts.

## Photo: blurry

3/3 runs succeeded. Recall counts only items with visibleInBlurryPhoto=true.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 3/6 (50%) | 11/12 (92%) | n/a | 14/18 (78%) | 3 | 0 | 100% | 41.2s | $0.0523 |
| 2 | 3/6 (50%) | 10/12 (83%) | n/a | 13/18 (72%) | 4 | 1 | 100% | 42.6s | $0.0495 |
| 3 | 4/6 (67%) | 10/12 (83%) | n/a | 14/18 (78%) | 8 | 0 | 100% | 45.3s | $0.0513 |

Median recall: 
- readable 50%, recognizable 83%, hidden n/a, readable+recognizable 78%
- sure precision 100%
- false items 4.0, leaks 0.0
- latency 42.6s, cost $0.0513 per call

Per run details:

### Run 1
- hits: sparkling_water, hummus, orange_lid_tub, butter, tomato_stew, black_pot_dish, brown_jar, red_jam, chopped_salad, white_eggs, garlic_onions, honey, peppercorn_dressing, knik_cheese
- misses: greek_yogurt, tuna, brown_eggs, kvass
- false items: Oats, Guacamole, Dark sauce bottle
- non-food leaks: 
- duplicates: Butter, Fresh produce, Cheddar cheese, Cream cheese, Pedialyte, Peanut butter, Tomato sauce
- out of scope (neutral): Eggs, Sliced deli meat, Tortillas, Leafy greens, Hot sauce, Condiment

### Run 2
- hits: brown_eggs, hummus, orange_lid_tub, tomato_stew, black_pot_dish, brown_jar, red_jam, butter, chopped_salad, white_eggs, garlic_onions, knik_cheese, peppercorn_dressing
- misses: sparkling_water, greek_yogurt, tuna, kvass, honey
- false items: Canned Drink or Oats, Guacamole or Lime Juice, Green Superfood Powder or Relish, Dark Bottle Sauce
- non-food leaks: Cooking Oil or Syrup
- duplicates: Bagged Produce, Peanut Butter or Salsa, Tomato Sauce or Salsa, Blue Packaged Snack or Cheese
- out of scope (neutral): Milk or Kefir, Cheese or Butter, Leafy Greens or Vegetables, Mustard or Condiment, Hot Sauce or Ketchup

### Run 3
- hits: brown_eggs, hummus, greek_yogurt, tomato_stew, black_pot_dish, brown_jar, red_jam, butter, chopped_salad, white_eggs, garlic_onions, orange_lid_tub, peppercorn_dressing, knik_cheese
- misses: sparkling_water, tuna, kvass, honey
- false items: Oats, Sparkling cider, Cauliflower, Leafy greens, Aloe vera juice, Relish, Apple cider vinegar, Soy sauce
- non-food leaks: 
- duplicates: Tomato sauce
- out of scope (neutral): Butter, Pickles, Cheese, Avocado saver, Cheddar cheese, Hot sauce, Mustard

## Photo: clear

3/3 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 11/11 (100%) | 16/18 (89%) | 8/9 (89%) | 27/29 (93%) | 3 | 1 | 93% | 69.8s | $0.0851 |
| 2 | 11/11 (100%) | 16/18 (89%) | 9/9 (100%) | 27/29 (93%) | 3 | 0 | 85% | 78.0s | $0.0905 |
| 3 | 11/11 (100%) | 15/18 (83%) | 8/9 (89%) | 26/29 (90%) | 1 | 3 | 86% | 84.8s | $0.0987 |

Median recall: 
- readable 100%, recognizable 89%, hidden 89%, readable+recognizable 93%
- sure precision 86%
- false items 3.0, leaks 1.0
- latency 78.0s, cost $0.0905 per call

Per run details:

### Run 1
- hits: knik_cheese, brown_eggs, hummus, greek_yogurt, tuna, tomato_stew, black_pot_dish, brown_jar, red_jam, yellow_item_behind, butter, white_eggs, garlic_onions, bread, cheese_block, eggplant, corn, soup_pot, orange_lid_tub, dill, bulgur, avocado, cucumbers, orange_food_strainer, melon, spices, kvass, honey, flax_seeds, peppercorn_dressing, ketchup, philadelphia, ranch, lactose_free_milk, milk_2pct
- misses: sparkling_water, chopped_salad, figs
- false items: Cut vegetables or meat, Pickles or condiment jar, Canned drink or starter
- non-food leaks: Dark juice or syrup
- duplicates: Lentil soup or hummus, Sliced cheese, Packaged meat or fish, Sauce or syrup bottle, Hot Pepper Sauce, Blue snack or cheese bag
- out of scope (neutral): 

### Run 2
- hits: orange_food_strainer, knik_cheese, brown_eggs, milk_2pct, bulgur, hummus, greek_yogurt, tuna, tomato_stew, soup_pot, yellow_item_behind, brown_jar, butter, white_eggs, garlic_onions, bread, cheese_block, eggplant, black_pot_dish, corn, peppercorn_dressing, orange_lid_tub, dill, figs, avocado, melon, cucumbers, spices, red_jam, kvass, honey, flax_seeds, ketchup, philadelphia, ranch, lactose_free_milk
- misses: sparkling_water, chopped_salad
- false items: Pomegranate juice, Cut vegetables, Beverage can
- non-food leaks: 
- duplicates: Berry jam, Sliced cheese, Flatbread, Shredded cheese, Carrots, Canned condiment, Hot sauce, Fontana Farms Pepper Sauce, Tahini, Snack pouch, 2% Reduced Fat Milk
- out of scope (neutral): 

### Run 3
- hits: knik_cheese, cheese_block, brown_eggs, greek_yogurt, bulgur, hummus, tuna, tomato_stew, soup_pot, red_jam, yellow_item_behind, honey, butter, black_pot_dish, white_eggs, bread, garlic_onions, eggplant, spices, peppercorn_dressing, orange_lid_tub, dill, brown_jar, avocado, orange_food_strainer, cucumbers, sparkling_water, kvass, flax_seeds, ketchup, philadelphia, ranch, lactose_free_milk, milk_2pct
- misses: chopped_salad, corn, melon, figs
- false items: Sausage or Cured Meat
- non-food leaks: Pomegranate Juice or Syrup, Sauce or Medicine Bottle, Hot Sauce or Syrup
- duplicates: Organic Greek Yogurt, Cheese Wheel or Hummus, Deli Meat or Cheese, Cooked Greens or Soup in Pot, Bread or Baked Goods, Shredded Cheese or Almond Flour, Butter or Cheese Block, Cabbage or Cauliflower, Mustard or Turmeric Paste, Condiment Jar, Honey, Fontana Farms Pepper Sauce, Tahini or Nut Butter, Snack or Frozen Fruit Bag
- out of scope (neutral): 
