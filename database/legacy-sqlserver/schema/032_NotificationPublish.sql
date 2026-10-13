USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Push tokens the app registers once the user grants notification permission
-- (see Silen.Services -> NotificationPublishService). One user can legitimately
-- have several (phone + tablet); a broadcast fans out to every active token and
-- the FCM sender deactivates any token the provider reports as unregistered.
IF OBJECT_ID(N'dbo.UserDeviceTokens', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserDeviceTokens
    (
        DeviceTokenId   UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_UserDeviceTokens_Id DEFAULT NEWSEQUENTIALID(),
        UserId          UNIQUEIDENTIFIER NOT NULL,
        Platform        NVARCHAR(20)     NOT NULL CONSTRAINT DF_UserDeviceTokens_Platform DEFAULT ('unknown'),
        PushToken       NVARCHAR(512)    NOT NULL,
        TimeZoneId      NVARCHAR(100)    NULL,
        IsActive        BIT              NOT NULL CONSTRAINT DF_UserDeviceTokens_IsActive DEFAULT (1),
        CreatedAtUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_UserDeviceTokens_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedAtUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_UserDeviceTokens_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),
        LastSeenAtUtc   DATETIME2(3)     NOT NULL CONSTRAINT DF_UserDeviceTokens_LastSeenAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_UserDeviceTokens PRIMARY KEY CLUSTERED (DeviceTokenId),
        CONSTRAINT FK_UserDeviceTokens_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT CK_UserDeviceTokens_Platform CHECK (Platform IN ('android', 'ios', 'web', 'windows', 'macos', 'linux', 'unknown'))
    );

    -- A token identifies one install: re-registering it (fresh launch, account
    -- switch on the same device) must move it to the current user, not clone it.
    CREATE UNIQUE INDEX UX_UserDeviceTokens_PushToken ON dbo.UserDeviceTokens(PushToken);

    CREATE INDEX IX_UserDeviceTokens_UserId_IsActive ON dbo.UserDeviceTokens(UserId, IsActive);
END
GO

-- Notification outbox + delivery audit. Every message the publish service
-- decides to send is written here first (idempotency via the unique
-- UserId + DedupeKey), then updated with its delivery outcome. Also doubles as
-- an engagement ledger: OpenedAtUtc is how the "user went quiet" backoff is
-- measured.
IF OBJECT_ID(N'dbo.UserNotifications', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserNotifications
    (
        NotificationId     UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_UserNotifications PRIMARY KEY CLUSTERED,
        UserId             UNIQUEIDENTIFIER NOT NULL,
        Category           NVARCHAR(30)     NOT NULL,
        Title              NVARCHAR(120)    NOT NULL,
        Body               NVARCHAR(500)    NOT NULL,
        DeepLink           NVARCHAR(200)    NULL,
        DedupeKey          NVARCHAR(120)    NOT NULL,
        Status             NVARCHAR(20)     NOT NULL CONSTRAINT DF_UserNotifications_Status DEFAULT ('Created'),
        ProviderMessageId  NVARCHAR(200)    NULL,
        ErrorMessage       NVARCHAR(1000)   NULL,
        ScheduledLocalAt   DATETIME2(3)     NULL,
        SentAtUtc          DATETIME2(3)     NULL,
        OpenedAtUtc        DATETIME2(3)     NULL,
        CreatedAtUtc       DATETIME2(3)     NOT NULL CONSTRAINT DF_UserNotifications_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_UserNotifications_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId),
        CONSTRAINT CK_UserNotifications_Category CHECK (Category IN ('GymReminder', 'TrackSets', 'TrackCalories', 'MealIdea', 'Motivation', 'Comeback')),
        CONSTRAINT CK_UserNotifications_Status CHECK (Status IN ('Created', 'Sent', 'Failed', 'Skipped', 'Opened'))
    );

    -- The single fact that makes the frequent (every-few-minutes) batch safe to
    -- re-run: the same reminder can only ever be enqueued once per user.
    CREATE UNIQUE INDEX UX_UserNotifications_UserId_DedupeKey ON dbo.UserNotifications(UserId, DedupeKey);

    CREATE INDEX IX_UserNotifications_UserId_CreatedAtUtc ON dbo.UserNotifications(UserId, CreatedAtUtc DESC);
    CREATE INDEX IX_UserNotifications_UserId_Category_SentAtUtc ON dbo.UserNotifications(UserId, Category, SentAtUtc);
END
GO

-- Per-user engagement state: when they last interacted with the app, when we
-- last pushed, and the last time we sent the two "low frequency" categories so
-- their cooldowns survive across runs.
IF OBJECT_ID(N'dbo.UserNotificationStates', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserNotificationStates
    (
        UserId               UNIQUEIDENTIFIER NOT NULL CONSTRAINT PK_UserNotificationStates PRIMARY KEY CLUSTERED,
        LastInteractionAtUtc DATETIME2(3)     NULL,
        LastPushedAtUtc      DATETIME2(3)     NULL,
        LastMotivationAtUtc  DATETIME2(3)     NULL,
        LastComebackAtUtc    DATETIME2(3)     NULL,
        PushedCount          INT              NOT NULL CONSTRAINT DF_UserNotificationStates_PushedCount DEFAULT (0),
        UpdatedAtUtc         DATETIME2(3)     NOT NULL CONSTRAINT DF_UserNotificationStates_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_UserNotificationStates_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId)
    );
END
GO

-- Lightweight "I'm still in the gym" heartbeat. The app's Active Workout
-- Tracker is otherwise entirely client-side, so without this the server has no
-- way to know a session is in progress and can't time a "log your sets" nudge.
IF COL_LENGTH('dbo.WorkoutSessions', 'LastActivityAtUtc') IS NULL
BEGIN
    ALTER TABLE dbo.WorkoutSessions
        ADD LastActivityAtUtc DATETIME2(3) NULL;
END
GO
