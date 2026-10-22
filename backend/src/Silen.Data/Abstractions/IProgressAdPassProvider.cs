using Silen.Common.Models;

namespace Silen.Data.Abstractions;

/// <summary>Short Progress passes a Free account earns by watching a rewarded video ad.</summary>
public interface IProgressAdPassProvider
{
    /// <summary>Grants a pass valid for <paramref name="validMinutes"/> unless the user already
    /// holds <paramref name="dailyLimit"/> passes granted in the last 24 hours.</summary>
    Task<ProgressAdPassGrantModel> GrantAsync(Guid userId, int validMinutes, int dailyLimit, CancellationToken cancellationToken = default);

    Task<bool> HasActiveAsync(Guid userId, CancellationToken cancellationToken = default);

    /// <summary>Expires the user's unexpired passes now; they still count toward the daily cap.</summary>
    Task EndAsync(Guid userId, CancellationToken cancellationToken = default);
}
