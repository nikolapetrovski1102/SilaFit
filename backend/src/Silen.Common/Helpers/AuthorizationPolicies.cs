namespace Silen.Common.Helpers;

/// <summary>Names of the ASP.NET Core authorization policies the API defines, shared between Program.cs and controllers.</summary>
public static class AuthorizationPolicies
{
    /// <summary>Requires the "tier" claim to be Registered - gates progress analytics, purchases and other account-only features.</summary>
    public const string RequireLinkedAccount = "RequireLinkedAccount";
}
