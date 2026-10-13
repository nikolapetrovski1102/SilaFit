USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Role, permission and operator administration for the console.
--
-- Every procedure here that changes something writes its own audit row inside the
-- same transaction, so a mutation that commits without a trail is not possible -
-- including changes made by an operator who later has their access revoked.
--
-- Mutating procedures return one row: Outcome / EntityId / Detail. Outcome is the
-- contract the service layer maps to HTTP (0 = done, 1 = not found, 2 = conflict,
-- 3 = rejected input), which keeps business rules out of the procedures and the
-- messages in one place. See AdminWriteOutcome in Silen.Common/Models.

-- Permissions for one operator, resolved from their role at read time. The API
-- calls this on every request, so a privilege change takes effect immediately
-- instead of when a session happens to be re-created.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_GetPermissions
    @AdminUserId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;

    SELECT rp.Permission
    FROM dbo.AdminUsers u
    INNER JOIN dbo.AdminRolePermissions rp ON rp.RoleId = u.RoleId
    WHERE u.AdminUserId = @AdminUserId
      AND u.IsActive = 1
    ORDER BY rp.Permission;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_Roles_GetAll
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.RoleId,
           r.Name,
           r.Description,
           r.IsSystemRole,
           (SELECT COUNT(*) FROM dbo.AdminRolePermissions p WHERE p.RoleId = r.RoleId) AS PermissionCount,
           (SELECT COUNT(*) FROM dbo.AdminUsers u WHERE u.RoleId = r.RoleId) AS OperatorCount
    FROM dbo.AdminRoles r
    ORDER BY r.IsSystemRole DESC, r.Name;
END
GO

-- One row per permission, plus a single all-NULL row for a role that exists but
-- has none - so the caller can tell "unknown role" (no rows) from "role with no
-- permissions" without a second round trip.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_RolePermissions_GetForRole
    @RoleName NVARCHAR(64)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT r.Name AS RoleName, r.IsSystemRole, rp.Permission
    FROM dbo.AdminRoles r
    LEFT JOIN dbo.AdminRolePermissions rp ON rp.RoleId = r.RoleId
    WHERE r.Name = @RoleName
    ORDER BY rp.Permission;
END
GO

-- Custom (non-system) roles only. A shipped role's permission set is immutable so
-- that operators.manage can never be stripped from super-admin by accident.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_Role_Create
    @Name NVARCHAR(64),
    @Description NVARCHAR(300) = NULL,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Name = LTRIM(RTRIM(@Name));

    BEGIN TRANSACTION;

    IF @Name IS NULL OR @Name = N''
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'A role name is required.' AS Detail;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM dbo.AdminRoles WHERE Name = @Name)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId,
               N'A role named ''' + @Name + N''' already exists.' AS Detail;
        RETURN;
    END

    DECLARE @RoleId UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.AdminRoles (RoleId, Name, Description, IsSystemRole)
    VALUES (@RoleId, @Name, @Description, 0);

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Create', N'AdminRole', CONVERT(NVARCHAR(64), @RoleId),
            N'Created role ''' + @Name + N''' (starts with no permissions)', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @RoleId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_Role_Delete
    @Name NVARCHAR(64),
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Name = LTRIM(RTRIM(@Name));

    DECLARE @RoleId UNIQUEIDENTIFIER;
    DECLARE @IsSystemRole BIT;
    DECLARE @OperatorCount INT;

    BEGIN TRANSACTION;

    SELECT @RoleId = RoleId, @IsSystemRole = IsSystemRole
    FROM dbo.AdminRoles
    WHERE Name = @Name;

    IF @RoleId IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId,
               N'No role named ''' + @Name + N'''.' AS Detail;
        RETURN;
    END

    IF @IsSystemRole = 1
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @RoleId AS EntityId,
               N'''' + @Name + N''' is a built-in role and cannot be deleted.' AS Detail;
        RETURN;
    END

    SELECT @OperatorCount = COUNT(*) FROM dbo.AdminUsers WHERE RoleId = @RoleId;

    IF @OperatorCount > 0
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @RoleId AS EntityId,
               N'Still assigned to ' + CONVERT(NVARCHAR(10), @OperatorCount) + N' operator(s); move them to another role first.' AS Detail;
        RETURN;
    END

    -- Permissions cascade with the role.
    DELETE FROM dbo.AdminRoles WHERE RoleId = @RoleId;

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Delete', N'AdminRole', CONVERT(NVARCHAR(64), @RoleId),
            N'Deleted role ''' + @Name + N'''', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @RoleId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Grants or revokes one permission on one custom role - the fine-grained control
-- behind "some operators get read-write, some get read-only".
CREATE OR ALTER PROCEDURE dbo.usp_Admin_RolePermission_Set
    @RoleName NVARCHAR(64),
    @Permission NVARCHAR(64),
    @Granted BIT,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @RoleName = LTRIM(RTRIM(@RoleName));
    SET @Permission = LTRIM(RTRIM(@Permission));

    DECLARE @RoleId UNIQUEIDENTIFIER;
    DECLARE @IsSystemRole BIT;

    BEGIN TRANSACTION;

    SELECT @RoleId = RoleId, @IsSystemRole = IsSystemRole
    FROM dbo.AdminRoles
    WHERE Name = @RoleName;

    IF @RoleId IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId,
               N'No role named ''' + @RoleName + N'''.' AS Detail;
        RETURN;
    END

    IF @IsSystemRole = 1
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, @RoleId AS EntityId,
               N'''' + @RoleName + N''' is a built-in role; create a custom role to vary its permissions.' AS Detail;
        RETURN;
    END

    IF @Permission IS NULL OR @Permission = N''
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, @RoleId AS EntityId, N'A permission name is required.' AS Detail;
        RETURN;
    END

    IF @Granted = 1
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM dbo.AdminRolePermissions WHERE RoleId = @RoleId AND Permission = @Permission)
        BEGIN
            INSERT INTO dbo.AdminRolePermissions (RoleId, Permission) VALUES (@RoleId, @Permission);
        END
    END
    ELSE
    BEGIN
        DELETE FROM dbo.AdminRolePermissions WHERE RoleId = @RoleId AND Permission = @Permission;
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, CASE WHEN @Granted = 1 THEN N'Grant' ELSE N'Revoke' END,
            N'AdminRole', CONVERT(NVARCHAR(64), @RoleId),
            CASE WHEN @Granted = 1
                 THEN N'Granted ''' + @Permission + N''' to role ''' + @RoleName + N''''
                 ELSE N'Revoked ''' + @Permission + N''' from role ''' + @RoleName + N'''' END,
            @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @RoleId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Admin_Operators_GetAll
    @IncludeInactive BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    SELECT u.AdminUserId,
           u.Username,
           u.RoleId,
           r.Name AS RoleName,
           u.IsActive,
           u.LastLoginAtUtc,
           u.CreatedAtUtc,
           u.Email,
           u.EmailConfirmedAtUtc,
           (SELECT COUNT(*) FROM dbo.AdminSessions s WHERE s.AdminUserId = u.AdminUserId) AS ActiveSessionCount
    FROM dbo.AdminUsers u
    LEFT JOIN dbo.AdminRoles r ON r.RoleId = u.RoleId
    WHERE u.IsActive = 1 OR @IncludeInactive = 1
    ORDER BY u.Username;
END
GO

-- One operator by username, regardless of active state, so operations that only
-- need a single account's address/confirmation state (e.g. re-sending an email
-- confirmation) do not have to list every operator. Deliberately selects the same
-- columns as usp_Admin_Operators_GetAll so AdminContentRowMapper.MapOperator reads
-- it unchanged.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_Operator_GetByUsername
    @Username NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT u.AdminUserId,
           u.Username,
           u.RoleId,
           r.Name AS RoleName,
           u.IsActive,
           u.LastLoginAtUtc,
           u.CreatedAtUtc,
           u.Email,
           u.EmailConfirmedAtUtc,
           (SELECT COUNT(*) FROM dbo.AdminSessions s WHERE s.AdminUserId = u.AdminUserId) AS ActiveSessionCount
    FROM dbo.AdminUsers u
    LEFT JOIN dbo.AdminRoles r ON r.RoleId = u.RoleId
    WHERE u.Username = LTRIM(RTRIM(@Username));
END
GO

-- Creates a brand-new operator from the dashboard (operators.manage). Deliberately
-- separate from usp_Admin_UpsertAccount: that procedure is the provisioning CLI's
-- rotate-or-create tool and will happily overwrite an existing username's
-- credentials, which is exactly the wrong behavior for an HTTP endpoint an
-- authenticated operator can call - a typo'd "existing" username must never
-- silently reset someone else's password and kill their sessions. This procedure
-- only ever inserts, and refuses (Conflict) if the username is already taken.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_Operator_Create
    @Username NVARCHAR(100),
    @PasswordHash VARBINARY(256),
    @PasswordSalt VARBINARY(128),
    @TotpSecretCipher VARBINARY(256),
    -- Stored unconfirmed (EmailConfirmedAtUtc stays NULL) until the operator
    -- clicks the link in their confirmation email - see usp_Admin_Operator_ConfirmEmail.
    @Email NVARCHAR(256) = NULL,
    @RoleName NVARCHAR(64) = NULL,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Username = LTRIM(RTRIM(@Username));
    SET @RoleName = NULLIF(LTRIM(RTRIM(@RoleName)), N'');
    SET @Email = NULLIF(LTRIM(RTRIM(@Email)), N'');

    DECLARE @RoleId UNIQUEIDENTIFIER;

    BEGIN TRANSACTION;

    IF @Username IS NULL OR @Username = N''
    BEGIN
        COMMIT TRANSACTION;
        SELECT 3 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId, N'A username is required.' AS Detail;
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM dbo.AdminUsers WHERE Username = @Username)
    BEGIN
        COMMIT TRANSACTION;
        SELECT 2 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId,
               N'An operator named ''' + @Username + N''' already exists.' AS Detail;
        RETURN;
    END

    IF @RoleName IS NOT NULL
    BEGIN
        SELECT @RoleId = RoleId FROM dbo.AdminRoles WHERE Name = @RoleName;

        IF @RoleId IS NULL
        BEGIN
            COMMIT TRANSACTION;
            SELECT 1 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId,
                   N'No role named ''' + @RoleName + N'''.' AS Detail;
            RETURN;
        END
    END

    DECLARE @AdminUserId UNIQUEIDENTIFIER = NEWID();

    INSERT INTO dbo.AdminUsers (AdminUserId, Username, PasswordHash, PasswordSalt, TotpSecretCipher, Email, RoleId)
    VALUES (@AdminUserId, @Username, @PasswordHash, @PasswordSalt, @TotpSecretCipher, @Email, @RoleId);

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'Create', N'AdminOperator', CONVERT(NVARCHAR(64), @AdminUserId),
            N'Created operator ''' + @Username + N''' with role ''' + ISNULL(@RoleName, N'none') + N'''', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @AdminUserId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Moving an operator between roles also drops their live sessions: privilege is
-- re-read per request so the change is immediate anyway, but a demotion should not
-- leave a console tab sitting mid-edit holding a page it can no longer save.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_Operator_SetRole
    @Username NVARCHAR(100),
    @RoleName NVARCHAR(64),
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Username = LTRIM(RTRIM(@Username));
    SET @RoleName = LTRIM(RTRIM(@RoleName));

    DECLARE @AdminUserId UNIQUEIDENTIFIER;
    DECLARE @RoleId UNIQUEIDENTIFIER;
    DECLARE @CurrentRoleName NVARCHAR(64);

    BEGIN TRANSACTION;

    SELECT @AdminUserId = AdminUserId, @CurrentRoleName = r.Name
    FROM dbo.AdminUsers u
    LEFT JOIN dbo.AdminRoles r ON r.RoleId = u.RoleId
    WHERE u.Username = @Username;

    IF @AdminUserId IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId,
               N'No operator named ''' + @Username + N'''.' AS Detail;
        RETURN;
    END

    SELECT @RoleId = RoleId FROM dbo.AdminRoles WHERE Name = @RoleName;

    IF @RoleId IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, @AdminUserId AS EntityId,
               N'No role named ''' + @RoleName + N'''.' AS Detail;
        RETURN;
    END

    UPDATE dbo.AdminUsers SET RoleId = @RoleId WHERE AdminUserId = @AdminUserId;

    DELETE FROM dbo.AdminSessions WHERE AdminUserId = @AdminUserId;

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, N'AssignRole', N'AdminOperator', CONVERT(NVARCHAR(64), @AdminUserId),
            N'Moved operator ''' + @Username + N''' from role ''' + ISNULL(@CurrentRoleName, N'none') + N''' to ''' + @RoleName
            + N''' (sessions revoked)', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @AdminUserId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Deactivating is the supported way to retire an operator: the row (and its trail)
-- stays, but every session dies immediately and sign-in stops working.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_Operator_SetActive
    @Username NVARCHAR(100),
    @IsActive BIT,
    @ActorAdminUserId UNIQUEIDENTIFIER = NULL,
    @ActorUsername NVARCHAR(100),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SET @Username = LTRIM(RTRIM(@Username));

    DECLARE @AdminUserId UNIQUEIDENTIFIER;

    BEGIN TRANSACTION;

    SELECT @AdminUserId = AdminUserId FROM dbo.AdminUsers WHERE Username = @Username;

    IF @AdminUserId IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId,
               N'No operator named ''' + @Username + N'''.' AS Detail;
        RETURN;
    END

    UPDATE dbo.AdminUsers SET IsActive = @IsActive WHERE AdminUserId = @AdminUserId;

    IF @IsActive = 0
    BEGIN
        DELETE FROM dbo.AdminSessions WHERE AdminUserId = @AdminUserId;
    END

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@ActorAdminUserId, @ActorUsername, CASE WHEN @IsActive = 1 THEN N'Activate' ELSE N'Deactivate' END,
            N'AdminOperator', CONVERT(NVARCHAR(64), @AdminUserId),
            CASE WHEN @IsActive = 1
                 THEN N'Activated operator ''' + @Username + N''''
                 ELSE N'Deactivated operator ''' + @Username + N''' (sessions revoked)' END,
            @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @AdminUserId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Confirms the email an operator was created with, reached by clicking the link
-- in the confirmation email (see AdminRbacService.ConfirmOperatorEmailAsync).
-- Deliberately not gated by a permission or actor lookup the way the rest of
-- this file is: the caller has no session yet, and the possession of a valid,
-- unexpired token (verified by the service before this ever runs) *is* the
-- authorization. @Email is re-checked against the row rather than trusted, so a
-- stale link from before the address was changed can never confirm the new one.
-- Confirming an already-confirmed address is treated as success, not an error -
-- clicking the link twice should never look like a failure.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_Operator_ConfirmEmail
    @AdminUserId UNIQUEIDENTIFIER,
    @Email NVARCHAR(256),
    @ActorIp NVARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Username NVARCHAR(100);
    DECLARE @AlreadyConfirmed BIT;

    BEGIN TRANSACTION;

    SELECT @Username = Username, @AlreadyConfirmed = CASE WHEN EmailConfirmedAtUtc IS NOT NULL THEN 1 ELSE 0 END
    FROM dbo.AdminUsers
    WHERE AdminUserId = @AdminUserId AND Email = @Email;

    IF @Username IS NULL
    BEGIN
        COMMIT TRANSACTION;
        SELECT 1 AS Outcome, CAST(NULL AS UNIQUEIDENTIFIER) AS EntityId,
               N'This confirmation link no longer matches an operator on file.' AS Detail;
        RETURN;
    END

    IF @AlreadyConfirmed = 1
    BEGIN
        COMMIT TRANSACTION;
        SELECT 0 AS Outcome, @AdminUserId AS EntityId, N'Email already confirmed.' AS Detail;
        RETURN;
    END

    UPDATE dbo.AdminUsers SET EmailConfirmedAtUtc = SYSUTCDATETIME() WHERE AdminUserId = @AdminUserId;

    INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
    VALUES (@AdminUserId, @Username, N'ConfirmEmail', N'AdminOperator', CONVERT(NVARCHAR(64), @AdminUserId),
            N'Confirmed email for ''' + @Username + N'''', @ActorIp);

    COMMIT TRANSACTION;

    SELECT 0 AS Outcome, @AdminUserId AS EntityId, CAST(NULL AS NVARCHAR(200)) AS Detail;
END
GO

-- Newest first. The cap is enforced here rather than by the caller so no request
-- can ask for the whole table.
CREATE OR ALTER PROCEDURE dbo.usp_Admin_Audit_GetRecent
    @Limit INT = 50
AS
BEGIN
    SET NOCOUNT ON;

    IF @Limit IS NULL OR @Limit < 1 SET @Limit = 50;
    IF @Limit > 200 SET @Limit = 200;

    SELECT TOP (@Limit)
           AuditId,
           AdminUserId,
           Username,
           Action,
           EntityType,
           EntityId,
           Summary,
           CreatedFromIp,
           CreatedAtUtc
    FROM dbo.AdminAuditLog
    ORDER BY CreatedAtUtc DESC, AuditId DESC;
END
GO
