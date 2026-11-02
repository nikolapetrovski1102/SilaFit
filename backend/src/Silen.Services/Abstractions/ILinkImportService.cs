using Silen.Common.Contracts;
using Silen.Common.Dtos;

namespace Silen.Services.Abstractions;

/// <summary>
/// "Share to SilaFit" from TikTok: reads a public post's caption and turns it into a workout
/// (exercises matched to the library) or a meal (ingredients with per-100 g nutrition). The AI
/// decides which; the user then reviews it in the app before anything is saved.
///
/// Allowance, per kind: Advanced gets workout and meal scans, Pro workout scans only, each
/// <see cref="DailyLimit"/> per local day. Free gets <see cref="TrialLimit"/> scans ever, of
/// either kind. A post that is neither a workout nor a meal doesn't use a scan. Requires AI
/// data-sharing consent, since the caption goes to the AI provider.
/// </summary>
public interface ILinkImportService
{
    const int DailyLimit = 3;
    const int TrialLimit = 5;

    Task<ServiceResult<LinkImportQuotaDto>> GetQuotaAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<ServiceResult<LinkImportResultDto>> ImportAsync(
        Guid userId, LinkImportRequest request, CancellationToken cancellationToken = default);
}
