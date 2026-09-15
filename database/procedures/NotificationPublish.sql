USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Registers (or refreshes) a push token for a user and, when supplied, the
-- timezone + notification opt-in that go with it. Called from onboarding the
-- moment the OS prompt is answered, so the very first reminder is already
-- scheduled against the device's own clock rather than the server's.
--
-- @Token is nullable: opting in with no push token yet still persists the
-- timezone/opt-in, so the app can call this twice (once on permission, once
-- once FCM hands back a token) without either call being a no-op.
CREATE OR ALTER PROCEDURE dbo.usp_Notification_RegisterDeviceToken
    @UserId               UNIQUEIDENTIFIER,
    @Token                NVARCHAR(512) = NULL,
    @Platform             NVARCHAR(20)  = 'unknown',
    @TimeZoneId           NVARCHAR(100) = NULL,
    @NotificationsEnabled BIT          = NULL,
    @NowUtc               DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;

    IF @TimeZoneId IS NOT NULL OR @NotificationsEnabled IS NOT NULL
    BEGIN
        UPDATE dbo.UserSettings
        SET TimeZoneId           = ISNULL(@TimeZoneId, TimeZoneId),
            NotificationsEnabled = ISNULL(@NotificationsEnabled, NotificationsEnabled),
            UpdatedAtUtc         = @NowUtc
        WHERE UserId = @UserId;
    END

    IF @Token IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM dbo.UserDeviceTokens WHERE PushToken = @Token)
        BEGIN
            UPDATE dbo.UserDeviceTokens
            SET UserId        = @UserId,
                Platform      = @Platform,
                TimeZoneId    = ISNULL(@TimeZoneId, TimeZoneId),
                IsActive      = 1,
                LastSeenAtUtc = @NowUtc,
                UpdatedAtUtc  = @NowUtc
            WHERE PushToken = @Token;
        END
        ELSE
        BEGIN
            INSERT INTO dbo.UserDeviceTokens (UserId, Platform, PushToken, TimeZoneId, LastSeenAtUtc, UpdatedAtUtc)
            VALUES (@UserId, @Platform, @Token, @TimeZoneId, @NowUtc, @NowUtc);
        END
    END

    -- Opting in/refreshing counts as an interaction. Without this, a brand-new
    -- user would look "gone quiet" (their only timestamp being account
    -- creation) and get the comeback message on day one.
    IF EXISTS (SELECT 1 FROM dbo.UserNotificationStates WHERE UserId = @UserId)
    BEGIN
        UPDATE dbo.UserNotificationStates
        SET LastInteractionAtUtc = @NowUtc,
            UpdatedAtUtc         = @NowUtc
        WHERE UserId = @UserId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.UserNotificationStates (UserId, LastInteractionAtUtc, UpdatedAtUtc)
        VALUES (@UserId, @NowUtc, @NowUtc);
    END
END
GO

-- Deactivates one token (sign-out, permission revoked, or the provider told us
-- it is unregistered). Kept rather than deleted so re-registering revives it.
CREATE OR ALTER PROCEDURE dbo.usp_Notification_DeactivateDeviceToken
    @UserId UNIQUEIDENTIFIER,
    @Token  NVARCHAR(512)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.UserDeviceTokens
    SET IsActive     = 0,
        UpdatedAtUtc = SYSUTCDATETIME()
    WHERE UserId = @UserId
      AND PushToken = @Token;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Notification_GetActiveDeviceTokens
    @UserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT DeviceTokenId, UserId, Platform, PushToken, TimeZoneId, IsActive,
           CreatedAtUtc, UpdatedAtUtc, LastSeenAtUtc
    FROM dbo.UserDeviceTokens
    WHERE UserId = @UserId
      AND IsActive = 1
    ORDER BY LastSeenAtUtc DESC;
END
GO

-- Records that the user actually used the app (foreground/open, or tapped a
-- notification). This is the heartbeat the backoff logic measures: too long a
-- gap and normal reminders quiet down, then a single comeback message fires.
CREATE OR ALTER PROCEDURE dbo.usp_Notification_RecordInteraction
    @UserId         UNIQUEIDENTIFIER,
    @AtUtc          DATETIME2(3),
    @NotificationId UNIQUEIDENTIFIER = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dbo.UserNotificationStates WHERE UserId = @UserId)
    BEGIN
        UPDATE dbo.UserNotificationStates
        SET LastInteractionAtUtc = @AtUtc,
            UpdatedAtUtc         = @AtUtc
        WHERE UserId = @UserId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.UserNotificationStates (UserId, LastInteractionAtUtc, UpdatedAtUtc)
        VALUES (@UserId, @AtUtc, @AtUtc);
    END

    IF @NotificationId IS NOT NULL
    BEGIN
        UPDATE dbo.UserNotifications
        SET OpenedAtUtc = @AtUtc,
            Status      = 'Opened'
        WHERE NotificationId = @NotificationId
          AND UserId = @UserId
          AND Status IN ('Created', 'Sent');
    END
END
GO

-- Every opted-in user with at least one active device token, plus the raw facts
-- the scheduler needs to decide what (if anything) to send. All timestamps come
-- back in UTC; the service converts to each user's timezone in memory, so this
-- never has to know about IANA/Windows zone names.
--
-- @MaxUsers is applied here, not in the caller: the API used to materialize every
-- opted-in user and then Take(MaxUsersPerRun) in memory, so a single run's cost
-- scaled with the whole user base. Ordering by UserId is deterministic; once the
-- opted-in base can exceed @MaxUsers, the next step is a persisted keyset cursor.
CREATE OR ALTER PROCEDURE dbo.usp_NotificationPublish_GetCandidates
    @MaxUsers INT = 5000
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH TokenCounts AS (
        SELECT UserId, COUNT(*) AS ActiveTokenCount
        FROM dbo.UserDeviceTokens
        WHERE IsActive = 1
        GROUP BY UserId
    ),
    Workouts AS (
        SELECT UserId,
               MAX(StartedAtUtc)   AS LastWorkoutStartedAtUtc,
               MAX(CompletedAtUtc) AS LastWorkoutCompletedAtUtc,
               COUNT(CASE WHEN CompletedAtUtc >= DATEADD(DAY, -7, SYSUTCDATETIME()) THEN 1 END) AS WorkoutsLast7Days
        FROM dbo.WorkoutSessions
        GROUP BY UserId
    ),
    ActiveSessions AS (
        SELECT UserId,
               MAX(StartedAtUtc)    AS ActiveSessionStartedAtUtc,
               MAX(LastActivityAtUtc) AS ActiveSessionLastActivityAtUtc
        FROM dbo.WorkoutSessions
        WHERE StartedAtUtc IS NOT NULL
          AND CompletedAtUtc IS NULL
        GROUP BY UserId
    ),
    MealStats AS (
        SELECT UserId,
               MAX(LoggedAtUtc) AS LastMealLoggedAtUtc,
               COUNT(CASE WHEN LoggedAtUtc >= DATEADD(HOUR, -24, SYSUTCDATETIME()) THEN 1 END) AS MealsLast24h
        FROM dbo.MealLogs
        WHERE Status = 'Logged'
        GROUP BY UserId
    ),
    NotificationStats AS (
        SELECT UserId,
               COUNT(CASE WHEN SentAtUtc >= DATEADD(HOUR, -24, SYSUTCDATETIME()) THEN 1 END) AS SentLast24h
        FROM dbo.UserNotifications
        GROUP BY UserId
    )
    SELECT TOP (@MaxUsers)
        u.UserId,
        u.DisplayName,
        s.NotificationsEnabled,
        s.NotificationLocalTime,
        s.TimeZoneId,
        COALESCE(st.LastInteractionAtUtc, u.LastLoginAtUtc, u.CreatedAtUtc) AS LastInteractionAtUtc,
        st.LastPushedAtUtc,
        st.LastMotivationAtUtc,
        st.LastComebackAtUtc,
        ISNULL(ns.SentLast24h, 0) AS SentLast24h,
        w.LastWorkoutStartedAtUtc,
        w.LastWorkoutCompletedAtUtc,
        ISNULL(w.WorkoutsLast7Days, 0) AS WorkoutsLast7Days,
        a.ActiveSessionStartedAtUtc,
        a.ActiveSessionLastActivityAtUtc,
        m.LastMealLoggedAtUtc,
        ISNULL(m.MealsLast24h, 0) AS MealsLast24h,
        -- Drives the monthly-review upsell: only non-paying users (no active
        -- PRO/ADVANCED entitlement) get the "unlock your review" push. Same
        -- plan-code set as SubscriptionGate.ProPlanCodes and
        -- usp_Plans_GetNonSubscribers.
        CAST(CASE WHEN EXISTS (
            SELECT 1
            FROM dbo.UserSubscriptions us
            INNER JOIN dbo.SubscriptionPlans sp ON sp.PlanId = us.PlanId
            WHERE us.UserId = u.UserId
              AND us.Status = 'Active'
              AND (us.ExpiresAtUtc IS NULL OR us.ExpiresAtUtc > SYSUTCDATETIME())
              AND sp.Code IN (N'PRO', N'ADVANCED')
        ) THEN 1 ELSE 0 END AS BIT) AS HasPaidSubscription,
        tc.ActiveTokenCount
    FROM dbo.UserSettings s
    INNER JOIN dbo.Users u ON u.UserId = s.UserId
    INNER JOIN TokenCounts tc ON tc.UserId = s.UserId
    LEFT JOIN dbo.UserNotificationStates st ON st.UserId = s.UserId
    LEFT JOIN Workouts w ON w.UserId = s.UserId
    LEFT JOIN ActiveSessions a ON a.UserId = s.UserId
    LEFT JOIN MealStats m ON m.UserId = s.UserId
    LEFT JOIN NotificationStats ns ON ns.UserId = s.UserId
    -- NOTE: UserNutritionTargets is deliberately not joined. Its TargetCalories
    -- is an encrypted VARBINARY column after the column-encryption cutover
    -- (schema 025), so it must only be read through the decrypting provider,
    -- not in raw reporting SQL like this.
    WHERE s.NotificationsEnabled = 1
      AND u.IsActive = 1
    ORDER BY u.UserId;
END
GO

-- Enqueues one notification unless its dedupe key already exists for the user.
-- Returns the created row, or nothing when it was a duplicate - that empty
-- result is what lets the batch run every few minutes without re-sending.
-- (HOLDLOCK/UPDLOCK is what keeps two overlapping runs from both passing the
-- existence check and racing into the unique index.)
CREATE OR ALTER PROCEDURE dbo.usp_NotificationPublish_TryCreate
    @UserId           UNIQUEIDENTIFIER,
    @Category         NVARCHAR(30),
    @Title            NVARCHAR(120),
    @Body             NVARCHAR(500),
    @DeepLink         NVARCHAR(200) = NULL,
    @DedupeKey        NVARCHAR(120),
    @ScheduledLocalAt DATETIME2(3)  = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @NotificationId UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.UserNotifications
        (NotificationId, UserId, Category, Title, Body, DeepLink, DedupeKey, Status, ScheduledLocalAt)
    SELECT @NotificationId, @UserId, @Category, @Title, @Body, @DeepLink, @DedupeKey, 'Created', @ScheduledLocalAt
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.UserNotifications WITH (UPDLOCK, HOLDLOCK)
        WHERE UserId = @UserId AND DedupeKey = @DedupeKey
    );

    IF @@ROWCOUNT = 0
    BEGIN
        RETURN;
    END

    SELECT NotificationId, UserId, Category, Title, Body, DeepLink, DedupeKey, Status,
           ProviderMessageId, ErrorMessage, ScheduledLocalAt, SentAtUtc, OpenedAtUtc, CreatedAtUtc
    FROM dbo.UserNotifications
    WHERE NotificationId = @NotificationId;
END
GO

-- Marks a notification delivered and advances the per-user cooldown state
-- (last push, and the two low-frequency category timestamps).
CREATE OR ALTER PROCEDURE dbo.usp_NotificationPublish_MarkSent
    @NotificationId    UNIQUEIDENTIFIER,
    @Category          NVARCHAR(30),
    @ProviderMessageId NVARCHAR(200) = NULL,
    @SentAtUtc         DATETIME2(3)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.UserNotifications
    SET Status            = 'Sent',
        ProviderMessageId = @ProviderMessageId,
        SentAtUtc         = @SentAtUtc,
        ErrorMessage      = NULL
    WHERE NotificationId = @NotificationId;

    DECLARE @UserId UNIQUEIDENTIFIER =
        (SELECT UserId FROM dbo.UserNotifications WHERE NotificationId = @NotificationId);

    IF @UserId IS NULL
    BEGIN
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM dbo.UserNotificationStates WHERE UserId = @UserId)
    BEGIN
        UPDATE dbo.UserNotificationStates
        SET LastPushedAtUtc     = @SentAtUtc,
            PushedCount         = PushedCount + 1,
            LastMotivationAtUtc = CASE WHEN @Category = 'Motivation' THEN @SentAtUtc ELSE LastMotivationAtUtc END,
            LastComebackAtUtc   = CASE WHEN @Category = 'Comeback' THEN @SentAtUtc ELSE LastComebackAtUtc END,
            UpdatedAtUtc        = SYSUTCDATETIME()
        WHERE UserId = @UserId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.UserNotificationStates
            (UserId, LastPushedAtUtc, PushedCount, LastMotivationAtUtc, LastComebackAtUtc, UpdatedAtUtc)
        VALUES
            (@UserId, @SentAtUtc, 1,
             CASE WHEN @Category = 'Motivation' THEN @SentAtUtc END,
             CASE WHEN @Category = 'Comeback' THEN @SentAtUtc END,
             SYSUTCDATETIME());
    END
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_NotificationPublish_MarkFailed
    @NotificationId UNIQUEIDENTIFIER,
    @ErrorMessage   NVARCHAR(1000)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.UserNotifications
    SET Status       = 'Failed',
        ErrorMessage = @ErrorMessage
    WHERE NotificationId = @NotificationId;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_NotificationPublish_MarkSkipped
    @NotificationId UNIQUEIDENTIFIER,
    @Reason         NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.UserNotifications
    SET Status       = 'Skipped',
        ErrorMessage = @Reason
    WHERE NotificationId = @NotificationId;
END
GO

-- Safety net for the outbox. A normal run creates a notification and delivers it
-- in the same pass (usp_NotificationPublish_TryCreate -> MarkSent/Failed/Skipped),
-- so a row left in 'Created' means the process died mid-flight or the transport
-- failed before the row reached a terminal status. This feed lets a later run
-- retry those rows instead of stranding them forever.
--
-- @OlderThanUtc is the grace cutoff: the create -> deliver window is
-- milliseconds, so anything older than a few minutes is genuinely orphaned, and
-- a run that is merely in-flight is left alone. Ordered oldest-first so the
-- longest-stranded notifications are retried first under the @MaxRows cap.
CREATE OR ALTER PROCEDURE dbo.usp_NotificationPublish_GetPending
    @OlderThanUtc DATETIME2(3),
    @MaxRows      INT = 200
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@MaxRows)
           NotificationId, UserId, Category, Title, Body, DeepLink, DedupeKey, Status,
           ProviderMessageId, ErrorMessage, ScheduledLocalAt, SentAtUtc, OpenedAtUtc, CreatedAtUtc
    FROM dbo.UserNotifications
    WHERE Status = 'Created'
      AND CreatedAtUtc < @OlderThanUtc
    ORDER BY CreatedAtUtc;
END
GO
