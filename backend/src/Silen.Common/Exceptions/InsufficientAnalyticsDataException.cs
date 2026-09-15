namespace Silen.Common.Exceptions;

/// <summary>
/// Thrown when a user hasn't logged enough activity in the requested month to generate a
/// meaningful AI review. Distinct from <see cref="ProUpgradeRequiredException"/> (403) so the
/// frontend can tell "not Pro" apart from "not enough history yet" and show its own empty state
/// instead of a generic error (see AnalyticsController catch-side in the Flutter app).
/// </summary>
public sealed class InsufficientAnalyticsDataException : AppException
{
    /// <summary>The HTTP status this maps to. Also lets service-layer callers that consume a
    /// <see cref="Silen.Common.Contracts.ServiceResult{T}"/> (e.g. the monthly review batch,
    /// which must not count a quiet month as a failed run) tell "not enough data" apart from a
    /// genuine failure without depending on message text.</summary>
    public const int HttpStatusCode = 422;

    public InsufficientAnalyticsDataException(string logMessage, string? userMessage = null)
        : base(HttpStatusCode, userMessage ?? "Not enough activity logged this month yet for an AI review.", logMessage)
    {
    }
}
