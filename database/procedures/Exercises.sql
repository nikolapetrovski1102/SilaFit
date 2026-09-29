USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Search values are always bound parameters (never concatenated into the
-- command text), so the LIKE usage below carries no injection risk.
-- @MuscleGroups is a comma-separated list of the catalogue's coarse muscle
-- groups (chest/back/legs/shoulders/arms/core). STRING_SPLIT keeps the filter
-- set-based, so one round trip can scope a search or a suggestion read to every
-- group a day's title points at (e.g. "Chest & Triceps" -> chest,arms).
--
-- @SearchTermsJson is the typed search already broken into keyword groups by
-- the API (ExerciseSearchTerms): [{"g":0,"t":"shoulder"},{"g":0,"t":"delt"},
-- {"g":1,"t":"fly"}] - one row per spelling, g = the typed word it stands for.
-- A word counts as matched when any of its spellings is in the name (or the
-- name with spaces/hyphens removed, so "pullup" finds "Pull-Up"), the muscle
-- group or the equipment. Exercises must hit at least half the words, one of
-- them in the name, and rank by words hit, then the whole typed phrase, then
-- name hits, then the shortest (most canonical) name - so "shoulder fly" finds
-- "Shoulder Cable Flys" first, followed by the other shoulder flys.
-- With no keywords (the suggestion reads, or a search of only filler words)
-- it falls back to the plain substring match on @SearchText.
--
-- @UserId adds that user's own exercises (CreatedByUserId, 071) to the shared
-- catalogue; NULL - the suggestion list and the weekly plan generator - reads
-- the catalogue alone. IsCustom tells the picker which rows are the user's.
-- TOP caps an anonymous, unbounded-in-principle search over the exercise catalogue.
CREATE OR ALTER PROCEDURE dbo.usp_Exercises_Search
    @MuscleGroups NVARCHAR(200) = NULL,
    @SearchText NVARCHAR(150) = NULL,
    @SearchTermsJson NVARCHAR(MAX) = NULL,
    @UserId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Phrase NVARCHAR(150) = NULLIF(LTRIM(RTRIM(@SearchText)), N'');

    DECLARE @Terms TABLE (GroupIndex INT NOT NULL, Term NVARCHAR(60) NOT NULL);
    IF @SearchTermsJson IS NOT NULL AND ISJSON(@SearchTermsJson) = 1
        INSERT INTO @Terms (GroupIndex, Term)
        SELECT GroupIndex, Term
        FROM OPENJSON(@SearchTermsJson)
             WITH (GroupIndex INT '$.g', Term NVARCHAR(60) '$.t')
        WHERE GroupIndex IS NOT NULL AND Term IS NOT NULL AND LEN(Term) > 0;

    DECLARE @GroupCount INT = (SELECT COUNT(DISTINCT GroupIndex) FROM @Terms);

    IF @GroupCount = 0
    BEGIN
        SELECT TOP (200) ExerciseId, Name, MuscleGroup, EquipmentType, IsCompound, DemoVideoUrl,
               CAST(CASE WHEN CreatedByUserId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsCustom
        FROM dbo.Exercises
        WHERE (CreatedByUserId IS NULL OR CreatedByUserId = @UserId)
          AND (@MuscleGroups IS NULL
               OR MuscleGroup IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(NULLIF(@MuscleGroups, N''), N',')))
          AND (@Phrase IS NULL OR Name LIKE N'%' + @Phrase + N'%')
        ORDER BY Name;
        RETURN;
    END;

    WITH Candidates AS
    (
        SELECT ExerciseId, Name, MuscleGroup, EquipmentType, IsCompound, DemoVideoUrl,
               CAST(CASE WHEN CreatedByUserId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsCustom,
               REPLACE(REPLACE(Name, N'-', N''), N' ', N'') AS SquashedName
        FROM dbo.Exercises
        WHERE (CreatedByUserId IS NULL OR CreatedByUserId = @UserId)
          AND (@MuscleGroups IS NULL
               OR MuscleGroup IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(NULLIF(@MuscleGroups, N''), N',')))
    ),
    WordHits AS
    (
        SELECT c.ExerciseId, t.GroupIndex,
               MAX(CASE WHEN c.Name LIKE N'%' + t.Term + N'%'
                          OR c.SquashedName LIKE N'%' + t.Term + N'%' THEN 1 ELSE 0 END) AS InName,
               MAX(CASE WHEN c.Name LIKE N'%' + t.Term + N'%'
                          OR c.SquashedName LIKE N'%' + t.Term + N'%'
                          OR c.MuscleGroup LIKE N'%' + t.Term + N'%'
                          OR c.EquipmentType LIKE N'%' + t.Term + N'%' THEN 1 ELSE 0 END) AS Anywhere
        FROM Candidates c
        CROSS JOIN @Terms t
        GROUP BY c.ExerciseId, t.GroupIndex
    ),
    Scored AS
    (
        SELECT ExerciseId, SUM(Anywhere) AS WordsMatched, SUM(InName) AS NameWordsMatched
        FROM WordHits
        GROUP BY ExerciseId
    )
    SELECT TOP (200) c.ExerciseId, c.Name, c.MuscleGroup, c.EquipmentType, c.IsCompound, c.DemoVideoUrl, c.IsCustom
    FROM Scored s
    INNER JOIN Candidates c ON c.ExerciseId = s.ExerciseId
    WHERE s.NameWordsMatched >= 1
      AND s.WordsMatched * 2 >= @GroupCount
    ORDER BY s.WordsMatched DESC,
             CASE WHEN @Phrase IS NOT NULL AND c.Name LIKE N'%' + @Phrase + N'%' THEN 0 ELSE 1 END,
             s.NameWordsMatched DESC,
             LEN(c.Name),
             c.Name;
END
GO

-- Every exercise the user can pick (the catalogue plus their own), for the
-- "did you mean" pass ExerciseCloseMatches runs in the API when a search finds
-- nothing - typo tolerance needs edit distances the LIKE search above can't do.
-- Only the name-matching columns plus what a picker row shows.
CREATE OR ALTER PROCEDURE dbo.usp_Exercises_GetPickable
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ExerciseId, Name, MuscleGroup, EquipmentType, IsCompound, DemoVideoUrl,
           CAST(CASE WHEN CreatedByUserId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsCustom
    FROM dbo.Exercises
    WHERE CreatedByUserId IS NULL OR CreatedByUserId = @UserId;
END
GO

-- An exercise the user couldn't find, added from the exercise picker; private
-- to them. A name they already have, or one the catalogue already has (same
-- name ignoring case, spaces and hyphens), returns that row instead of adding
-- a duplicate, so a retried save or a near-miss search can't fork the list.
CREATE OR ALTER PROCEDURE dbo.usp_Exercises_CreateCustom
    @UserId UNIQUEIDENTIFIER,
    @Name NVARCHAR(150),
    @MuscleGroup NVARCHAR(30),
    @EquipmentType NVARCHAR(50) = NULL,
    @IsCompound BIT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Squashed NVARCHAR(150) = REPLACE(REPLACE(@Name, N'-', N''), N' ', N'');
    DECLARE @ExerciseId UNIQUEIDENTIFIER;

    BEGIN TRANSACTION;

    SELECT TOP (1) @ExerciseId = ExerciseId
    FROM dbo.Exercises WITH (UPDLOCK, HOLDLOCK)
    WHERE (CreatedByUserId IS NULL OR CreatedByUserId = @UserId)
      AND REPLACE(REPLACE(Name, N'-', N''), N' ', N'') = @Squashed
    ORDER BY CASE WHEN CreatedByUserId IS NULL THEN 0 ELSE 1 END;

    IF @ExerciseId IS NULL
    BEGIN
        SET @ExerciseId = NEWID();
        INSERT INTO dbo.Exercises (ExerciseId, Name, MuscleGroup, EquipmentType, IsCompound, CreatedByUserId)
        VALUES (@ExerciseId, @Name, @MuscleGroup, @EquipmentType, @IsCompound, @UserId);
    END

    COMMIT TRANSACTION;

    SELECT ExerciseId, Name, MuscleGroup, EquipmentType, IsCompound, DemoVideoUrl,
           CAST(CASE WHEN CreatedByUserId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsCustom
    FROM dbo.Exercises
    WHERE ExerciseId = @ExerciseId;
END
GO
