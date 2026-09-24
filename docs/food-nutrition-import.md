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

Apply the database scripts first, then run:

```bash
SILEN_CONNECTION_STRING="Server=localhost,14330;Database=SilenDb;User Id=sa;Password=<password>;TrustServerCertificate=True;" \
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
table, so they are removed by `dbo.FoodNutrition_Prune` - check with
`EXEC dbo.FoodNutrition_Prune @DryRun = 1;` and apply with
`database/manual-migrations/027_FoodNutritionPrune.sql` after an import.

Search from SQL with:

```sql
EXEC dbo.FoodNutrition_Search @Query = N'egg', @Take = 25;
```

## Licensing and attribution

- USDA FoodData Central: CC0/public domain
- Canadian Nutrient File: Open Government Licence - Canada
- UK CoFID: Open Government Licence v3.0
- Open Food Facts: Open Database Licence (ODbL)

Personal use is allowed. If the merged catalog is redistributed, preserve the
source attribution and review the ODbL share-alike requirements.
