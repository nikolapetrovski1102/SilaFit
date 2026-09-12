using Microsoft.Data.SqlClient;
using Silen.Common.Enums;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>
/// Outside helper that maps a Users-table row to <see cref="UserAccountModel"/>.
/// Kept out of AuthProvider itself per architecture rule: no private methods
/// inside Provider/Service implementation classes.
/// </summary>
public static class AuthRowMapper
{
    public static UserAccountModel MapAccount(SqlDataReader reader) => new()
    {
        UserId = reader.GetGuidValue("UserId"),
        DeviceId = reader.GetNullableString("DeviceId"),
        DisplayName = reader.GetNullableString("DisplayName"),
        Email = reader.GetNullableString("Email"),
        AccountTier = Enum.Parse<AccountTier>(reader.GetStringValue("AccountTier")),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc"),
        LastLoginAtUtc = reader.GetNullableDateTime("LastLoginAtUtc"),
        IsActive = reader.GetBoolValue("IsActive")
    };

    public static UserAccountModel MapAccountWithCredentials(SqlDataReader reader)
    {
        var account = MapAccount(reader);
        account.PasswordHash = reader.GetNullableBytes("PasswordHash");
        account.PasswordSalt = reader.GetNullableBytes("PasswordSalt");
        return account;
    }

    public static PendingEmailVerificationModel MapPendingVerification(SqlDataReader reader) => new()
    {
        PendingId = reader.GetGuidValue("PendingId"),
        ExistingUserId = reader.GetNullableGuid("ExistingUserId"),
        Email = reader.GetStringValue("Email"),
        PasswordHash = reader.GetNullableBytes("PasswordHash") ?? [],
        PasswordSalt = reader.GetNullableBytes("PasswordSalt") ?? [],
        DisplayName = reader.GetNullableString("DisplayName"),
        CodeHash = reader.GetNullableBytes("CodeHash") ?? [],
        CodeSalt = reader.GetNullableBytes("CodeSalt") ?? [],
        AttemptCount = reader.GetInt32Value("AttemptCount"),
        ExpiresAtUtc = reader.GetDateTimeValue("ExpiresAtUtc"),
        LastSentAtUtc = reader.GetDateTimeValue("LastSentAtUtc")
    };
}
