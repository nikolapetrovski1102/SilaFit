namespace Silen.Services.Abstractions;

/// <summary>Reusable Pro/Advanced entitlement checks, with a dev-only override (FeatureFlags:DevTiersFree)
/// so gated features can be exercised locally without a real purchase.</summary>
public interface ISubscriptionGate
{
    /// <summary>True for an active PRO or ADVANCED subscriber (the monthly AI overview and
    /// every other feature the Pro tier includes).</summary>
    Task<bool> HasActiveProAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>True only for an active ADVANCED subscriber - the weekly AI overview and the
    /// meal/split recommendations review are exclusive to the top tier.</summary>
    Task<bool> HasActiveAdvancedAsync(Guid userId, CancellationToken cancellationToken = default);
}
