namespace Silen.Data.Abstractions;

public interface IHydrationProvider
{
    Task<int> LogAsync(Guid userId, short amountMl, CancellationToken cancellationToken = default);

    Task<int> GetTodayTotalAsync(Guid userId, CancellationToken cancellationToken = default);
}
