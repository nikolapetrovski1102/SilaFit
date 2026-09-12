namespace Silen.Services.Abstractions;

/// <summary>Reusable Pro/Advanced entitlement check, with a dev-only override (FeatureFlags:DevTiersFree)
/// so Pro-gated features can be exercised locally without a real purchase.</summary>
public interface ISubscriptionGate
{
    Task<bool> HasActiveProAsync(Guid userId, CancellationToken cancellationToken = default);
}
