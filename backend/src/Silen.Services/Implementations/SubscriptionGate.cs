using Microsoft.Extensions.Configuration;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="ISubscriptionGate"/>
public sealed class SubscriptionGate(IPlansProvider plansProvider, IConfiguration configuration) : ISubscriptionGate
{
    private static readonly HashSet<string> ProPlanCodes = new(StringComparer.OrdinalIgnoreCase) { "PRO", "ADVANCED" };
    private static readonly HashSet<string> AdvancedPlanCodes = new(StringComparer.OrdinalIgnoreCase) { "ADVANCED" };

    public Task<bool> HasActiveProAsync(Guid userId, CancellationToken cancellationToken = default) =>
        HasActivePlanAsync(userId, ProPlanCodes, cancellationToken);

    public Task<bool> HasActiveAdvancedAsync(Guid userId, CancellationToken cancellationToken = default) =>
        HasActivePlanAsync(userId, AdvancedPlanCodes, cancellationToken);

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
