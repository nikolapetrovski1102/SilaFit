using Microsoft.Extensions.Configuration;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="ISubscriptionGate"/>
public sealed class SubscriptionGate(IPlansProvider plansProvider, IConfiguration configuration) : ISubscriptionGate
{
    private static readonly HashSet<string> ProPlanCodes = new(StringComparer.OrdinalIgnoreCase) { "PRO", "ADVANCED" };

    public async Task<bool> HasActiveProAsync(Guid userId, CancellationToken cancellationToken = default)
    {
        // Dev-only escape hatch: every tier behaves as if Pro is active so Pro-gated features can
        // be exercised locally without a real purchase. Committed appsettings.json defaults this
        // to false - only appsettings.Development.json turns it on.
        if (configuration.GetValue("FeatureFlags:DevTiersFree", false))
        {
            return true;
        }

        var subscription = await plansProvider.GetActiveAsync(userId, cancellationToken).ConfigureAwait(false);
        return subscription is not null
            && string.Equals(subscription.Status, "Active", StringComparison.OrdinalIgnoreCase)
            && subscription.PlanCode is not null
            && ProPlanCodes.Contains(subscription.PlanCode);
    }
}
