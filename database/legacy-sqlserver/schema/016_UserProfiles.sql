USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.UserProfiles', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.UserProfiles
    (
        UserId          UNIQUEIDENTIFIER NOT NULL,
        Gender          NVARCHAR(10)     NULL CONSTRAINT CK_UserProfiles_Gender CHECK (Gender IN ('Male', 'Female', 'Other')),
        AgeYears        TINYINT          NULL,
        HeightCm        DECIMAL(5, 1)    NULL,
        WeightKg        DECIMAL(5, 1)    NULL,
        Goal            NVARCHAR(20)     NULL CONSTRAINT CK_UserProfiles_Goal CHECK (Goal IN ('BuildMuscle', 'LoseFat', 'MaintainActive')),
        CreatedAtUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_UserProfiles_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),
        UpdatedAtUtc    DATETIME2(3)     NOT NULL CONSTRAINT DF_UserProfiles_UpdatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_UserProfiles PRIMARY KEY CLUSTERED (UserId),
        CONSTRAINT FK_UserProfiles_Users FOREIGN KEY (UserId) REFERENCES dbo.Users(UserId)
    );
END
GO
