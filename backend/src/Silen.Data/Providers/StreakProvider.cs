using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class StreakProvider(ISqlExecutor sqlExecutor) : IStreakProvider
{
    public Task<(StreakStatusModel Status, List<WeekDayStatusModel> Week)> GetStatusAsync(
        Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Streak_GetStatus",
            [SqlParameterBuilder.Create("@UserId", userId)],
            async reader =>
            {
                var status = await SqlResultSetReader.ReadScalarRowAsync(reader, WorkoutRowMapper.MapStreakStatus, cancellationToken);
                await reader.NextResultAsync(cancellationToken);
                var week = await SqlResultSetReader.ReadListAsync(reader, WorkoutRowMapper.MapWeekDayStatus, cancellationToken);
                return (status, week);
            },
            cancellationToken);
}
