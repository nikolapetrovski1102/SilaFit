using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class WeeklyPlanGenerationProvider(ISqlExecutor sqlExecutor) : IWeeklyPlanGenerationProvider
{
    public Task<WeeklyAiPlanRunModel> StartRunAsync(DateTime weekStartUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_WeeklyAiPlan_StartRun",
            [SqlParameterBuilder.Create("@WeekStartUtc", weekStartUtc.Date)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, WeeklyAiPlanRowMapper.MapRun, cancellationToken),
            cancellationToken);

    public Task CompleteRunAsync(
        Guid runId, string status, int usersConsidered, int plansGenerated, int notificationsSent, int failures,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_WeeklyAiPlan_CompleteRun",
            [
                SqlParameterBuilder.Create("@RunId", runId),
                SqlParameterBuilder.Create("@Status", status),
                SqlParameterBuilder.Create("@UsersConsidered", usersConsidered),
                SqlParameterBuilder.Create("@PlansGenerated", plansGenerated),
                SqlParameterBuilder.Create("@NotificationsSent", notificationsSent),
                SqlParameterBuilder.Create("@Failures", failures)
            ],
            cancellationToken);

    public Task<HashSet<Guid>> GetProcessedUserIdsAsync(DateTime weekStartUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_WeeklyAiPlan_GetProcessedUserIds",
            [SqlParameterBuilder.Create("@WeekStartUtc", weekStartUtc.Date)],
            async reader =>
            {
                var userIds = await SqlResultSetReader.ReadListAsync(
                    reader, r => r.GetGuidValue("UserId"), cancellationToken);
                return userIds.ToHashSet();
            },
            cancellationToken);

    public Task RecordDeliveryAsync(WeeklyAiPlanDeliveryModel delivery, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_WeeklyAiPlan_RecordDelivery",
            [
                SqlParameterBuilder.Create("@RunId", delivery.RunId),
                SqlParameterBuilder.Create("@UserId", delivery.UserId),
                SqlParameterBuilder.Create("@WeekStartUtc", delivery.WeekStartUtc.Date),
                SqlParameterBuilder.Create("@SplitStatus", delivery.SplitStatus),
                SqlParameterBuilder.Create("@DietStatus", delivery.DietStatus),
                SqlParameterBuilder.Create("@SplitId", delivery.SplitId),
                SqlParameterBuilder.Create("@DietPlanId", delivery.DietPlanId),
                SqlParameterBuilder.Create("@ErrorMessage", delivery.ErrorMessage),
                SqlParameterBuilder.Create("@GeneratedAtUtc", delivery.GeneratedAtUtc),
                SqlParameterBuilder.Create("@NotifiedAtUtc", delivery.NotifiedAtUtc)
            ],
            cancellationToken);

    public Task<List<PlanSubscriberModel>> GetCandidateUsersAsync(CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_WeeklyAiPlan_GetCandidateUsers",
            [],
            reader => SqlResultSetReader.ReadListAsync(reader, WeeklyAiPlanRowMapper.MapCandidateUser, cancellationToken),
            cancellationToken);
}
