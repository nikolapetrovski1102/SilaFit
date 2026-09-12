using Microsoft.Data.SqlClient;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>
/// Outside helper that maps AdminUsers / AdminSessions rows to their models.
/// Kept out of AdminProvider itself per architecture rule: no private methods
/// inside Provider/Service implementation classes.
/// </summary>
public static class AdminRowMapper
{
    public static AdminAccountModel MapAccount(SqlDataReader reader) => new()
    {
        AdminUserId = reader.GetGuidValue("AdminUserId"),
        Username = reader.GetStringValue("Username"),
        PasswordHash = reader.GetNullableBytes("PasswordHash") ?? [],
        PasswordSalt = reader.GetNullableBytes("PasswordSalt") ?? [],
        TotpSecretCipher = reader.GetNullableBytes("TotpSecretCipher") ?? [],
        FailedAttemptCount = reader.GetInt32Value("FailedAttemptCount"),
        LockedUntilUtc = reader.GetNullableDateTime("LockedUntilUtc"),
        LastLoginAtUtc = reader.GetNullableDateTime("LastLoginAtUtc"),
        PasswordChangedAtUtc = reader.GetDateTimeValue("PasswordChangedAtUtc"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
        IsActive = reader.GetBoolValue("IsActive"),
        RoleId = reader.GetNullableGuid("RoleId"),
        RoleName = reader.GetNullableString("RoleName")
    };

    public static AdminLockoutStateModel MapLockoutState(SqlDataReader reader) => new()
    {
        FailedAttemptCount = reader.GetInt32Value("FailedAttemptCount"),
        LockedUntilUtc = reader.GetNullableDateTime("LockedUntilUtc")
    };

    public static AdminSessionModel MapSession(SqlDataReader reader) => new()
    {
        AdminSessionId = reader.GetGuidValue("AdminSessionId"),
        AdminUserId = reader.GetGuidValue("AdminUserId"),
        Username = reader.GetStringValue("Username"),
        ExpiresAtUtc = reader.GetDateTimeValue("ExpiresAtUtc"),
        AbsoluteExpiresAtUtc = reader.GetDateTimeValue("AbsoluteExpiresAtUtc"),
        LastSeenAtUtc = reader.GetDateTimeValue("LastSeenAtUtc")
    };
}
