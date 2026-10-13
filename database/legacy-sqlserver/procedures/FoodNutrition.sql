USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- @Query is expected pre-normalized by the caller (FoodService applies the
-- same lower-case/punctuation folding the importer used for NormalizedName);
-- the LOWER/TRIM here is only a safety net for direct callers.
-- @UserId scopes user-added foods (CreatedByUserId, 066_FoodTracking.sql):
-- the caller sees the shared catalog plus only their own additions.
-- Ranking: the caller's own foods, then generic reference foods, then
-- branded products collapsed to one row per name and brand (067).
CREATE OR ALTER PROCEDURE dbo.FoodNutrition_Search
    @Query  NVARCHAR(200),
    @Take   INT = 25,
    @UserId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Query = LOWER(LTRIM(RTRIM(ISNULL(@Query, N''))));
    SET @Query = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
        @Query, N',', N' '), N'.', N' '), N'-', N' '), N'/', N' '), N'(', N' '), N')', N' '), N'  ', N' ');
    WHILE CHARINDEX(N'  ', @Query) > 0 SET @Query = REPLACE(@Query, N'  ', N' ');
    SET @Take = CASE WHEN @Take BETWEEN 1 AND 100 THEN @Take ELSE 25 END;

    DECLARE @Matches TABLE
    (
        ResultOrder INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        FoodNutritionId BIGINT NOT NULL UNIQUE
    );

    IF @Query NOT LIKE N'%[^0-9]%'
    BEGIN
        INSERT @Matches (FoodNutritionId)
        SELECT TOP (@Take) FoodNutritionId
        FROM dbo.FoodNutrition WITH (FORCESEEK, INDEX(IX_FoodNutrition_Barcode))
        WHERE Barcode = @Query
          AND (CreatedByUserId IS NULL OR CreatedByUserId = @UserId)
        ORDER BY CASE SourceName
            WHEN N'USDA Foundation' THEN 0 WHEN N'USDA Survey' THEN 1
            WHEN N'CNF' THEN 2 WHEN N'CoFID' THEN 3 WHEN N'USDA Legacy' THEN 4
            WHEN N'USDA Branded' THEN 5 WHEN N'Open Food Facts' THEN 6 ELSE 7 END,
            FoodNutritionId
        OPTION (RECOMPILE);
    END
    ELSE IF LEN(@Query) >= 2
    BEGIN
        DECLARE @Escaped NVARCHAR(400) = REPLACE(REPLACE(REPLACE(REPLACE(
            @Query, N'\', N'\\'), N'%', N'\%'), N'_', N'\_'), N'[', N'\[');
        DECLARE @Prefix NVARCHAR(406) = @Escaped + N'%';
        -- "Egg, whole, raw": USDA/CNF/CoFID name the plain food as the query
        -- followed by a comma, while "Egg burrito" is a dish that contains it.
        -- The plural counts too: "oat" should find "Oats, rolled".
        DECLARE @PrimaryPrefix NVARCHAR(406) = @Escaped + N',%';
        DECLARE @PluralPrimaryPrefix NVARCHAR(407) = @Escaped + N's,%';
        -- Compute the next lexical prefix ("egg" -> "egh"). Appending a
        -- maximal Unicode character looks intuitive but spans most of a
        -- linguistic collation and still reads thousands of pages.
        DECLARE @LastCodePoint INT = UNICODE(RIGHT(@Query, 1));
        DECLARE @UpperBound NVARCHAR(200) = CASE
            WHEN @LastCodePoint < 65535
                THEN LEFT(@Query, LEN(@Query) - 1) + NCHAR(@LastCodePoint + 1)
            ELSE @Query + NCHAR(65535)
        END;
        DECLARE @Remaining INT;

        -- 1. The caller's own foods, exact name then prefix.
        IF @UserId IS NOT NULL
        BEGIN
            INSERT @Matches (FoodNutritionId)
            SELECT TOP (@Take) FoodNutritionId
            FROM dbo.FoodNutrition WITH (FORCESEEK, INDEX(IX_FoodNutrition_CreatedByUserId))
            WHERE CreatedByUserId = @UserId
              AND NormalizedName >= @Query AND NormalizedName < @UpperBound
              AND NormalizedName LIKE @Prefix ESCAPE N'\'
            ORDER BY CASE WHEN NormalizedName = @Query THEN 0 ELSE 1 END,
                NormalizedName, LEN(Name), FoodNutritionId
            OPTION (RECOMPILE);
        END

        -- 2. Generic reference foods (IX_FoodNutrition_Generic, ~1% of the
        -- catalog, so reading the whole prefix range to rank it is cheap),
        -- one row per name from the best source: the exact name and the
        -- "<query>, ..." plain food. Dishes that merely start with the query
        -- ("Nutella sandwich") wait until after exact branded matches.
        SET @Remaining = @Take - (SELECT COUNT(*) FROM @Matches);
        IF @Remaining > 0
        BEGIN
            INSERT @Matches (FoodNutritionId)
            SELECT TOP (@Remaining) ranked.FoodNutritionId
            FROM
            (
                SELECT FoodNutritionId, NameLength = LEN(Name),
                    Tier = CASE WHEN NormalizedName = @Query THEN 0
                                WHEN Name LIKE @PrimaryPrefix ESCAPE N'\'
                                  OR Name LIKE @PluralPrimaryPrefix ESCAPE N'\' THEN 1
                                ELSE 2 END,
                    ROW_NUMBER() OVER (
                        PARTITION BY NormalizedName
                        ORDER BY CASE SourceName
                            WHEN N'USDA Foundation' THEN 0 WHEN N'USDA Survey' THEN 1
                            WHEN N'CNF' THEN 2 WHEN N'CoFID' THEN 3 ELSE 4 END,
                            FoodNutritionId) AS NameRank
                FROM dbo.FoodNutrition WITH (FORCESEEK, INDEX(IX_FoodNutrition_Generic))
                WHERE SourceName IN (N'USDA Foundation', N'USDA Survey', N'CNF', N'CoFID', N'USDA Legacy')
                  AND NormalizedName >= @Query AND NormalizedName < @UpperBound
                  AND NormalizedName LIKE @Prefix ESCAPE N'\'
            ) ranked
            WHERE ranked.NameRank = 1 AND ranked.Tier < 2
            ORDER BY ranked.Tier, ranked.NameLength, ranked.FoodNutritionId
            OPTION (RECOMPILE);
        END

        -- 3. Branded products, one row per (name, brand): Open Food Facts and
        -- USDA Branded carry the same product many times over, and dozens of
        -- brands sell something named just "Egg". Exact name here, prefix in
        -- step 5 - kept as two seeks so the prefix read stops early in index
        -- order instead of sorting the whole range.
        SET @Remaining = @Take - (SELECT COUNT(*) FROM @Matches);
        IF @Remaining > 0
        BEGIN
            INSERT @Matches (FoodNutritionId)
            SELECT TOP (@Remaining) ranked.FoodNutritionId
            FROM
            (
                SELECT FoodNutritionId, SourceName, NameLength = LEN(Name),
                    ROW_NUMBER() OVER (
                        PARTITION BY LOWER(ISNULL(BrandName, N''))
                        ORDER BY CASE SourceName WHEN N'USDA Branded' THEN 0 ELSE 1 END, FoodNutritionId) AS BrandRank
                FROM dbo.FoodNutrition WITH (FORCESEEK, INDEX(IX_FoodNutrition_SearchV4))
                WHERE NormalizedName = @Query
                  AND SourceName IN (N'USDA Branded', N'Open Food Facts')
                  AND CreatedByUserId IS NULL
            ) ranked
            WHERE ranked.BrandRank = 1
            ORDER BY CASE ranked.SourceName WHEN N'USDA Branded' THEN 0 ELSE 1 END,
                ranked.NameLength, ranked.FoodNutritionId
            OPTION (RECOMPILE);
        END

        -- 4. Generic dishes that start with the query.
        SET @Remaining = @Take - (SELECT COUNT(*) FROM @Matches);
        IF @Remaining > 0
        BEGIN
            INSERT @Matches (FoodNutritionId)
            SELECT TOP (@Remaining) ranked.FoodNutritionId
            FROM
            (
                SELECT FoodNutritionId, NameLength = LEN(Name),
                    Tier = CASE WHEN NormalizedName = @Query THEN 0
                                WHEN Name LIKE @PrimaryPrefix ESCAPE N'\'
                                  OR Name LIKE @PluralPrimaryPrefix ESCAPE N'\' THEN 1
                                ELSE 2 END,
                    ROW_NUMBER() OVER (
                        PARTITION BY NormalizedName
                        ORDER BY CASE SourceName
                            WHEN N'USDA Foundation' THEN 0 WHEN N'USDA Survey' THEN 1
                            WHEN N'CNF' THEN 2 WHEN N'CoFID' THEN 3 ELSE 4 END,
                            FoodNutritionId) AS NameRank
                FROM dbo.FoodNutrition WITH (FORCESEEK, INDEX(IX_FoodNutrition_Generic))
                WHERE SourceName IN (N'USDA Foundation', N'USDA Survey', N'CNF', N'CoFID', N'USDA Legacy')
                  AND NormalizedName >= @Query AND NormalizedName < @UpperBound
                  AND NormalizedName LIKE @Prefix ESCAPE N'\'
            ) ranked
            WHERE ranked.NameRank = 1 AND ranked.Tier = 2
            ORDER BY ranked.Tier, ranked.NameLength, ranked.FoodNutritionId
            OPTION (RECOMPILE);
        END

        -- 5. Branded products by prefix.
        SET @Remaining = @Take - (SELECT COUNT(*) FROM @Matches);
        IF @Remaining > 0
        BEGIN
            -- Over-read in index order, then collapse duplicates.
            DECLARE @Candidates INT = @Remaining * 4;

            INSERT @Matches (FoodNutritionId)
            SELECT TOP (@Remaining) ranked.FoodNutritionId
            FROM
            (
                SELECT candidate.FoodNutritionId, candidate.NormalizedName,
                    ROW_NUMBER() OVER (
                        PARTITION BY candidate.NormalizedName, LOWER(ISNULL(candidate.BrandName, N''))
                        ORDER BY CASE candidate.SourceName WHEN N'USDA Branded' THEN 0 ELSE 1 END,
                            candidate.FoodNutritionId) AS BrandRank
                FROM
                (
                    SELECT TOP (@Candidates) FoodNutritionId, NormalizedName, BrandName, SourceName
                    FROM dbo.FoodNutrition WITH (FORCESEEK, INDEX(IX_FoodNutrition_SearchV4))
                    WHERE NormalizedName >= @Query AND NormalizedName < @UpperBound
                      AND NormalizedName LIKE @Prefix ESCAPE N'\'
                      AND NormalizedName <> @Query
                      AND SourceName IN (N'USDA Branded', N'Open Food Facts')
                      AND CreatedByUserId IS NULL
                    ORDER BY NormalizedName, FoodNutritionId
                ) candidate
            ) ranked
            WHERE ranked.BrandRank = 1
            ORDER BY ranked.NormalizedName, ranked.FoodNutritionId
            OPTION (RECOMPILE);
        END
    END

    SELECT
        food.FoodNutritionId,
        food.Name,
        food.BrandName,
        food.Barcode,
        food.SourceName,
        food.ServingSizeG,
        food.CaloriesKcal,
        food.ProteinG,
        food.CarbohydrateG,
        food.FatG,
        food.FiberG,
        food.SugarG,
        food.SodiumMg,
        CAST(CASE WHEN food.CreatedByUserId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsCustom
    FROM @Matches matches
    INNER JOIN dbo.FoodNutrition food WITH (FORCESEEK, INDEX(PK_FoodNutrition))
        ON food.FoodNutritionId = matches.FoodNutritionId
    ORDER BY matches.ResultOrder;
END
GO

-- A food the user couldn't find in the catalog, added from the meal tracker.
-- Nutrients are per 100 g like every other row. @ContentHash is computed by
-- FoodService from the new SourceFoodId so it can never collide with
-- (or be deduplicated into) a catalog row or another user's food.
CREATE OR ALTER PROCEDURE dbo.FoodNutrition_CreateCustom
    @UserId         UNIQUEIDENTIFIER,
    @Name           NVARCHAR(500),
    @NormalizedName NVARCHAR(500),
    @BrandName      NVARCHAR(300) = NULL,
    @ServingSizeG   DECIMAL(12,3) = NULL,
    @CaloriesKcal   DECIMAL(12,3),
    @ProteinG       DECIMAL(12,3),
    @CarbohydrateG  DECIMAL(12,3),
    @FatG           DECIMAL(12,3),
    @FiberG         DECIMAL(12,3) = NULL,
    @SugarG         DECIMAL(12,3) = NULL,
    @SodiumMg       DECIMAL(12,3) = NULL,
    @SourceFoodId   NVARCHAR(120),
    @ContentHash    BINARY(32)
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.FoodNutrition
        (Name, NormalizedName, BrandName, SourceName, SourceFoodId, ServingSizeG,
         CaloriesKcal, ProteinG, CarbohydrateG, FatG, FiberG, SugarG, SodiumMg,
         IsBranded, ContentHash, CreatedByUserId)
    VALUES
        (@Name, @NormalizedName, @BrandName, N'User', @SourceFoodId, @ServingSizeG,
         @CaloriesKcal, @ProteinG, @CarbohydrateG, @FatG, @FiberG, @SugarG, @SodiumMg,
         CASE WHEN @BrandName IS NULL THEN 0 ELSE 1 END, @ContentHash, @UserId);

    SELECT
        FoodNutritionId,
        Name,
        BrandName,
        Barcode,
        SourceName,
        ServingSizeG,
        CaloriesKcal,
        ProteinG,
        CarbohydrateG,
        FatG,
        FiberG,
        SugarG,
        SodiumMg,
        CAST(1 AS BIT) AS IsCustom
    FROM dbo.FoodNutrition
    WHERE FoodNutritionId = SCOPE_IDENTITY();
END
GO

-- Removes branded catalog rows that add noise without adding a food:
-- incomplete, physically implausible, unidentifiable, or a duplicate of a
-- row already kept. Generic reference sources and user-created foods are
-- never touched. Meal logs snapshot their macros (MealLogs.Items), so no
-- logged meal changes when a catalog row goes.
--
-- Runs at the end of every Silen.Tools.ImportFoodNutrition run (the MERGE
-- there re-inserts rows this deleted, so the rules have to re-apply); the
-- importer also skips the per-row cases up front (FoodNutritionRow.IsCatalogQuality)
-- - keep the two in step. @DryRun = 1 only reports what would go.
-- Deletes run in small autocommitted batches so the log never has to hold
-- a multi-million-row transaction.
CREATE OR ALTER PROCEDURE dbo.FoodNutrition_Prune
    @DryRun    BIT = 1,
    @BatchSize INT = 20000
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #Doomed
    (
        FoodNutritionId BIGINT  NOT NULL PRIMARY KEY,
        Reason          TINYINT NOT NULL
    );

    -- 1-4: per-row rules, branded sources only.
    INSERT #Doomed (FoodNutritionId, Reason)
    SELECT FoodNutritionId,
        CASE
            -- 1. Can't be tracked without all four headline values.
            WHEN CaloriesKcal IS NULL OR ProteinG IS NULL OR CarbohydrateG IS NULL OR FatG IS NULL THEN 1
            -- 2. Energy the macros can't account for. Below the macros:
            -- sugar-free (polyol) and high-fibre products legitimately land
            -- well under 4 kcal/g of carbs, so only under half is an error
            -- ("condensed milk, 3 kcal"). Above them is allowed up to
            -- ~300 kcal, which alcohol (7 kcal/g, spirits) explains - beyond
            -- that it's usually kJ typed as kcal.
            WHEN Atwater - CaloriesKcal > 50 AND CaloriesKcal < 0.5 * Atwater THEN 2
            WHEN CaloriesKcal - Atwater > 300 THEN 2
            -- 3. An Open Food Facts product with no brand can't be told
            -- apart from the dozens of same-named rows around it.
            WHEN SourceName = N'Open Food Facts' AND NULLIF(LTRIM(RTRIM(BrandName)), N'') IS NULL THEN 3
            -- 4. Name is only digits (usually a barcode typed into the name).
            WHEN NormalizedName NOT LIKE N'%[^0-9 ]%' THEN 4
        END
    FROM
    (
        SELECT FoodNutritionId, SourceName, BrandName, NormalizedName, CaloriesKcal,
               ProteinG, CarbohydrateG, FatG,
               Atwater = 4 * ProteinG + 4 * CarbohydrateG + 9 * FatG
        FROM dbo.FoodNutrition
        WHERE SourceName IN (N'USDA Branded', N'Open Food Facts')
          AND CreatedByUserId IS NULL
    ) branded
    WHERE CaloriesKcal IS NULL OR ProteinG IS NULL OR CarbohydrateG IS NULL OR FatG IS NULL
       OR (Atwater - CaloriesKcal > 50 AND CaloriesKcal < 0.5 * Atwater)
       OR CaloriesKcal - Atwater > 300
       OR (SourceName = N'Open Food Facts' AND NULLIF(LTRIM(RTRIM(BrandName)), N'') IS NULL)
       OR NormalizedName NOT LIKE N'%[^0-9 ]%';

    -- 5. Duplicates: the same name with the same macros (to the gram/kcal)
    -- is the same food to someone logging it, whatever the brand spelling or
    -- pack size. Generic rows win, then USDA Branded, then the oldest row;
    -- only branded losers are removed.
    INSERT #Doomed (FoodNutritionId, Reason)
    SELECT ranked.FoodNutritionId, 5
    FROM
    (
        SELECT food.FoodNutritionId, food.SourceName,
            ROW_NUMBER() OVER (
                PARTITION BY food.NormalizedName, ROUND(food.CaloriesKcal, 0), ROUND(food.ProteinG, 0),
                             ROUND(food.CarbohydrateG, 0), ROUND(food.FatG, 0)
                ORDER BY CASE food.SourceName
                    WHEN N'USDA Foundation' THEN 0 WHEN N'USDA Survey' THEN 1
                    WHEN N'CNF' THEN 2 WHEN N'CoFID' THEN 3 WHEN N'USDA Legacy' THEN 4
                    WHEN N'USDA Branded' THEN 5 ELSE 6 END,
                    food.FoodNutritionId) AS DuplicateRank
        FROM dbo.FoodNutrition food
        WHERE food.CreatedByUserId IS NULL
          AND food.CaloriesKcal IS NOT NULL AND food.ProteinG IS NOT NULL
          AND food.CarbohydrateG IS NOT NULL AND food.FatG IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM #Doomed doomed WHERE doomed.FoodNutritionId = food.FoodNutritionId)
    ) ranked
    WHERE ranked.DuplicateRank > 1
      AND ranked.SourceName IN (N'USDA Branded', N'Open Food Facts');

    SELECT
        CASE Reason
            WHEN 1 THEN N'Missing calories/protein/carbs/fat'
            WHEN 2 THEN N'Calories inconsistent with macros'
            WHEN 3 THEN N'Open Food Facts product without a brand'
            WHEN 4 THEN N'Name is only digits'
            WHEN 5 THEN N'Duplicate name + macros'
        END AS Reason,
        COUNT_BIG(*) AS RowsRemoved
    FROM #Doomed
    GROUP BY Reason
    ORDER BY Reason;

    IF @DryRun = 1 RETURN;

    DECLARE @Batch TABLE (FoodNutritionId BIGINT NOT NULL PRIMARY KEY);
    WHILE 1 = 1
    BEGIN
        DELETE @Batch;
        DELETE TOP (@BatchSize) FROM #Doomed OUTPUT deleted.FoodNutritionId INTO @Batch;
        IF @@ROWCOUNT = 0 BREAK;

        DELETE food
        FROM dbo.FoodNutrition food
        INNER JOIN @Batch batch ON batch.FoodNutritionId = food.FoodNutritionId
        WHERE food.CreatedByUserId IS NULL;
    END
END
GO
