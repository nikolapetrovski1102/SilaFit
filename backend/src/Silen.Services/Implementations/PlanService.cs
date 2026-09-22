using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IPlanService"/>
public sealed class PlanService(IPlansProvider plansProvider, ISubscriptionReceiptService subscriptionReceiptService) : IPlanService
{
    public Task<ServiceResult<List<PlanCatalogEntryDto>>> GetCatalogAsync(CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var (plans, features) = await plansProvider.GetAllAsync(cancellationToken);

            return plans
                .Select(plan => new PlanCatalogEntryDto
                {
                    Plan = plan,
                    Features = features.Where(f => f.PlanId == plan.PlanId).OrderBy(f => f.SortOrder).ToList()
                })
                .ToList();
        });

    public Task<ServiceResult<UserSubscriptionModel>> GetCurrentAsync(Guid userId, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var subscription = await plansProvider.GetActiveAsync(userId, cancellationToken);
            if (subscription is not null
                && string.Equals(subscription.Status, "Active", StringComparison.OrdinalIgnoreCase)
                && (subscription.ExpiresAtUtc is null || subscription.ExpiresAtUtc > DateTime.UtcNow))
                return subscription;

            return new UserSubscriptionModel { UserId = userId, PlanCode = "FREE", PlanName = "Free", Status = "Inactive" };
        });

    public Task<ServiceResult<UserSubscriptionModel>> PurchaseAsync(Guid userId, PurchaseRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            if (request.BillingCycle is not ("Monthly" or "Yearly"))
            {
                throw new ValidationException($"Unsupported billing cycle '{request.BillingCycle}'.", "Choose a monthly or yearly plan.");
            }

            return await plansProvider.PurchaseAsync(userId, request.PlanId, request.BillingCycle, cancellationToken)
                ?? throw new NotFoundException($"Purchase for user '{userId}' did not return a subscription row.");
        });

    public Task<ServiceResult<UserSubscriptionModel>> VerifyPurchaseAsync(
        Guid userId, VerifyPurchaseRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(() => subscriptionReceiptService.VerifyAndActivateAsync(userId, request, cancellationToken));
}
