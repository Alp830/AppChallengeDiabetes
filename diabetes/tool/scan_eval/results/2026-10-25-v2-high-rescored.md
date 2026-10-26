# Scan eval (re-scored): v2-high

Date: 2026-10-25T17:03:05.094573

Re-scored 6 saved raw outputs against the current answer key. No API calls; the ledger was not touched. Cost is computed from saved token counts.

## Photo: blurry

3/3 runs succeeded. Recall counts only items with visibleInBlurryPhoto=true.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 3/6 (50%) | 11/12 (92%) | n/a | 14/18 (78%) | 2 | 3 | 100% | 35.8s | $0.0508 |
| 2 | 3/6 (50%) | 11/12 (92%) | n/a | 14/18 (78%) | 3 | 0 | 100% | 48.6s | $0.0427 |
| 3 | 3/6 (50%) | 11/12 (92%) | n/a | 14/18 (78%) | 5 | 0 | 100% | 52.2s | $0.0454 |

Median recall: 
- readable 50%, recognizable 92%, hidden n/a, readable+recognizable 78%
- sure precision 100%
- false items 3.0, leaks 0.0
- latency 48.6s, cost $0.0454 per call

Per run details:

### Run 1
- hits: brown_eggs, hummus, orange_lid_tub, butter, tomato_stew, black_pot_dish, brown_jar, honey, chopped_salad, white_eggs, garlic_onions, knik_cheese, red_jam, peppercorn_dressing
- misses: sparkling_water, greek_yogurt, tuna, kvass
- false items: Quaker Oats, Produce in bag
- non-food leaks: Dressing or liquid supplement, Oral Electrolyte or Syrup, Dark bottle
- duplicates: Peanut butter or tahini, Tomato sauce or hot sauce, Blue bagged snack or yeast
- out of scope (neutral): Milk or kefir bottle, Kerrygold butter or cheese, Leafy greens, Mustard or condiment, Avocado saver or lime juice, Condiment bottle

### Run 2
- hits: brown_eggs, hummus, orange_lid_tub, tomato_stew, black_pot_dish, brown_jar, red_jam, butter, chopped_salad, white_eggs, garlic_onions, knik_cheese, peppercorn_dressing, sparkling_water
- misses: greek_yogurt, tuna, kvass, honey
- false items: Whipped Cream, Produce, Guacamole
- non-food leaks: 
- duplicates: Peanut Butter, Tomato Sauce, Snack Pouch
- out of scope (neutral): Milk, Cheese, Mustard, Hot Sauce

### Run 3
- hits: brown_eggs, hummus, orange_lid_tub, tomato_stew, black_pot_dish, brown_jar, red_jam, butter, chopped_salad, white_eggs, garlic_onions, honey, peppercorn_dressing, knik_cheese
- misses: sparkling_water, greek_yogurt, tuna, kvass
- false items: Cinnamon rolls dough, Bagged produce, Lime juice, Electrolyte solution, Dark sauce bottle
- non-food leaks: 
- duplicates: Salsa, Tomato sauce
- out of scope (neutral): Milk, Butter, Orange juice, Hot sauce

## Photo: clear

3/3 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 11/11 (100%) | 14/18 (78%) | 9/9 (100%) | 25/29 (86%) | 4 | 0 | 75% | 84.4s | $0.0945 |
| 2 | 11/11 (100%) | 15/18 (83%) | 8/9 (89%) | 26/29 (90%) | 1 | 2 | 92% | 88.3s | $0.0903 |
| 3 | 11/11 (100%) | 17/18 (94%) | 9/9 (100%) | 28/29 (97%) | 1 | 1 | 83% | 86.6s | $0.0950 |

Median recall: 
- readable 100%, recognizable 83%, hidden 100%, readable+recognizable 90%
- sure precision 83%
- false items 1.0, leaks 1.0
- latency 86.6s, cost $0.0945 per call

Per run details:

### Run 1
- hits: knik_cheese, brown_eggs, brown_jar, cheese_block, greek_yogurt, hummus, tuna, tomato_stew, black_pot_dish, avocado, yellow_item_behind, red_jam, butter, white_eggs, bread, eggplant, spices, soup_pot, orange_lid_tub, dill, bulgur, figs, orange_food_strainer, cucumbers, garlic_onions, honey, philadelphia, kvass, flax_seeds, peppercorn_dressing, ketchup, ranch, lactose_free_milk, milk_2pct
- misses: sparkling_water, chopped_salad, corn, melon
- false items: Roasted Vegetables, Mushrooms, Meat, Artichoke Hearts
- non-food leaks: 
- duplicates: Greek Yogurt, Cheese Wheel, Bread, Pomegranate, Zucchini, Spice Jar, Preserve Jar, Seasoning, Hot Sauce, Broth / Honey, Pepper Sauce, Cream Cheese, Yeast / Powder Packet
- out of scope (neutral): 

### Run 2
- hits: cheese_block, knik_cheese, brown_eggs, brown_jar, hummus, greek_yogurt, tuna, tomato_stew, soup_pot, red_jam, yellow_item_behind, honey, butter, black_pot_dish, white_eggs, bread, eggplant, corn, garlic_onions, dill, bulgur, avocado, orange_food_strainer, cucumbers, spices, sparkling_water, kvass, flax_seeds, peppercorn_dressing, ketchup, philadelphia, ranch, lactose_free_milk, milk_2pct
- misses: orange_lid_tub, chopped_salad, melon, figs
- false items: Pickles or jarred vegetables
- non-food leaks: Pomegranate juice or syrup, Syrup or sauce bottle
- duplicates: Hummus or lentil soup, Sliced cheese or butter, Bagged meat or produce, Cheese wheel or round bread, Cooked soup or greens in pot, Wrapped white cheese or cabbage, Zucchini or cucumber, Condiment or supplement jar, Canned or jarred food, Broth or honey in jar, Fontana Farms Pepper Sauce, Clipped blue snack or cheese bag
- out of scope (neutral): 

### Run 3
- hits: knik_cheese, soup_pot, orange_food_strainer, brown_eggs, greek_yogurt, hummus, tuna, tomato_stew, black_pot_dish, brown_jar, cheese_block, chopped_salad, white_eggs, bread, butter, yellow_item_behind, eggplant, corn, garlic_onions, orange_lid_tub, dill, bulgur, figs, avocado, cucumbers, melon, honey, spices, red_jam, kvass, flax_seeds, peppercorn_dressing, ketchup, philadelphia, ranch, lactose_free_milk, milk_2pct
- misses: sparkling_water
- false items: Pomegranate juice or dark syrup
- non-food leaks: Jarred condiment or supplement
- duplicates: Stonyfield Organic Greek Yogurt, Fruit compote or tomato sauce, Meat or poultry in bag, Green herb stew or soup, Carrots or red peppers, Green boxed bottle or carton, Dark sauce or syrup bottle, Honey or broth in glass jar, Fontana Farms Pepper Sauce, Shredded cheese or snack bag with pink clip
- out of scope (neutral): 
