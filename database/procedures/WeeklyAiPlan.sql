USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Opens one weekly plan-generation run. RunId is generated here so every
-- per-user delivery row written afterwards shares the same identifier even if
-- the worker process is restarted mid-batch (see usp_MonthlyReview_StartRun,
-- which this mirrors).
CREATE OR ALTER PROCEDURE dbo.usp_WeeklyAiPlan_StartRun
    @WeekStartUtc DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RunId UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.WeeklyAiPlanRuns (RunId, WeekStartUtc, Status)
    VALUES (@RunId, @WeekStartUtc, 'Running');

    SELECT RunId, WeekStartUtc, Status,
           UsersConsidered, PlansGenerated, NotificationsSent, Failures,
           StartedAtUtc, CompletedAtUtc
    FROM dbo.WeeklyAiPlanRuns
    WHERE RunId = @RunId;
END
GO

-- Finalises a run with its aggregate counters. Status stays 'Completed' even
-- when some users failed - Failures captures the count and the per-user
-- detail lives in WeeklyAiPlanDeliveries.
CREATE OR ALTER PROCEDURE dbo.usp_WeeklyAiPlan_CompleteRun
    @RunId             UNIQUEIDENTIFIER,
    @Status             NVARCHAR(20),
    @UsersConsidered    INT,
    @PlansGenerated     INT,
    @NotificationsSent  INT,
    @Failures           INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.WeeklyAiPlanRuns
    SET Status = @Status,
        CompletedAtUtc = SYSUTCDATETIME(),
        UsersConsidered = @UsersConsidered,
        PlansGenerated = @PlansGenerated,
        NotificationsSent = @NotificationsSent,
        Failures = @Failures
    WHERE RunId = @RunId;
END
GO

-- Users already settled for this week - a delivery row exists whose split AND
-- diet outcome are both something other than 'Failed' (i.e. either
-- successfully 'Generated' or validly 'Skipped', for example for not enough
-- logged activity). A user with a 'Failed' delivery on either side is left
-- out, so a later re-run of the same week retries only the ones that didn't
-- finish - this is what makes a run safely re-runnable (mirrors
-- usp_MonthlyReview_GetEmailedUserIds).
CREATE OR ALTER PROCEDURE dbo.usp_WeeklyAiPlan_GetProcessedUserIds
    @WeekStartUtc DATE
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DISTINCT UserId
    FROM dbo.WeeklyAiPlanDeliveries
    WHERE WeekStartUtc = @WeekStartUtc
      AND SplitStatus <> 'Failed'
      AND DietStatus <> 'Failed';
END
GO

-- One audit row per user considered by a run: what happened to their split
-- and diet plan (Generated / Skipped / Failed independently), the resulting
-- ids, and when the "your plan is ready" notification went out.
CREATE OR ALTER PROCEDURE dbo.usp_WeeklyAiPlan_RecordDelivery
    @RunId          UNIQUEIDENTIFIER,
    @UserId         UNIQUEIDENTIFIER,
    @WeekStartUtc   DATE,
    @SplitStatus    NVARCHAR(20),
    @DietStatus     NVARCHAR(20),
    @SplitId        UNIQUEIDENTIFIER = NULL,
    @DietPlanId     UNIQUEIDENTIFIER = NULL,
    @ErrorMessage   NVARCHAR(1000)   = NULL,
    @GeneratedAtUtc DATETIME2(3)     = NULL,
    @NotifiedAtUtc  DATETIME2(3)     = NULL
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.WeeklyAiPlanDeliveries
        (DeliveryId, RunId, UserId, WeekStartUtc, SplitStatus, DietStatus, SplitId, DietPlanId, ErrorMessage, GeneratedAtUtc, NotifiedAtUtc)
    VALUES
        (NEWID(), @RunId, @UserId, @WeekStartUtc, @SplitStatus, @DietStatus, @SplitId, @DietPlanId, @ErrorMessage, @GeneratedAtUtc, @NotifiedAtUtc);
END
GO

-- The weekly batch's audience: every active ADVANCED subscriber. Building a
-- fresh weekly split/diet plan is part of what the ADVANCED plan buys, so
-- there is no opt-in flag - the generated plans are simply left inactive for
-- the user to activate themselves.
CREATE OR ALTER PROCEDURE dbo.usp_WeeklyAiPlan_GetCandidateUsers
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        u.UserId,
        u.DisplayName,
        u.Email,
        sp.Code AS PlanCode,
        us.ExpiresAtUtc
    FROM dbo.UserSubscriptions us
    INNER JOIN dbo.SubscriptionPlans sp ON sp.PlanId = us.PlanId
    INNER JOIN dbo.Users u ON u.UserId = us.UserId
    WHERE sp.Code = N'ADVANCED'
      AND us.Status = 'Active'
      AND u.IsActive = 1
      AND (us.ExpiresAtUtc IS NULL OR us.ExpiresAtUtc > SYSUTCDATETIME())
    ORDER BY u.CreatedAtUtc;
END
GO
