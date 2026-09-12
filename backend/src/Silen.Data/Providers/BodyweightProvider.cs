using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class BodyweightProvider(ISqlExecutor sqlExecutor) : IBodyweightProvider
{
    public Task<List<BodyweightEntryModel>> LogAsync(Guid userId, decimal weightKg, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Bodyweight_Log",
            [SqlParameterBuilder.Create("@UserId", userId), SqlParameterBuilder.Create("@WeightKg", weightKg)],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapBodyweightEntry, cancellationToken),
            cancellationToken);

    public Task<List<BodyweightEntryModel>> GetLatestAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Bodyweight_GetLatest",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapBodyweightEntry, cancellationToken),
            cancellationToken);
}
