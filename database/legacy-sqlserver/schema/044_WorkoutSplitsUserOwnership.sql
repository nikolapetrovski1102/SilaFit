USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- =============================================================================
-- User-owned splits: an app user building their own custom split, alongside the
-- existing trainer-owned axis from 031_SplitTrainerSharing.sql.
--
-- OwnerUserId          who built the split from inside the app (NULL = not a
--                       user-built split - system content or a trainer's).
-- CK_WorkoutSplits_OwnerAxis  a split has at most one owner: an admin/trainer via
--                       the console, or a regular user via the app builder, never
--                       both.
--
-- A user-owned split still flows through the same WorkoutSplits/SplitDays/
-- SplitDayExercises tables and the same app-facing read procedures
-- (procedures/Splits.sql) as every other split - only the ownership/visibility
-- predicate changes (see 1c below). The write side lives in a new
-- procedures/UserSplits.sql, mirroring AdminSplits.sql but with the ownership
-- check pinned to @UserId instead of an admin actor.
-- =============================================================================

IF COL_LENGTH(N'dbo.WorkoutSplits', N'OwnerUserId') IS NULL
BEGIN
    ALTER TABLE dbo.WorkoutSplits ADD OwnerUserId UNIQUEIDENTIFIER NULL;
END
GO

-- No ON DELETE cascade/set-null: SplitDays/SplitDayExercises have plain,
-- non-cascading FKs to WorkoutSplits, so cascading here could delete a
-- WorkoutSplits row and orphan them. Cleanup instead happens explicitly in
-- usp_Account_Delete, in dependency order, before the Users row is removed.
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_WorkoutSplits_Users')
BEGIN
    ALTER TABLE dbo.WorkoutSplits ADD CONSTRAINT FK_WorkoutSplits_Users
        FOREIGN KEY (OwnerUserId) REFERENCES dbo.Users(UserId);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_WorkoutSplits_OwnerUserId')
BEGIN
    CREATE INDEX IX_WorkoutSplits_OwnerUserId ON dbo.WorkoutSplits(OwnerUserId);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_WorkoutSplits_OwnerAxis')
BEGIN
    ALTER TABLE dbo.WorkoutSplits ADD CONSTRAINT CK_WorkoutSplits_OwnerAxis
        CHECK (OwnerAdminUserId IS NULL OR OwnerUserId IS NULL);
END
GO

-- Widen the category taxonomy once more so a self-built split isn't forced
-- into one of the curated archetypes.
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_WorkoutSplits_Category')
BEGIN
    ALTER TABLE dbo.WorkoutSplits DROP CONSTRAINT CK_WorkoutSplits_Category;
END
GO

ALTER TABLE dbo.WorkoutSplits
    ADD CONSTRAINT CK_WorkoutSplits_Category CHECK (Category IN (
        'PushPullLegs', 'UpperLower', 'FullBody', 'ArnoldSplit',
        'PHUL', 'PHAT', 'BroSplit', 'Circuit', 'Powerlifting',
        'Calisthenics', 'GluteFocus', 'Custom'
    ));
GO

-- usp_Account_Delete (procedures/Account.sql) is extended separately to clean
-- up a user's owned-split tree before the Users row is removed.
