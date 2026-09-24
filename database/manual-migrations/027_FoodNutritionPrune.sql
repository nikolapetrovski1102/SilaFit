USE SilenDb;
GO

-- Required for the rebuild below: dbo.FoodNutrition has filtered indexes and
-- sqlcmd connects with QUOTED_IDENTIFIER OFF (Msg 1934 without these).
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- One-time cleanup of the branded food catalog (see dbo.FoodNutrition_Prune
-- in procedures/FoodNutrition.sql for the rules). Deletes roughly 960k of
-- ~2.68M rows on a full import: Open Food Facts products without a brand,
-- rows missing a macro, calories the macros can't explain, digit-only
-- names, and same-name/same-macros duplicates. Generic reference foods and
-- user-created foods are never touched; logged meals keep their snapshot.
--
-- Run the dry run first and check the counts:
--   EXEC dbo.FoodNutrition_Prune @DryRun = 1;
-- Take a backup, then run this file. Expect several minutes.

EXEC dbo.FoodNutrition_Prune @DryRun = 0;
GO

-- Deleting leaves the freed pages inside the data file. Rebuilding compacts
-- the table and its indexes; shrinking afterwards hands the space back to
-- the OS. Shrink before a final rebuild would fragment the indexes again,
-- so the order is rebuild -> shrink -> reorganize.
ALTER INDEX ALL ON dbo.FoodNutrition REBUILD WITH (SORT_IN_TEMPDB = ON, MAXDOP = 2);
GO

-- File 1 is the primary data file.
DBCC SHRINKFILE (1);
GO

ALTER INDEX ALL ON dbo.FoodNutrition REORGANIZE;
GO
