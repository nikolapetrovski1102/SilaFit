using Microsoft.Extensions.Options;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Options;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IPartnerService"/>
public sealed class PartnerService(
    IPartnerLeadsProvider partnerLeadsProvider,
    IUserProfileProvider userProfileProvider,
    IMealPlanningService mealPlanningService,
    IOptions<PartnerOptions> partnerOptions) : IPartnerService
{
    public Task<ServiceResult<PartnerEncryptedResponse>> ProvisionLeadAsync(PartnerEncryptedRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var options = partnerOptions.Value;
            var payload = PartnerPayloadCodec.Decrypt<PartnerProvisionPayload>(request.Payload, options, PartnerPayloadCipher.ProvisionPurpose);
            var issuedAtUtc = PartnerPayloadCodec.RequireFreshIssuedAt(payload.IssuedAtUtc, options, DateTime.UtcNow);
            var partnerUserId = PartnerPayloadCodec.RequirePartnerUserId(payload.PartnerUserId);
            var (email, displayName, provider) = PartnerPayloadCodec.RequireLeadDetails(payload);
            var profile = PartnerPayloadCodec.RequireProfile(payload.Profile);

            var outcome = await partnerLeadsProvider.ProvisionAsync(
                partnerUserId, email, displayName, provider, issuedAtUtc, cancellationToken)
                ?? throw new NotFoundException($"Partner provision for lead '{partnerUserId}' returned no outcome row.");

            var result = outcome.Outcome switch
            {
                "Ok" when outcome.UserId is { } userId => new PartnerLeadResultDto
                {
                    PartnerUserId = partnerUserId,
                    UserId = userId,
                    Status = "Active",
                    RequestIssuedAtUtc = issuedAtUtc,
                    IsNewAccount = outcome.IsNewAccount,
                    ProGranted = outcome.ProGranted,
                    ProfileSaved = profile is not null && await SeedProfileAsync(userId, profile, cancellationToken)
                },
                "Stale" => throw new ConflictException(
                    $"Partner provision for lead '{partnerUserId}' is older than a request already applied.",
                    "A newer request for this lead was already applied."),
                "EmailTaken" => throw new ConflictException(
                    $"Partner provision for lead '{partnerUserId}': email tag {LogRedaction.Tag(email)} already belongs to another lead.",
                    "This email's SilaFit account already belongs to a different lead."),
                "AccountDisabled" => throw new ConflictException(
                    $"Partner provision for lead '{partnerUserId}': email tag {LogRedaction.Tag(email)} belongs to a deactivated account.",
                    "The SilaFit account with this email is deactivated."),
                _ => throw new InvalidOperationException($"Unexpected partner provision outcome '{outcome.Outcome}'.")
            };

            return PartnerPayloadCodec.Seal(result, options, PartnerPayloadCipher.ProvisionResponsePurpose);
        });

    public Task<ServiceResult<PartnerEncryptedResponse>> CancelLeadAsync(PartnerEncryptedRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var options = partnerOptions.Value;
            var payload = PartnerPayloadCodec.Decrypt<PartnerCancelPayload>(request.Payload, options, PartnerPayloadCipher.CancelPurpose);
            var issuedAtUtc = PartnerPayloadCodec.RequireFreshIssuedAt(payload.IssuedAtUtc, options, DateTime.UtcNow);
            var partnerUserId = PartnerPayloadCodec.RequirePartnerUserId(payload.PartnerUserId);

            var outcome = await partnerLeadsProvider.CancelAsync(partnerUserId, issuedAtUtc, cancellationToken)
                ?? throw new NotFoundException($"Partner cancel for lead '{partnerUserId}' returned no outcome row.");

            var result = outcome.Outcome switch
            {
                "Ok" when outcome.UserId is { } userId => new PartnerLeadResultDto
                {
                    PartnerUserId = partnerUserId,
                    UserId = userId,
                    Status = "Cancelled",
                    RequestIssuedAtUtc = issuedAtUtc
                },
                "NotFound" => throw new NotFoundException(
                    $"Partner cancel for unknown lead '{partnerUserId}'.", "No lead exists with this partnerUserId."),
                "Stale" => throw new ConflictException(
                    $"Partner cancel for lead '{partnerUserId}' is older than a request already applied.",
                    "A newer request for this lead was already applied."),
                _ => throw new InvalidOperationException($"Unexpected partner cancel outcome '{outcome.Outcome}'.")
            };

            return PartnerPayloadCodec.Seal(result, options, PartnerPayloadCipher.CancelResponsePurpose);
        });

    /// <summary>Saves the partner's onboarding answers as the account's profile, unless it
    /// already has one - answers the user gave in the app, or an earlier provision's, are
    /// never overwritten. Returns whether the profile was written.</summary>
    private async Task<bool> SeedProfileAsync(Guid userId, UpsertUserProfileRequest profile, CancellationToken cancellationToken)
    {
        if (await userProfileProvider.GetAsync(userId, cancellationToken) is not null)
        {
            return false;
        }

        var saved = await userProfileProvider.UpsertAsync(userId, profile, cancellationToken);

        // Same as the app's own profile save: nutrition targets follow the profile.
        // Best-effort - the result is not checked, so a hiccup never fails the provision.
        await mealPlanningService.RecomputeTargetsAsync(userId, saved, cancellationToken);
        return true;
    }
}
