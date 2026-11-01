using Silen.Common.Contracts;
using Silen.Common.Models;

namespace Silen.Services.Abstractions;

/// <summary>Motivational lines for the app's splash screen.</summary>
public interface IMotivationalQuoteService
{
    Task<ServiceResult<List<MotivationalQuoteModel>>> GetActiveAsync(CancellationToken cancellationToken = default);
}
