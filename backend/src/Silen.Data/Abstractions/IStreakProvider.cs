using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IStreakProvider
{
    Task<(StreakStatusModel Status, List<WeekDayStatusModel> Week)> GetStatusAsync(
        Guid userId, CancellationToken cancellationToken = default);
}
