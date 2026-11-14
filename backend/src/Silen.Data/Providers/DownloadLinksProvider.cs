using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

/// <inheritdoc cref="IDownloadLinksProvider"/>
public sealed class DownloadLinksProvider(ISqlExecutor sqlExecutor) : IDownloadLinksProvider
{
    public Task RecordVisitAsync(
        string? sourceCode, Guid? visitorId, string platform, string? deviceLabel, byte[]? ipHash,
        int retainHashHours, CancellationToken cancellationToken = default) =>
        sqlExecutor.ExecuteAsync(
            "dbo.usp_Download_RecordVisit",
            [
                SqlParameterBuilder.Create("@SourceCode", sourceCode),
                SqlParameterBuilder.Create("@VisitorId", visitorId),
                SqlParameterBuilder.Create("@Platform", platform),
                SqlParameterBuilder.Create("@DeviceLabel", deviceLabel),
                SqlParameterBuilder.Create("@IpHash", ipHash),
                SqlParameterBuilder.Create("@RetainHashHours", retainHashHours)
            ],
            cancellationToken);

    public Task<(bool Matched, string? SourceCode)> ClaimInstallAsync(
        Guid userId, byte[] ipHash, string? platform, int windowHours, int maxAccountAgeMinutes,
        CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Download_ClaimInstall",
            [
                SqlParameterBuilder.Create("@UserId", userId),
                SqlParameterBuilder.Create("@IpHash", ipHash),
                SqlParameterBuilder.Create("@Platform", platform),
                SqlParameterBuilder.Create("@WindowHours", windowHours),
                SqlParameterBuilder.Create("@MaxAccountAgeMinutes", maxAccountAgeMinutes)
            ],
            reader => SqlResultSetReader.ReadScalarRowAsync(
                reader,
                r => (r.GetBoolValue("Matched"), r.GetNullableString("SourceCode")),
                cancellationToken),
            cancellationToken);

    public Task<DownloadLinkReportModel> GetReportAsync(DateTime? fromUtc, int leadLimit, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_Download_Report",
            [
                SqlParameterBuilder.Create("@FromUtc", fromUtc),
                SqlParameterBuilder.Create("@LeadLimit", leadLimit)
            ],
            async reader =>
            {
                var model = new DownloadLinkReportModel { FromUtc = fromUtc };

                model.Sources = await SqlResultSetReader.ReadListAsync(reader, r => new DownloadSourceStatsModel
                {
                    SourceCode = r.GetNullableString("SourceCode"),
                    Label = r.GetStringValue("Label"),
                    Channel = r.GetStringValue("Channel"),
                    IsActive = r.GetBoolValue("IsActive"),
                    Opens = r.GetInt32Value("Opens"),
                    UniqueDevices = r.GetInt32Value("UniqueDevices"),
                    IosOpens = r.GetInt32Value("IosOpens"),
                    AndroidOpens = r.GetInt32Value("AndroidOpens"),
                    DesktopOpens = r.GetInt32Value("DesktopOpens"),
                    LastVisitAtUtc = r.GetNullableDateTime("LastVisitAtUtc"),
                    Installs = r.GetInt32Value("Installs"),
                    SignedUp = r.GetInt32Value("SignedUp"),
                    Purchased = r.GetInt32Value("Purchased"),
                    PayingNow = r.GetInt32Value("PayingNow")
                }, cancellationToken);

                if (await reader.NextResultAsync(cancellationToken))
                {
                    model.Leads = await SqlResultSetReader.ReadListAsync(reader, r => new DownloadLeadModel
                    {
                        SourceCode = r.GetNullableString("SourceCode"),
                        SourceLabel = r.GetStringValue("SourceLabel"),
                        Platform = r.GetStringValue("Platform"),
                        DeviceLabel = r.GetNullableString("DeviceLabel"),
                        VisitedAtUtc = r.GetDateTimeValue("VisitedAtUtc"),
                        InstalledAtUtc = r.GetDateTimeValue("InstalledAtUtc"),
                        UserId = r.GetGuidValue("UserId"),
                        DisplayName = r.GetNullableString("DisplayName"),
                        Email = r.GetNullableString("Email"),
                        AccountTier = r.GetStringValue("AccountTier"),
                        Purchased = r.GetBoolValue("Purchased"),
                        PayingNow = r.GetBoolValue("PayingNow"),
                        ActivePlanCode = r.GetNullableString("ActivePlanCode")
                    }, cancellationToken);
                }

                return model;
            },
            cancellationToken);
}
