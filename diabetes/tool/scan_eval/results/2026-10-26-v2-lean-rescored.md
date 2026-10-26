# Scan eval (re-scored): v2-lean

Date: 2026-10-26T00:02:39.750198

Re-scored 4 saved raw outputs against the current answer key. No API calls; the ledger was not touched. Cost is computed from saved token counts.

## Photo: freezer

1/1 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 6/6 (100%) | 4/6 (67%) | n/a | 10/12 (83%) | 0 | 0 | 80% | 15.8s | $0.0183 |

Median recall: 
- readable 100%, recognizable 67%, hidden n/a, readable+recognizable 83%
- sure precision 80%
- false items 0.0, leaks 0.0
- latency 15.8s, cost $0.0183 per call

Per run details:

### Run 1
- hits: freezer_montana, freezer_frozen_berries_bag, freezer_meat_packs, freezer_cevapi, freezer_strawberries, freezer_manti, freezer_tortillas, freezer_peas_corn, freezer_vegetables_dark_bag, freezer_molokhia
- misses: freezer_bread_rolls, freezer_pasta_bag
- false items: 
- non-food leaks: 
- duplicates: Frozen dough balls, Homemade manti, Puff pastry, Ezekiel tortillas, Frozen corn, Frozen waffles, Frozen berries
- out of scope (neutral): 

## Photo: pantry_wide

1/1 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 7/9 (78%) | 9/15 (60%) | n/a | 16/24 (67%) | 1 | 0 | 100% | 17.3s | $0.0208 |

Median recall: 
- readable 78%, recognizable 60%, hidden n/a, readable+recognizable 67%
- sure precision 100%
- false items 1.0, leaks 0.0
- latency 17.3s, cost $0.0208 per call

Per run details:

### Run 1
- hits: pantry_avocados, pantry_herbs, pantry_lemons, pantry_almonds, pantry_mandarins, pantry_tomatoes, pantry_potatoes, pantry_gullac, pantry_fruit_strips, pantry_fruit_bites, pantry_garlic, pantry_kabocha, pantry_walnuts, pantry_spices, pantry_bread, pantry_crackers
- misses: pantry_butternut, pantry_juice_box, pantry_tea, pantry_coffee, pantry_dates, pantry_turkish_delight, pantry_seasoning, pantry_nut_butter
- false items: Canned Food
- non-food leaks: 
- duplicates: Onions, Tomato Paste
- out of scope (neutral): 

## Photo: pantry_counter

1/1 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 5/5 (100%) | 3/5 (60%) | n/a | 8/10 (80%) | 1 | 0 | 86% | 13.3s | $0.0123 |

Median recall: 
- readable 100%, recognizable 60%, hidden n/a, readable+recognizable 80%
- sure precision 86%
- false items 1.0, leaks 0.0
- latency 13.3s, cost $0.0123 per call

Per run details:

### Run 1
- hits: pantry_herbs, pantry_avocados, pantry_lemons, pantry_almonds, pantry_mandarins, pantry_tomatoes, pantry_fruit_strips, pantry_watermelon
- misses: pantry_potatoes, pantry_tea
- false items: Gazi Güllaç pastry sheets
- non-food leaks: 
- duplicates: 
- out of scope (neutral): 

## Photo: bottles

1/1 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2/2 (100%) | 2/2 (100%) | n/a | 4/4 (100%) | 0 | 0 | 100% | 6.1s | $0.0083 |

Median recall: 
- readable 100%, recognizable 100%, hidden n/a, readable+recognizable 100%
- sure precision 100%
- false items 0.0, leaks 0.0
- latency 6.1s, cost $0.0083 per call

Per run details:

### Run 1
- hits: bottles_olive_oil, bottles_soy_sauce, bottles_dark_sauce, bottles_acv
- misses: 
- false items: 
- non-food leaks: 
- duplicates: 
- out of scope (neutral): 
