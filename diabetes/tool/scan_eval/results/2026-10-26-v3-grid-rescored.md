# Scan eval (re-scored): v3-grid

Date: 2026-10-26T00:03:10.758889

Re-scored 3 saved raw outputs against the current answer key. No API calls; the ledger was not touched. Cost is computed from saved token counts.

## Photo: pantry_wide

1/1 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 8/9 (89%) | 12/15 (80%) | n/a | 20/24 (83%) | 1 | 0 | 85% | 19.1s | $0.0539 |

Median recall: 
- readable 89%, recognizable 80%, hidden n/a, readable+recognizable 83%
- sure precision 85%
- false items 1.0, leaks 0.0
- latency 19.1s, cost $0.0539 per call

Per run details:

### Run 1
- hits: pantry_herbs, pantry_avocados, pantry_lemons, pantry_almonds, pantry_mandarins, pantry_potatoes, pantry_tomatoes, pantry_turkish_delight, pantry_gullac, pantry_fruit_bites, pantry_fruit_strips, pantry_coffee, pantry_crackers, pantry_spices, pantry_butternut, pantry_kabocha, pantry_tea, pantry_bread, pantry_seasoning, pantry_walnuts
- misses: pantry_juice_box, pantry_dates, pantry_garlic, pantry_nut_butter
- false items: Jam
- non-food leaks: 
- duplicates: Onions, Potatoes, Kurukahveci Mehmet Efendi Pouch, Black box
- out of scope (neutral): 

## Photo: pantry_counter

1/1 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 5/5 (100%) | 4/5 (80%) | n/a | 9/10 (90%) | 3 | 0 | 86% | 14.1s | $0.0384 |

Median recall: 
- readable 100%, recognizable 80%, hidden n/a, readable+recognizable 90%
- sure precision 86%
- false items 3.0, leaks 0.0
- latency 14.1s, cost $0.0384 per call

Per run details:

### Run 1
- hits: pantry_herbs, pantry_avocados, pantry_lemons, pantry_almonds, pantry_mandarins, pantry_tomatoes, pantry_watermelon, pantry_fruit_strips, pantry_tea
- misses: pantry_potatoes
- false items: garlic bulbs, gullac, packaged food
- non-food leaks: 
- duplicates: cherry tomatoes
- out of scope (neutral): 

## Photo: bottles

1/1 runs succeeded.

| run | readable | recognizable | hidden | read+recog | false | leaks | sure precision | latency | cost |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2/2 (100%) | 1/2 (50%) | n/a | 3/4 (75%) | 0 | 0 | 100% | 9.9s | $0.0322 |

Median recall: 
- readable 100%, recognizable 50%, hidden n/a, readable+recognizable 75%
- sure precision 100%
- false items 0.0, leaks 0.0
- latency 9.9s, cost $0.0322 per call

Per run details:

### Run 1
- hits: bottles_olive_oil, bottles_soy_sauce, bottles_acv
- misses: bottles_dark_sauce
- false items: 
- non-food leaks: 
- duplicates: Pomegranate molasses, Olive oil
- out of scope (neutral): 
