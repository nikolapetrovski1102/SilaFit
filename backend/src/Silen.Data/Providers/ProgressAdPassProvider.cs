using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class ProgressAdPassProvider(ISqlExecutor sqlExecutor) : IProgressAdPassProvider
{
    public Task<ProgressAdPassGrantModel> GrantAsync(Guid userId, int validMinutes, int dailyLimit, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_ProgressAdPass_Grant",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@ValidMinutes", validMinutes),
                SqlParameterBuilder.Create("@DailyLimit", dailyLimit)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, r => new ProgressAdPassGrantModel
            {
                Status = r.GetStringValue("Status"),
                ExpiresAtUtc = r.GetNullableDateTime("ExpiresAtUtc")
            }, cancellationToken),
            cancellationToken);

    public Task<bool> HasActiveAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_ProgressAdPass_HasActive",
            [SqlParameterBuilder.Create("@UserId", userId)],
            reader => SqlResultSetReader.ReadScalarRowAsync(reader, r => r.GetBoolValue("HasActivePass"), cancellationToken),
            cancellationToken);

    public Task EndAsync(Guid userId, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_ProgressAdPass_End",
            [SqlParameterBuilder.Create("@UserId", userId)],
            cancellationToken);
}
