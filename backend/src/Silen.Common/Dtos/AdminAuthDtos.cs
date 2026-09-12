namespace Silen.Common.Dtos;

/// <summary>Step 1 of the console sign-in: username + password.</summary>
public sealed class AdminLoginRequest
{
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}

/// <summary>
/// Returned by step 1 on success. <see cref="ChallengeToken"/> proves the password was
/// right, is only good for the second factor, and expires quickly - it grants no
/// access to anything on its own.
/// </summary>
public sealed class AdminLoginChallengeDto
{
    public string ChallengeToken { get; set; } = string.Empty;
    public int ExpiresInSeconds { get; set; }
}

/// <summary>Step 2: the challenge from step 1 plus the current authenticator code.</summary>
public sealed class AdminVerifyCodeRequest
{
    public string ChallengeToken { get; set; } = string.Empty;
    public string Code { get; set; } = string.Empty;

    /// <summary>Recorded on the session row for audit purposes. Filled in by the controller
    /// from the request connection - not set by the client directly.</summary>
    public string? ClientIp { get; set; }
}

/// <summary>
/// Internal result of step 2. <see cref="Token"/> is the raw session token and is
/// only ever handed to the cookie the controller sets - it is never returned in a
/// response body, so the browser's JS cannot read or leak it.
/// </summary>
public sealed class AdminSessionIssuedDto
{
    public string Token { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public DateTime ExpiresAtUtc { get; set; }
    public DateTime AbsoluteExpiresAtUtc { get; set; }
}

/// <summary>Who is signed in and until when - the payload of the session endpoint.</summary>
public sealed class AdminSessionDto
{
    public string Username { get; set; } = string.Empty;
    public DateTime ExpiresAtUtc { get; set; }
    public DateTime AbsoluteExpiresAtUtc { get; set; }

    /// <summary>The operator's role, or null for an account that has none (deny-all).</summary>
    public string? RoleName { get; set; }

    /// <summary>
    /// Everything this operator may do, resolved from their role on this request.
    /// The console renders its navigation, its landing view and its write controls
    /// from this list. The server enforces the same list separately, so hiding a
    /// button is a courtesy rather than the control.
    /// </summary>
    public List<string> Permissions { get; set; } = [];
}
