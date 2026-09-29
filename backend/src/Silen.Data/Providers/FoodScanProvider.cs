using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="IFoodScanProvider"/>
public sealed class FoodScanProvider(ISqlExecutor sqlExecutor) : IFoodScanProvider
{
    public Task<FoodScanReservationModel> TryReserveAsync(
        Guid userId, DateTime dayStartUtc, int dailyLimit, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_FoodScan_TryReserve",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@DayStartUtc", dayStartUtc),
                SqlParameterBuilder.Create("@DailyLimit", dailyLimit)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(
                reader,
                r => new FoodScanReservationModel
                {
                    Allowed = r.GetBoolean(r.GetOrdinal("Allowed")),
                    UsedToday = r.GetInt32(r.GetOrdinal("UsedToday")),
                    FoodScanId = r.IsDBNull(r.GetOrdinal("FoodScanId")) ? null : r.GetInt64(r.GetOrdinal("FoodScanId"))
                },
                cancellationToken),
            cancellationToken);

    public Task ReleaseAsync(Guid userId, long foodScanId, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_FoodScan_Release",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@FoodScanId", foodScanId)
            ],
            cancellationToken);

    public Task<int> CountSinceAsync(Guid userId, DateTime dayStartUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_FoodScan_CountSince",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@DayStartUtc", dayStartUtc)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(
                reader, r => r.GetInt32(r.GetOrdinal("UsedToday")), cancellationToken),
            cancellationToken);
}
