using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="ILinkScanProvider"/>
public sealed class LinkScanProvider(ISqlExecutor sqlExecutor) : ILinkScanProvider
{
    public Task<LinkScanReservationModel> TryReserveAsync(
        Guid userId, string kind, bool isTrial, DateTime dayStartUtc, int dailyLimit, int trialLimit,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_LinkScan_TryReserve",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@Kind", kind),
                SqlParameterBuilder.Create("@IsTrial", isTrial),
                SqlParameterBuilder.Create("@DayStartUtc", dayStartUtc),
                SqlParameterBuilder.Create("@DailyLimit", dailyLimit),
                SqlParameterBuilder.Create("@TrialLimit", trialLimit)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(
                reader,
                r => new LinkScanReservationModel
                {
                    Allowed = r.GetBoolean(r.GetOrdinal("Allowed")),
                    Used = r.GetInt32(r.GetOrdinal("Used")),
                    LinkScanId = r.IsDBNull(r.GetOrdinal("LinkScanId")) ? null : r.GetInt64(r.GetOrdinal("LinkScanId"))
                },
                cancellationToken),
            cancellationToken);

    public Task ReleaseAsync(Guid userId, long linkScanId, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_LinkScan_Release",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@LinkScanId", linkScanId)
            ],
            cancellationToken);

    public Task<LinkScanUsageModel> GetUsageAsync(Guid userId, DateTime dayStartUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_LinkScan_Usage",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@DayStartUtc", dayStartUtc)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(
                reader,
                r => new LinkScanUsageModel
                {
                    WorkoutToday = r.GetInt32(r.GetOrdinal("WorkoutToday")),
                    MealToday = r.GetInt32(r.GetOrdinal("MealToday")),
                    TrialUsed = r.GetInt32(r.GetOrdinal("TrialUsed"))
                },
                cancellationToken),
            cancellationToken);

    public Task<string?> GetCachedAsync(string provider, string videoId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_LinkScanCache_Get",
            [
                SqlParameterBuilder.Create("@Provider", provider),
                SqlParameterBuilder.Create("@VideoId", videoId)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(
                reader, r => r.GetString(r.GetOrdinal("ResultJson")), cancellationToken),
            cancellationToken);

    public Task PutCachedAsync(string provider, string videoId, string resultJson, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_LinkScanCache_Put",
            [
                SqlParameterBuilder.Create("@Provider", provider),
                SqlParameterBuilder.Create("@VideoId", videoId),
                SqlParameterBuilder.Create("@ResultJson", resultJson)
            ],
            cancellationToken);
}
