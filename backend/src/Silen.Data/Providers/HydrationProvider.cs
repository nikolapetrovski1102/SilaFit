using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class HydrationProvider(ISqlExecutor sqlExecutor) : IHydrationProvider
{
    public Task<int> LogAsync(Guid userId, short amountMl, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Hydration_Log",
            [SqlParameterBuilder.Create("@UserId", userId), SqlParameterBuilder.Create("@AmountMl", amountMl)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, r => r.GetInt32Value("TotalMlToday"), cancellationToken),
            cancellationToken);

    public Task<int> GetTodayTotalAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Hydration_GetToday",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, r => r.GetInt32Value("TotalMlToday"), cancellationToken),
            cancellationToken);
}
