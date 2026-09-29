using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

public interface ISupportService
{
    /// <summary>Emails a website support-form message to the support inbox, with the
    /// visitor's address as Reply-To.</summary>
    Task<ServiceResult<bool>> ContactAsync(SupportContactRequest request, CancellationToken cancellationToken = default);
}
