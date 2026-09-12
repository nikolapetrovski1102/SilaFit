namespace Silen.Common.Models;

/// <summary>
/// Who is making a change, for the audit row the procedure writes in the same
/// transaction. The API builds this from the authenticated session, so an operator
/// can never influence what the trail says about them.
///
/// <see cref="AdminUserId"/> is nullable and <see cref="Username"/> is not, because
/// not every actor is a signed-in operator: the provisioning tool assigns roles too,
/// and it identifies itself by name.
/// </summary>
public sealed class AdminActorModel
{
    public Guid? AdminUserId { get; init; }
    public string Username { get; init; } = string.Empty;
    public string? Ip { get; init; }
}
