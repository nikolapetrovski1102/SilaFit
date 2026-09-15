USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- The app's split library.
--
-- Visibility rules live here, not in the API, so there is exactly one predicate
-- deciding what a normal user may see and no endpoint can accidentally bypass it:
--
--   * system/shipped splits          - always visible (public catalogue)
--   * Visibility = 'Public'          - a trainer's split shared with everyone
--   * a SplitAssignments row for the caller - 'Shared'/'Private' split handed to
--     this specific user. Guests (@UserId NULL) only ever see the first two.
--
-- @UserId is optional because the library is browseable by guests.
--
-- TOP is a safety valve, not paging: the catalogue is curated content, but an
-- admin/trainer could in principle create unbounded public splits and this list is
-- anonymous, so the response is capped rather than allowed to grow without bound.
CREATE OR ALTER PROCEDURE dbo.usp_Splits_GetAll
    @UserId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (2500) s.SplitId,
           s.Name,
           s.Category,
           s.Level,
           s.DurationDays,
           s.Description,
           s.HeroImageUrl,
           s.IsSystemDefault,
           s.SortOrder,
           s.RecommendedGoal,
           s.Visibility,
           s.DaysPerWeek,
           s.ProgramDurationWeeks,
           s.MinSessionMinutes,
           s.MaxSessionMinutes,
           s.EquipmentRequired,
           s.TargetGender,
           s.WorkoutTypeLabel,
           s.SourceCategoriesJson,
           -- Average training-day length, surfaced so the recommender can fit a
           -- user's session-duration answer. Rest days are excluded so a split
           -- with recovery days booked still reports a realistic session.
           ISNULL((SELECT CONVERT(INT, AVG(d.EstimatedMinutes))
                   FROM dbo.SplitDays d
                   WHERE d.SplitId = s.SplitId
                     AND d.IsRestDay = 0), 0) AS AvgSessionMinutes
    FROM dbo.WorkoutSplits s
    WHERE s.IsSystemDefault = 1
       OR s.Visibility = N'Public'
       OR (@UserId IS NOT NULL
           AND EXISTS (SELECT 1
                       FROM dbo.SplitAssignments a
                       WHERE a.SplitId = s.SplitId
                         AND a.UserId = @UserId))
    ORDER BY s.SortOrder;
END
GO

-- Result set 1: split header. Result set 2: its days. Result set 3: each
-- day's target exercises.
--
-- Detail is behind the same visibility predicate as the list: a user who
-- guesses a SplitId must not be able to read a private or unassigned split.
-- All three result sets are always emitted (empty when invisible) so the
-- provider's reader can advance through them unconditionally; a null header
-- is what the service turns into "not found".
CREATE OR ALTER PROCEDURE dbo.usp_Splits_GetDetail
    @SplitId UNIQUEIDENTIFIER,
    @UserId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Visible BIT = 0;

    SELECT @Visible = 1
    FROM dbo.WorkoutSplits s
    WHERE s.SplitId = @SplitId
      AND (s.IsSystemDefault = 1
           OR s.Visibility = N'Public'
           OR (@UserId IS NOT NULL
               AND EXISTS (SELECT 1
                           FROM dbo.SplitAssignments a
                           WHERE a.SplitId = s.SplitId
                             AND a.UserId = @UserId)));

    SELECT SplitId, Name, Category, Level, DurationDays, Description, HeroImageUrl, IsSystemDefault, SortOrder, RecommendedGoal, Visibility,
           DaysPerWeek, ProgramDurationWeeks, MinSessionMinutes, MaxSessionMinutes,
           EquipmentRequired, TargetGender, WorkoutTypeLabel, SourceCategoriesJson,
           ISNULL((SELECT CONVERT(INT, AVG(d.EstimatedMinutes))
                   FROM dbo.SplitDays d
                   WHERE d.SplitId = @SplitId
                     AND d.IsRestDay = 0), 0) AS AvgSessionMinutes
    FROM dbo.WorkoutSplits
    WHERE SplitId = @SplitId
      AND @Visible = 1;

    SELECT SplitDayId, DayIndex, Title, FocusLabel, EstimatedMinutes, IsRestDay
    FROM dbo.SplitDays
    WHERE SplitId = @SplitId
      AND @Visible = 1
    ORDER BY DayIndex;

    SELECT sd.SplitDayId, e.ExerciseId, e.Name, sde.SortOrder, sde.TargetSets, sde.TargetRepsLow, sde.TargetRepsHigh
    FROM dbo.SplitDays sd
    INNER JOIN dbo.SplitDayExercises sde ON sde.SplitDayId = sd.SplitDayId
    INNER JOIN dbo.Exercises e ON e.ExerciseId = sde.ExerciseId
    WHERE sd.SplitId = @SplitId
      AND @Visible = 1
    ORDER BY sd.DayIndex, sde.SortOrder;
END
GO

-- @IsAutoAssigned defaults to 0 (a user's own pick via POST /api/splits/activate).
-- The recommender passes 1 explicitly, so a later re-check
-- (AutoAssignRecommendedAsync) can tell its own pick apart from one the user
-- made deliberately and never overwrite the latter.
CREATE OR ALTER PROCEDURE dbo.usp_UserActiveSplit_Set
    @UserId UNIQUEIDENTIFIER,
    @SplitId UNIQUEIDENTIFIER,
    @IsAutoAssigned BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dbo.UserActiveSplits AS target
    USING (SELECT @UserId AS UserId, @SplitId AS SplitId, @IsAutoAssigned AS IsAutoAssigned) AS source
    ON target.UserId = source.UserId
    WHEN MATCHED THEN
        UPDATE SET SplitId = source.SplitId, ActivatedAtUtc = SYSUTCDATETIME(), IsAutoAssigned = source.IsAutoAssigned
    WHEN NOT MATCHED THEN
        INSERT (UserId, SplitId, ActivatedAtUtc, IsAutoAssigned) VALUES (source.UserId, source.SplitId, SYSUTCDATETIME(), source.IsAutoAssigned);

    SELECT UserId, SplitId, ActivatedAtUtc, IsAutoAssigned FROM dbo.UserActiveSplits WHERE UserId = @UserId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_UserActiveSplit_Get
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT uas.UserId, uas.SplitId, uas.ActivatedAtUtc, uas.IsAutoAssigned, ws.Name, ws.DurationDays
    FROM dbo.UserActiveSplits uas
    INNER JOIN dbo.WorkoutSplits ws ON ws.SplitId = uas.SplitId
    WHERE uas.UserId = @UserId;
END
GO
