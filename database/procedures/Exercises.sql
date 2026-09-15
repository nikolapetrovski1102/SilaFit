USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- @SearchText is always passed as a bound parameter value (never concatenated
-- into the command text), so this LIKE usage carries no injection risk.
-- TOP caps an anonymous, unbounded-in-principle search over the exercise catalogue.
CREATE OR ALTER PROCEDURE dbo.usp_Exercises_Search
    @MuscleGroup NVARCHAR(30) = NULL,
    @SearchText NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (200) ExerciseId, Name, MuscleGroup, EquipmentType, IsCompound, DemoVideoUrl
    FROM dbo.Exercises
    WHERE (@MuscleGroup IS NULL OR MuscleGroup = @MuscleGroup)
      AND (@SearchText IS NULL OR Name LIKE '%' + @SearchText + '%')
    ORDER BY Name;
END
GO
