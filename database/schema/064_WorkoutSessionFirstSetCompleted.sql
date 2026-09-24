USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- When the first set of a session was ticked off in the Active Workout
-- Tracker, reported by the workout heartbeat. StartedAtUtc can't serve this
-- purpose: it is stamped as soon as the tracker is opened (the notification
-- publisher relies on that), so it can't tell "opened and backed out" apart
-- from "mid-workout". usp_WorkoutSession_GetTodayScheduled only keeps today's
-- session pinned to its split day once this is set (or the session is
-- completed), so switching splits after merely peeking at the tracker still
-- moves today over to the new split.
IF COL_LENGTH('dbo.WorkoutSessions', 'FirstSetCompletedAtUtc') IS NULL
BEGIN
    ALTER TABLE dbo.WorkoutSessions
        ADD FirstSetCompletedAtUtc DATETIME2(3) NULL;
END
GO
