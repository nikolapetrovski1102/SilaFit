using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class SplitsProvider(ISqlExecutor sqlExecutor) : ISplitsProvider
{
    public Task<List<WorkoutSplitModel>> GetAllAsync(Guid? userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Splits_GetAll",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapSplit, cancellationToken),
            cancellationToken);

    public Task<(WorkoutSplitModel? Split, List<SplitDayModel> Days, List<SplitDayExerciseModel> Exercises)> GetDetailAsync(
        Guid splitId, Guid? userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Splits_GetDetail",
            [SqlParameterBuilder.Create("@SplitId", splitId), SqlParameterBuilder.Create("@UserId", userId)],
            async reader =>
            {
                var split = await SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapSplit, cancellationToken);
                await reader.NextResultAsync(cancellationToken);
                var days = await SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapSplitDay, cancellationToken);
                await reader.NextResultAsync(cancellationToken);
                var exercises = await SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapSplitDayExercise, cancellationToken);
                return (split, days, exercises);
            },
            cancellationToken);

    public Task<ActiveSplitModel?> SetActiveAsync(Guid userId, Guid splitId, bool isAutoAssigned = false, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserActiveSplit_Set",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@SplitId", splitId),
                SqlParameterBuilder.Create("@IsAutoAssigned", isAutoAssigned)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapActiveSplit, cancellationToken),
            cancellationToken);

    public Task<ActiveSplitModel?> GetActiveAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_UserActiveSplit_Get",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, WorkoutRowMapper.MapActiveSplit, cancellationToken),
            cancellationToken);
}
