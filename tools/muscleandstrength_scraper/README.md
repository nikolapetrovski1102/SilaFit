# Muscle & Strength data collector

Collects public content from the three Muscle & Strength catalogs used by
SilaFit:

- every unique workout found across the public workout category pages, including
  women, muscle-building, fat-loss, strength, bodyweight, home, body-part, and
  sports catalogs; the **Best Workouts** rank is retained when a program appears
  there;
- every diet guide linked from the diet-plan catalog, including its complete
  article body;
- recipes found through the recipe categories, including ingredients,
  instructions, serving information, and published macros.

The collector uses a real browser because the site currently puts non-browser
HTTP clients behind a Cloudflare challenge. It sends requests sequentially and
waits a random 12–20 seconds before each network page load and 60–90 seconds
between workout categories. Failed server requests use exponential backoff. A
browser verification page stops the run immediately so it is never hammered by
retries. Successfully loaded HTML is cached locally,
so an interrupted run can resume without requesting those pages again.

## Setup

```bash
cd tools/muscleandstrength_scraper
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/playwright install chromium
```

## Run

From the repository root:

```bash
tools/muscleandstrength_scraper/.venv/bin/python \
  tools/muscleandstrength_scraper/scrape.py
```

Results are written to `data/scraped/muscleandstrength/` as `workouts.json`,
`diets.json`, `recipes.json`, and `manifest.json`. Raw HTML cache files go to
`data/scraped/muscleandstrength/.cache/` and are safe to remove when a fresh
collection is required.

The repository includes a completed 2026-09-14 collection. Running the command
again refreshes the same output format; cached pages are reused unless
`--refresh` is supplied.

Useful options:

```bash
# Visible browser, useful if Cloudflare asks for an interactive check.
python scrape.py --headed

# Small verification run.
python scrape.py --max-workouts 1 --max-diets 1 --max-recipes 3

# Refresh only workouts (existing diet and recipe JSON is retained).
python scrape.py --datasets workouts --headed

# Import only the selected routines and use the CSV Program Name values as titles.
python scrape.py --datasets workouts \
  --workout-checklist /path/to/workout_import_checklist.csv --headed

# Use even more conservative request and category pauses.
python scrape.py --delay-min 20 --delay-max 30 \
  --category-delay-min 120 --category-delay-max 180

# Ignore cached pages and collect them again.
python scrape.py --refresh
```

When Chromium is challenged but the catalog already works in Safari, start the
localhost receiver below and run `safari_collector.js` in Safari's Web Inspector
console on the workout-routines page. It uses Safari's existing session, spaces
requests by 15–25 seconds, waits 90–120 seconds between categories, and stores
resume checkpoints in site-local storage. The bridge parses each detail page
into the same `workouts.json` format.

```bash
tools/muscleandstrength_scraper/.venv/bin/python \
  tools/muscleandstrength_scraper/browser_bridge.py \
  --output-dir data/scraped/muscleandstrength \
  --token silen-safari-import-2026
```

The collector checks `robots.txt` when it is available. If the browser receives
a Cloudflare challenge instead of the file, it logs that the rules could not be
verified and continues with the conservative delay. If the published rules
explicitly disallow one of the requested paths, the collector stops.

## Generate the SQL Server import

After collecting or editing the JSON, regenerate the idempotent database seed:

```bash
python3 tools/muscleandstrength_scraper/generate_sql.py
```

For an intentional one-time replacement that removes every existing workout
split before inserting the selected catalog, generate a separate deployment file:

```bash
python3 tools/muscleandstrength_scraper/generate_sql.py \
  --replace-all-workouts --workouts-only \
  --output /tmp/replace-all-workouts.sql
```

This writes `database/seed/006_ImportMuscleAndStrength.sql`. Apply
`database/schema/036_ImportedContentLibrary.sql` and
`database/schema/040_WorkoutRecommendationMetadata.sql` first. The migrations add
source metadata to workout splits, stores original set/rep prescriptions, adds
normalized recipe ingredients and instructions to the existing meal catalog,
and creates tables for full diet guides and their ordered sections.

The seed uses source URLs as stable keys and can be run repeatedly. Recipes
without published macros keep their raw source values in `SourceMacrosJson` and
use zero in the existing non-null integer macro columns.
