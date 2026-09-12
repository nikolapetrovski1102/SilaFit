using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

public interface IAuthService
{
    Task<ServiceResult<AuthResultDto>> LoginWithDeviceAsync(string deviceId, CancellationToken cancellationToken = default);

    Task<ServiceResult<AuthResultDto>> RegisterEmailAsync(EmailRegisterRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<AuthResultDto>> LoginEmailAsync(EmailLoginRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<AuthResultDto>> LoginOrLinkGoogleAsync(GoogleLoginRequest request, CancellationToken cancellationToken = default);

    Task<ServiceResult<AuthResultDto>> LoginOrLinkAppleAsync(AppleLoginRequest request, CancellationToken cancellationToken = default);
}
