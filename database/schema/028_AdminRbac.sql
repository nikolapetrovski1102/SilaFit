USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Role-based access control for console operators.
--
-- Privileges are *data*, not code: an operator's role is a row, and what that role
-- may do is a set of permission rows. The API re-reads them on every request, so
-- revoking a privilege takes effect on the next click rather than at the next
-- sign-in. Nothing in the backend hardcodes who may do what.
--
-- Permissions are plain capability strings ("<area>.<thing>.<verb>"), which keeps
-- them greppable and lets a custom role be granted something a future build adds
-- without a schema change.
IF OBJECT_ID(N'dbo.AdminRoles', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AdminRoles
    (
        RoleId       UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_AdminRoles_RoleId DEFAULT NEWSEQUENTIALID(),
        Name         NVARCHAR(64)     NOT NULL,
        Description  NVARCHAR(300)    NULL,
        -- System roles ship with the product and their permission set is immutable,
        -- so an operator can't accidentally strip operators.manage from super-admin
        -- and lock everyone out of granting it back. Custom roles (IsSystemRole = 0)
        -- are freely editable and are how you get a variation on a shipped role.
        IsSystemRole BIT              NOT NULL CONSTRAINT DF_AdminRoles_IsSystemRole DEFAULT (0),
        CreatedAtUtc DATETIME2(3)     NOT NULL CONSTRAINT DF_AdminRoles_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_AdminRoles PRIMARY KEY CLUSTERED (RoleId),
        CONSTRAINT UQ_AdminRoles_Name UNIQUE (Name)
    );
END
GO

IF OBJECT_ID(N'dbo.AdminRolePermissions', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AdminRolePermissions
    (
        RoleId     UNIQUEIDENTIFIER NOT NULL,
        Permission NVARCHAR(64)     NOT NULL,

        CONSTRAINT PK_AdminRolePermissions PRIMARY KEY CLUSTERED (RoleId, Permission),
        CONSTRAINT FK_AdminRolePermissions_AdminRoles FOREIGN KEY (RoleId)
            REFERENCES dbo.AdminRoles(RoleId) ON DELETE CASCADE
    );

    -- The per-request permission lookup goes the other way (operator -> role ->
    -- permissions); this index serves "who can do X" audits in the console.
    CREATE INDEX IX_AdminRolePermissions_Permission ON dbo.AdminRolePermissions(Permission);
END
GO

-- An operator with no role is denied everything: authorization fails closed, so a
-- half-provisioned account can sign in and still see nothing.
IF COL_LENGTH(N'dbo.AdminUsers', N'RoleId') IS NULL
BEGIN
    ALTER TABLE dbo.AdminUsers ADD RoleId UNIQUEIDENTIFIER NULL
        CONSTRAINT FK_AdminUsers_AdminRoles REFERENCES dbo.AdminRoles(RoleId);

    CREATE INDEX IX_AdminUsers_RoleId ON dbo.AdminUsers(RoleId);
END
GO

-- Who did what, to which row, from where. Written inside the same transaction as
-- the mutation it describes (see database/procedures/AdminContent.sql), so a write
-- that succeeds without a trace is not possible.
--
-- Username is denormalized on purpose: the trail has to stay readable after an
-- account is renamed, deactivated or removed.
IF OBJECT_ID(N'dbo.AdminAuditLog', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.AdminAuditLog
    (
        AuditId       UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_AdminAuditLog_AuditId DEFAULT NEWSEQUENTIALID(),
        AdminUserId   UNIQUEIDENTIFIER NULL,
        Username      NVARCHAR(100)    NOT NULL,
        Action        NVARCHAR(30)     NOT NULL,
        EntityType    NVARCHAR(50)     NOT NULL,
        EntityId      NVARCHAR(64)     NULL,
        Summary       NVARCHAR(500)    NULL,
        CreatedFromIp NVARCHAR(64)     NULL,
        CreatedAtUtc  DATETIME2(3)     NOT NULL CONSTRAINT DF_AdminAuditLog_CreatedAtUtc DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_AdminAuditLog PRIMARY KEY CLUSTERED (AuditId)
    );

    CREATE INDEX IX_AdminAuditLog_CreatedAtUtc ON dbo.AdminAuditLog(CreatedAtUtc DESC);
    CREATE INDEX IX_AdminAuditLog_AdminUserId ON dbo.AdminAuditLog(AdminUserId);
END
GO

-- ---------------------------------------------------------------------------
-- Default roles.
--
-- These are seeded, not enforced: nothing stops an operator from being moved to a
-- different role, or a custom role being created with a different split of
-- permissions. A role's defaults are granted **only when the role row is created**,
-- so re-running the deploy never resurrects a permission someone deliberately
-- revoked - which is exactly what a naive "insert missing rows" seed would do.
-- ---------------------------------------------------------------------------
DECLARE @CreatedRoles TABLE (RoleId UNIQUEIDENTIFIER);

INSERT INTO dbo.AdminRoles (Name, Description, IsSystemRole)
OUTPUT inserted.RoleId INTO @CreatedRoles (RoleId)
SELECT defaults.Name, defaults.Description, 1
FROM (VALUES
    (N'super-admin',    N'Full control: all content, users, operators, roles and the audit log.'),
    (N'content-editor', N'Can read and edit every content area and read the audit log, but not manage operators.'),
    (N'analyst',        N'Read-only across content, plus the user list and the audit log.'),
    (N'viewer',         N'Read-only across content. The safest role for a new operator.')
) AS defaults (Name, Description)
WHERE NOT EXISTS (SELECT 1 FROM dbo.AdminRoles existing WHERE existing.Name = defaults.Name);

DECLARE @DefaultGrants TABLE (RoleName NVARCHAR(64), Permission NVARCHAR(64));

INSERT INTO @DefaultGrants (RoleName, Permission)
VALUES
    -- super-admin: everything, listed explicitly rather than by wildcard so the
    -- permission set is auditable from this file alone.
    (N'super-admin', N'content.plans.read'),
    (N'super-admin', N'content.plans.write'),
    (N'super-admin', N'content.splits.read'),
    (N'super-admin', N'content.splits.write'),
    (N'super-admin', N'content.exercises.read'),
    (N'super-admin', N'content.exercises.write'),
    (N'super-admin', N'content.suggestions.read'),
    (N'super-admin', N'content.suggestions.write'),
    (N'super-admin', N'users.read'),
    (N'super-admin', N'operators.manage'),
    (N'super-admin', N'roles.manage'),
    (N'super-admin', N'audit.read'),
    -- content-editor: everything content, plus the trail of its own edits.
    (N'content-editor', N'content.plans.read'),
    (N'content-editor', N'content.plans.write'),
    (N'content-editor', N'content.splits.read'),
    (N'content-editor', N'content.splits.write'),
    (N'content-editor', N'content.exercises.read'),
    (N'content-editor', N'content.exercises.write'),
    (N'content-editor', N'content.suggestions.read'),
    (N'content-editor', N'content.suggestions.write'),
    (N'content-editor', N'audit.read'),
    -- analyst: read everything, change nothing.
    (N'analyst', N'content.plans.read'),
    (N'analyst', N'content.splits.read'),
    (N'analyst', N'content.exercises.read'),
    (N'analyst', N'content.suggestions.read'),
    (N'analyst', N'users.read'),
    (N'analyst', N'audit.read'),
    -- viewer: the content catalog and nothing else.
    (N'viewer', N'content.plans.read'),
    (N'viewer', N'content.splits.read'),
    (N'viewer', N'content.exercises.read'),
    (N'viewer', N'content.suggestions.read');

INSERT INTO dbo.AdminRolePermissions (RoleId, Permission)
SELECT roles.RoleId, grants.Permission
FROM @DefaultGrants grants
INNER JOIN dbo.AdminRoles roles ON roles.Name = grants.RoleName
-- Only roles created by *this* run get their defaults; pre-existing ones are left
-- exactly as an operator configured them.
INNER JOIN @CreatedRoles created ON created.RoleId = roles.RoleId;
GO
