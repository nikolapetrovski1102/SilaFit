# Muscle & Strength collection

Collected on 2026-09-14 from the public Muscle & Strength workout, diet-plan,
and recipe catalogs.

| File | Records | Contents |
| --- | ---: | --- |
| `workouts.json` | 6 | The landing page's ordered **Best Workouts** (most downloaded in the prior 24 hours), including descriptions, metadata, days, and exercise tables. |
| `diets.json` | 10 | Every guide linked by the diet catalog, with full text and structured sections. |
| `recipes.json` | 198 | Recipe pages deduplicated across 10 categories and 14 listing pages, with 1,566 ingredient lines, instructions/content, serving guidance, catalog read counts, and published macros. |
| `manifest.json` | 1 | Source, collection time, pacing, discovery counts, and the workout popularity definition. |

Requests were sequential with a random delay of 2.5–5 seconds between source
page loads. No detail-page request failed and every recipe has an ingredient
list.

Four older recipes do not publish all four macro values on their source pages,
so the missing values remain `null`: Home Made Protein and Carbohydrate Bar,
Ground Turkey Omelette, Tuna, Avocado and Tomato, and Kurt Weidner's Saturday
Night Burritos. No values were inferred.

The JSON preserves source URLs for provenance. Review the source site's terms
and content-license requirements before redistributing its text or images.

