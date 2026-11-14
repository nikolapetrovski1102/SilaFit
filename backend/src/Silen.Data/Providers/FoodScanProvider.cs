using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="IFoodScanProvider"/>
public sealed class FoodScanProvider(ISqlExecutor sqlExecutor) : IFoodScanProvider
{
    public Task<FoodScanReservationModel> TryReserveAsync(
        Guid userId, string kind, bool isTrial, DateTime dayStartUtc, int dailyLimit, int trialLimit,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_FoodScan_TryReserve",
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
                r => new FoodScanReservationModel
                {
                    Allowed = r.GetBoolean(r.GetOrdinal("Allowed")),
                    Used = r.GetInt32(r.GetOrdinal("Used")),
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

    public Task<FoodScanUsageModel> GetUsageAsync(Guid userId, DateTime dayStartUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_FoodScan_Usage",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@DayStartUtc", dayStartUtc)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(
                reader,
                r => new FoodScanUsageModel
                {
                    MealToday = r.GetInt32(r.GetOrdinal("MealToday")),
                    BarcodeTrialUsed = r.GetInt32(r.GetOrdinal("BarcodeTrialUsed"))
                },
                cancellationToken),
            cancellationToken);
}
