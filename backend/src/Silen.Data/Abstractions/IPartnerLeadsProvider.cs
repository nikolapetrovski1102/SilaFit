using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>Leads handed over by the partner website, each with a partner-billed PRO grant.</summary>
public interface IPartnerLeadsProvider
{
    /// <summary>Creates or matches (by email) the lead's SilaFit account and grants PRO with no
    /// expiry. Never null in practice: the function always answers with one outcome row.</summary>
    Task<PartnerLeadOutcomeModel?> ProvisionAsync(
        string partnerUserId, string email, string? displayName, string signupProvider,
        DateTime issuedAtUtc, CancellationToken cancellationToken = default);

    /// <summary>Ends the lead's partner PRO grant immediately. Never null in practice.</summary>
    Task<PartnerLeadOutcomeModel?> CancelAsync(
        string partnerUserId, DateTime issuedAtUtc, CancellationToken cancellationToken = default);
}
