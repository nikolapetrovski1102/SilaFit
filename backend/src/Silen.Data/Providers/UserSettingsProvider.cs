using Silen.Common.Dtos;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class UserSettingsProvider(ISqlExecutor sqlExecutor) : IUserSettingsProvider
{
    public Task<UserSettingsModel?> GetAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserSettings_Get",
            [SqlParameterBuilder.Create("@UserId", userId)],
            async reader => await reader.ReadAsync(cancellationToken) ? SettingsRowMapper.MapSettings(reader) : null,
            cancellationToken);

    public Task SetNotificationsEnabledAsync(Guid userId, bool enabled, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_UserSettings_SetNotificationsEnabled",
            [SqlParameterBuilder.Create("@UserId", userId), SqlParameterBuilder.Create("@NotificationsEnabled", enabled)],
            cancellationToken);

    public Task<UserSettingsModel?> SetAiDataConsentAsync(Guid userId, bool granted, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserSettings_SetAiDataConsent",
            [SqlParameterBuilder.Create("@UserId", userId), SqlParameterBuilder.Create("@Granted", granted)],
            async reader => await reader.ReadAsync(cancellationToken) ? SettingsRowMapper.MapSettings(reader) : null,
            cancellationToken);

    public Task<UserSettingsModel?> UpdateAsync(Guid userId, UpdateUserSettingsRequest request, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserSettings_Update",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@TargetWaterMl", request.TargetWaterMl),
                SqlParameterBuilder.Create("@NotificationsEnabled", request.NotificationsEnabled),
                SqlParameterBuilder.Create("@NotificationLocalTime", request.NotificationLocalTime),
                SqlParameterBuilder.Create("@TimeZoneId", request.TimeZoneId),
                SqlParameterBuilder.Create("@WeightUnit", request.WeightUnit),
                SqlParameterBuilder.Create("@DistanceUnit", request.DistanceUnit),
                SqlParameterBuilder.Create("@RestTimerSoundEnabled", request.RestTimerSoundEnabled),
                SqlParameterBuilder.Create("@BarbellStandardKg", request.BarbellStandardKg),
                SqlParameterBuilder.Create("@AppearanceMode", request.AppearanceMode),
                SqlParameterBuilder.Create("@AvatarChoice", request.AvatarChoice)
            ],
            async reader => await reader.ReadAsync(cancellationToken) ? SettingsRowMapper.MapSettings(reader) : null,
            cancellationToken);
}
