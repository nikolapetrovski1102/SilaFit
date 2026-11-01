using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>Partner shops with discount codes: the app's Settings list and protein nudge, and the console's editor.</summary>
public interface ISupplementProviderService
{
    Task<ServiceResult<List<SupplementProviderModel>>> GetActiveAsync(CancellationToken cancellationToken = default);

    Task<ServiceResult<List<AdminSupplementProviderModel>>> GetAllAsync(string? sessionToken, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> SaveAsync(
        string? sessionToken, AdminSupplementProviderUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminWriteResultDto>> DeleteAsync(
        string? sessionToken, Guid providerId, string? clientIp, CancellationToken cancellationToken = default);

    Task<ServiceResult<AdminImageUploadResultDto>> UploadLogoAsync(
        string? sessionToken, ImageUploadRequest upload, string? clientIp, CancellationToken cancellationToken = default);
}
