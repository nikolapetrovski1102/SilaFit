using Microsoft.Data.SqlClient;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>
/// Builds the three actor parameters every admin write procedure takes
/// (@ActorAdminUserId / @ActorUsername / @ActorIp). An outside helper rather than a
/// private method on the provider, matching the rule that Provider classes hold no
/// private methods of their own.
/// </summary>
public static class AdminActorParameters
{
    public static SqlParameter[] Build(AdminActorModel actor) =>
    [
        SqlParameterBuilder.Create("@ActorAdminUserId", actor.AdminUserId),
        SqlParameterBuilder.Create("@ActorUsername", actor.Username),
        SqlParameterBuilder.Create("@ActorIp", actor.Ip)
    ];
}
