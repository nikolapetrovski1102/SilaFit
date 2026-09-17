using Microsoft.Extensions.Configuration;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="ISubscriptionGate"/>
public sealed class SubscriptionGate(IPlansProvider plansProvider, IConfiguration configuration) : ISubscriptionGate
{
    private static readonly HashSet<string> ProPlanCodes = new(StringComparer.OrdinalIgnoreCase) { "PRO", "ADVANCED" };
    private static readonly HashSet<string> AdvancedPlanCodes = new(StringComparer.OrdinalIgnoreCase) { "ADVANCED" };

    // Free tier has no UserSubscriptions row and therefore no PlanId to hang a
    // PlanEntitlements row off - these conservative constants stand in for it
    // until Free becomes a real, admin-editable plan row.
    private static readonly PlanEntitlementsModel FreeTierDefaults = new()
    {
        MaxActiveSplits = 1,
        MaxActiveDietPlans = 1,
        AllowAiGeneration = false
    };

    private static readonly PlanEntitlementsModel UnlimitedEntitlements = new()
    {
        MaxActiveSplits = null,
        MaxActiveDietPlans = null,
        AllowAiGeneration = true
    };

    public Task<bool> HasActiveProAsync(Guid userId, CancellationToken cancellationToken = default) =>
        HasActivePlanAsync(userId, ProPlanCodes, cancellationToken);

    public Task<bool> HasActiveAdvancedAsync(Guid userId, CancellationToken cancellationToken = default) =>
        HasActivePlanAsync(userId, AdvancedPlanCodes, cancellationToken);

    public async Task<PlanEntitlementsModel> GetEntitlementsAsync(Guid userId, CancellationToken cancellationToken = default)
    {
        if (configuration.GetValue("FeatureFlags:DevTiersFree", false))
        {
            return UnlimitedEntitlements;
        }

        var entitlements = await plansProvider.GetEntitlementsForUserAsync(userId, cancellationToken).ConfigureAwait(false);
        return entitlements ?? FreeTierDefaults;
    }

    private async Task<bool> HasActivePlanAsync(
        Guid userId, HashSet<string> allowedPlanCodes, CancellationToken cancellationToken)
    {
        // Dev-only escape hatch: every tier behaves as if the highest plan is active so gated
        // features can be exercised locally without a real purchase. Committed appsettings.json
        // defaults this to false - only appsettings.Development.json turns it on.
        if (configuration.GetValue("FeatureFlags:DevTiersFree", false))
        {
            return true;
        }

        var subscription = await plansProvider.GetActiveAsync(userId, cancellationToken).ConfigureAwait(false);
        return subscription is not null
            && string.Equals(subscription.Status, "Active", StringComparison.OrdinalIgnoreCase)
            && (subscription.ExpiresAtUtc is null || subscription.ExpiresAtUtc > DateTime.UtcNow)
            && subscription.PlanCode is not null
            && allowedPlanCodes.Contains(subscription.PlanCode);
    }
}
