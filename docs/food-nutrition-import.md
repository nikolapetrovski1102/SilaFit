# Food nutrition catalog

`dbo.FoodNutrition` is the app's normalized food-composition catalog. Every
nutrient value is stored per 100 g; `ServingSizeG` is optional source metadata.

The importer merges:

- USDA FoodData Central Foundation, Survey/FNDDS, SR Legacy, and Branded data
- Health Canada's Canadian Nutrient File (CNF)
- the UK's Composition of Foods Integrated Dataset (CoFID)
- Open Food Facts packaged-product data

Rows are unique by source ID and by a conservative SHA-256 content fingerprint.
The fingerprint includes normalized name, brand, barcode, and macro values, so
equivalent generic records can collapse without merging distinct packaged foods.

## Refreshing the catalog

Apply the database first (`database/apply.sh`), then run:

```bash
SILEN_CONNECTION_STRING="Host=localhost;Port=54320;Database=silendb;Username=postgres;Password=<password>" \
  dotnet run --project backend/src/Silen.Tools.ImportFoodNutrition -- \
  --sources=usda,cnf,cofid,off
```

Downloads are cached in `data/import/food-nutrition/` and excluded from Git.
The importer streams compressed USDA/Open Food Facts files, commits every 5,000
valid rows, rejects physically impossible nutrient outliers, and is safe to
rerun. Individual sources can be refreshed with `--sources=cnf` or similar.
USDA families can be narrowed with
`--usda-types=foundation,survey,legacy,branded`.

Branded rows (USDA Branded, Open Food Facts) are filtered on import: all four
macros required, calories consistent with them, Open Food Facts products must
have a brand. Duplicates (same name and same rounded macros) need the whole
table, so they are removed by `dbo.foodnutrition_prune` after an import. It
returns its report as a cursor, so call it inside a transaction:

```sql
BEGIN;
SELECT dbo.foodnutrition_prune(p_dryrun => true);   -- false to delete
FETCH ALL FROM "<unnamed portal 1>";
COMMIT;
```

Search from SQL with:

```sql
BEGIN;
SELECT dbo.foodnutrition_search(p_query => 'egg', p_take => 25);
FETCH ALL FROM "<unnamed portal 1>";
COMMIT;
```

## Licensing and attribution

- USDA FoodData Central: CC0/public domain
- Canadian Nutrient File: Open Government Licence - Canada
- UK CoFID: Open Government Licence v3.0
- Open Food Facts: Open Database Licence (ODbL)

Personal use is allowed. If the merged catalog is redistributed, preserve the
source attribution and review the ODbL share-alike requirements.
