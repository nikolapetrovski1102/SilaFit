using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class MonthlyReviewProvider(ISqlExecutor sqlExecutor) : IMonthlyReviewProvider
{
    public Task<MonthlyReviewRunModel> StartRunAsync(
        int periodYear, int periodMonth, string planCode, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_MonthlyReview_StartRun",
            [
                SqlParameterBuilder.Create("@PeriodYear", (short)periodYear),
                SqlParameterBuilder.Create("@PeriodMonth", (byte)periodMonth),
                SqlParameterBuilder.Create("@PlanCode", planCode)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, MonthlyReviewRowMapper.MapRun, cancellationToken),
            cancellationToken);

    public Task CompleteRunAsync(
        Guid runId, string status, int usersConsidered, int reportsGenerated, int emailsSent, int failures,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_MonthlyReview_CompleteRun",
            [
                SqlParameterBuilder.Create("@RunId", runId),
                SqlParameterBuilder.Create("@Status", status),
                SqlParameterBuilder.Create("@UsersConsidered", usersConsidered),
                SqlParameterBuilder.Create("@ReportsGenerated", reportsGenerated),
                SqlParameterBuilder.Create("@EmailsSent", emailsSent),
                SqlParameterBuilder.Create("@Failures", failures)
            ],
            cancellationToken);

    public Task<HashSet<Guid>> GetEmailedUserIdsAsync(
        int periodYear, int periodMonth, string deliveryKind, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_MonthlyReview_GetEmailedUserIds",
            [
                SqlParameterBuilder.Create("@PeriodYear", (short)periodYear),
                SqlParameterBuilder.Create("@PeriodMonth", (byte)periodMonth),
                SqlParameterBuilder.Create("@DeliveryKind", deliveryKind)
            ],
            async reader =>
            {
                var userIds = await SqlResultSetReader.ReadListAsync(
                    reader, r => r.GetGuidValue("UserId"), cancellationToken);
                return userIds.ToHashSet();
            },
            cancellationToken);

    public Task RecordDeliveryAsync(MonthlyReviewDeliveryModel delivery, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_MonthlyReview_RecordDelivery",
            [
                SqlParameterBuilder.Create("@RunId", delivery.RunId),
                SqlParameterBuilder.Create("@UserId", delivery.UserId),
                SqlParameterBuilder.Create("@PeriodYear", (short)delivery.PeriodYear),
                SqlParameterBuilder.Create("@PeriodMonth", (byte)delivery.PeriodMonth),
                SqlParameterBuilder.Create("@Status", delivery.Status),
                SqlParameterBuilder.Create("@ErrorMessage", delivery.ErrorMessage),
                SqlParameterBuilder.Create("@GeneratedAtUtc", delivery.GeneratedAtUtc),
                SqlParameterBuilder.Create("@EmailedAtUtc", delivery.EmailedAtUtc),
                SqlParameterBuilder.Create("@DeliveryKind", delivery.DeliveryKind)
            ],
            cancellationToken);
}
