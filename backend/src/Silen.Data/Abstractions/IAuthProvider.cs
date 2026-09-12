using Silen.Common.Models;

namespace Silen.Data.Abstractions;

public interface IAuthProvider
{
    Task<UserAccountModel?> GetOrCreateDeviceUserAsync(string deviceId, CancellationToken cancellationToken = default);

    Task<UserAccountModel?> GetUserByEmailAsync(string email, CancellationToken cancellationToken = default);

    Task<UserAccountModel?> GetUserByIdAsync(Guid userId, CancellationToken cancellationToken = default);

    Task<UserAccountModel?> GetIdentityAsync(string provider, string externalId, CancellationToken cancellationToken = default);

    Task<Guid> RegisterEmailUserAsync(
        Guid? existingUserId,
        string email,
        byte[] passwordHash,
        byte[] passwordSalt,
        string? displayName,
        CancellationToken cancellationToken = default);

    Task<Guid> LinkExternalIdentityAsync(
        Guid? existingUserId,
        string provider,
        string externalId,
        string? email,
        string? displayName,
        CancellationToken cancellationToken = default);

    Task UpdateLastLoginAsync(Guid userId, CancellationToken cancellationToken = default);
}
