using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Data.Helpers;

namespace Silen.Data.Providers;

public sealed class PartnerLeadsProvider(ISqlExecutor sqlExecutor) : IPartnerLeadsProvider
{
    public Task<PartnerLeadOutcomeModel?> ProvisionAsync(
        string partnerUserId, string email, string? displayName, string signupProvider,
        DateTime issuedAtUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_PartnerLead_Provision",
            [
                SqlParameterBuilder.Create("@PartnerUserId", partnerUserId),
                SqlParameterBuilder.Create("@Email", email),
                SqlParameterBuilder.Create("@DisplayName", displayName),
                SqlParameterBuilder.Create("@SignupProvider", signupProvider),
                SqlParameterBuilder.Create("@IssuedAtUtc", issuedAtUtc)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, PartnerLeadRowMapper.MapOutcome, cancellationToken),
            cancellationToken);

    public Task<PartnerLeadOutcomeModel?> CancelAsync(
        string partnerUserId, DateTime issuedAtUtc, CancellationToken cancellationToken = default) =>
        sqlExecutor.QueryAsync(
            "dbo.usp_PartnerLead_Cancel",
            [
                SqlParameterBuilder.Create("@PartnerUserId", partnerUserId),
                SqlParameterBuilder.Create("@IssuedAtUtc", issuedAtUtc)
            ],
            reader => SqlResultSetReader.ReadSingleOrDefaultAsync(reader, PartnerLeadRowMapper.MapOutcome, cancellationToken),
            cancellationToken);
}
