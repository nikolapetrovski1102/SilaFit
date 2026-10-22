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
                    // Backstop for the unique index: a repeated perk would render twice on the plans screen.
                    Features = features
                        .Where(f => f.PlanId == plan.PlanId)
                        .OrderBy(f => f.SortOrder)
                        .DistinctBy(f => f.FeatureText.Trim(), StringComparer.OrdinalIgnoreCase)
                        .ToList()
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

    public Task<ServiceResult<PromoCodeDto>> RedeemPromoCodeAsync(
        Guid userId, RedeemPromoCodeRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var code = request.Code?.Trim() ?? string.Empty;
            if (code.Length is 0 or > 40)
            {
                throw new ValidationException("Promo code was empty or too long.", "Enter the code exactly as you received it.");
            }

            var redemption = await plansProvider.RedeemPromoCodeAsync(userId, code, cancellationToken)
                ?? throw new NotFoundException($"Promo code redeem for user '{userId}' did not return a status row.");

            return redemption.Status switch
            {
                "Ok" => new PromoCodeDto
                {
                    Code = redemption.Code!,
                    PlayOfferId = redemption.PlayOfferId!,
                    ExpiresAtUtc = redemption.ExpiresAtUtc
                },
                "Expired" => throw new ValidationException($"Promo code '{code}' has expired.", "This code has expired."),
                "NotStarted" => throw new ValidationException($"Promo code '{code}' is not live yet.", "This code isn't active yet."),
                "Exhausted" => throw new ValidationException($"Promo code '{code}' has no redemptions left.", "This code has already been fully claimed."),
                _ => throw new ValidationException($"Promo code '{code}' is unknown or inactive.", "That code isn't valid.")
            };
        });
}
