using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

/// <summary>
/// Server-to-server API for the partner website. A lead who signs up there (Apple, Google
/// or email) gets a SilaFit account with PRO that the partner bills; it stays PRO until
/// the partner cancels, which ends it immediately. The user later signs in to the app with
/// the same Apple/Google account or email and lands on that account.
/// Requests and successful responses are both AES-256-GCM sealed with the shared key
/// (PartnerPayloadCipher); error responses stay plain and carry no lead data.
/// </summary>
public interface IPartnerService
{
    Task<ServiceResult<PartnerEncryptedResponse>> ProvisionLeadAsync(PartnerEncryptedRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<PartnerEncryptedResponse>> CancelLeadAsync(PartnerEncryptedRequest request, CancellationToken cancellationToken = default);
}
