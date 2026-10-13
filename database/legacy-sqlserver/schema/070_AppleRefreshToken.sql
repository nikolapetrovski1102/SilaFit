USE SilenDb;
GO

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

-- Sign in with Apple refresh token (FieldCipher-encrypted), obtained by
-- exchanging the authorization code at login. Kept only so account deletion
-- can revoke the user's Apple token (App Review 5.1.1(v)). NULL for every
-- non-Apple identity and for Apple logins made before this column existed.
IF COL_LENGTH('dbo.UserAuthIdentities', 'RefreshTokenCiphertext') IS NULL
BEGIN
    ALTER TABLE dbo.UserAuthIdentities
        ADD RefreshTokenCiphertext VARBINARY(MAX) NULL;
END
GO
