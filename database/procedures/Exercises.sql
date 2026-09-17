USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- @SearchText is always passed as a bound parameter value (never concatenated
-- into the command text), so this LIKE usage carries no injection risk.
-- @MuscleGroups is a comma-separated list of the catalogue's coarse muscle
-- groups (chest/back/legs/shoulders/arms/core). STRING_SPLIT keeps the filter
-- set-based, so one round trip can scope a search or a suggestion read to every
-- group a day's title points at (e.g. "Chest & Triceps" -> chest,arms).
-- TOP caps an anonymous, unbounded-in-principle search over the exercise catalogue.
CREATE OR ALTER PROCEDURE dbo.usp_Exercises_Search
    @MuscleGroups NVARCHAR(200) = NULL,
    @SearchText NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (200) ExerciseId, Name, MuscleGroup, EquipmentType, IsCompound, DemoVideoUrl
    FROM dbo.Exercises
    WHERE (@MuscleGroups IS NULL
           OR MuscleGroup IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(NULLIF(@MuscleGroups, N''), N',')))
      AND (@SearchText IS NULL OR Name LIKE '%' + @SearchText + '%')
    ORDER BY Name;
END
GO
