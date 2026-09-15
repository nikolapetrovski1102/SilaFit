using System.Data;
using Microsoft.Data.SqlClient;
using QRCoder;
using Silen.Common.Helpers;

// Enrollment + credential rotation for the admin console (website/admin.html).
//
// There is no self-service sign-up for console operators on purpose: the only ways
// to get an account are this tool and direct SQL access. It creates the account if
// the username is new, and otherwise replaces the password (and, unless you ask it
// not to, the TOTP secret) - so the same command is both "provision" and "rotate".
//
// Rotating also drops every live session for that operator, so a leaked password
// can be shut out immediately rather than waiting for a cookie to expire.
//
// Runs against the *stored procedures* (database/procedures/Admin.sql), exactly
// like the API does, so provisioning can never write a credential shape the runtime
// wouldn't understand.
//
// Usage:
//   SILEN_CONNECTION_STRING="..." ENCRYPTION_MASTER_KEY="<base64>" \
//     dotnet run --project backend/src/Silen.Tools.AdminProvision -- --username=admin
//
//   Env vars instead of prompts (used by the containerized run in deploy/):
//     SILEN_ADMIN_USERNAME, SILEN_ADMIN_PASSWORD, SILEN_ADMIN_EMAIL
//   Flags:
//     --username=<name>   operator name (else SILEN_ADMIN_USERNAME, else prompt)
//     --email=<address>   recovery email to set while creating/rotating (else
//                         SILEN_ADMIN_EMAIL, else leaves any existing address
//                         alone). Enables "send email code instead" at sign-in.
//     --keep-totp         keep the enrolled authenticator secret, reprint its URI
//                         (for password-only rotation; otherwise a new secret is
//                         generated and must be re-enrolled in the app)
//     --show-totp         read-only: reveal the existing account's authenticator
//                         secret + otpauth URI and render a scannable terminal QR,
//                         without rotating the password or dropping any sessions.
//                         Use this to re-enroll a device; no password is prompted.
//     --set-email=<addr>  read-only otherwise: sets (or, given an empty value,
//                         clears) the account's recovery email without touching
//                         its password, TOTP secret or live sessions.

var connectionString = ReadEnv("SILEN_CONNECTION_STRING")
    ?? throw new InvalidOperationException("SILEN_CONNECTION_STRING is not set.");
var masterKey = AdminTotpSecretCipher.ParseMasterKey(ReadEnv("ENCRYPTION_MASTER_KEY") ?? string.Empty);
var keepTotp = args.Any(a => string.Equals(a, "--keep-totp", StringComparison.OrdinalIgnoreCase));
var showTotp = args.Any(a => string.Equals(a, "--show-totp", StringComparison.OrdinalIgnoreCase));
var setEmailArg = args.FirstOrDefault(a => a.StartsWith("--set-email=", StringComparison.OrdinalIgnoreCase));

// Must match AdminAuthOptions defaults: an authenticator enrolled from this URI is
// checked against those settings, so a mismatch would make every code fail.
const string issuer = "SilaFit Admin";
const int digits = 6;
const int stepSeconds = 30;

var username = ResolveUsername(args);

// Read-only reveal. The secret is only ever stored encrypted, so the console can
// never show it again after enrollment - but whoever runs this tool already holds
// the master key needed to decrypt it (that is exactly what --keep-totp does).
// This path uses that access to reprint the enrollment without the side effects of
// a rotation: the password hash is left alone and no sessions are signed out.
if (showTotp)
{
    await using var readOnlyConnection = new SqlConnection(connectionString);
    await readOnlyConnection.OpenAsync();

    var enrolledSecret = await ReadEnrolledSecretAsync(readOnlyConnection, username, masterKey);
    var enrolledUri = TotpHelper.BuildOtpAuthUri(issuer, username, enrolledSecret, digits, stepSeconds);

    Console.WriteLine();
    Console.WriteLine($"Existing authenticator enrollment for '{username}' (read-only - nothing was changed):");
    PrintEnrollment(enrolledSecret, enrolledUri, digits, stepSeconds);
    PrintTerminalQr(enrolledUri);
    Console.WriteLine();
    Console.WriteLine("Sign in at /admin-login.html with the username, password and a code from the app.");

    return;
}

// Read-only email update: no password or TOTP touched, no sessions dropped - this is
// meant to be safe to run against a live, signed-in operator.
if (setEmailArg is not null)
{
    var newEmail = setEmailArg["--set-email=".Length..].Trim();

    await using var emailConnection = new SqlConnection(connectionString);
    await emailConnection.OpenAsync();

    var accountId = await GetAccountIdAsync(emailConnection, username)
        ?? throw new InvalidOperationException($"No admin account named '{username}' exists.");

    await SetEmailAsync(emailConnection, accountId, newEmail);

    Console.WriteLine();
    Console.WriteLine(newEmail.Length == 0
        ? $"Cleared the recovery email for admin account '{username}'."
        : $"Set the recovery email for admin account '{username}' to '{newEmail}'.");
    Console.WriteLine("Nothing else changed - the password, authenticator and any live sessions are untouched.");

    return;
}

var password = ResolvePassword();
var email = ResolveEmail(args);

await using var connection = new SqlConnection(connectionString);
await connection.OpenAsync();

var existing = await GetAccountIdAsync(connection, username);
var isNewAccount = existing is null;

var totpSecret = keepTotp
    ? await ReadEnrolledSecretAsync(connection, username, masterKey)
    : TotpHelper.GenerateSecret();

var (passwordHash, passwordSalt) = PasswordHasher.Hash(password);

await UpsertAccountAsync(connection, username, passwordHash, passwordSalt, AdminTotpSecretCipher.Encrypt(totpSecret, masterKey), email);

var otpAuthUri = TotpHelper.BuildOtpAuthUri(issuer, username, totpSecret, digits, stepSeconds);

Console.WriteLine();
Console.WriteLine(isNewAccount
    ? $"Created admin account '{username}'."
    : $"Rotated credentials for existing admin account '{username}' (all its sessions were signed out).");
PrintEnrollment(totpSecret, otpAuthUri, digits, stepSeconds);
Console.WriteLine();
Console.WriteLine("Store the secret somewhere safe (password manager): it is the only copy.");
Console.WriteLine("Sign in at /admin-login.html with the username, password and a code from the app.");
if (email is not null)
{
    Console.WriteLine(email.Length == 0
        ? "Recovery email cleared - \"send email code instead\" is unavailable until one is set."
        : $"Recovery email set to '{email}' - \"send email code instead\" is now available at sign-in.");
}
if (!keepTotp && !isNewAccount)
{
    Console.WriteLine();
    Console.WriteLine("NOTE: a new secret was issued - the previous enrollment in your authenticator app is now dead.");
}

return;

/* Treats a blank env var exactly like an unset one: docker compose passes
   `VAR: "${VAR:-}"` through as an empty string when nothing set it. */
static string? ReadEnv(string name)
{
    var value = Environment.GetEnvironmentVariable(name);
    return string.IsNullOrWhiteSpace(value) ? null : value;
}

static string ResolveUsername(string[] args)
{
    var fromArgs = args.FirstOrDefault(a => a.StartsWith("--username=", StringComparison.OrdinalIgnoreCase));

    var username = fromArgs is not null
        ? fromArgs["--username=".Length..]
        : ReadEnv("SILEN_ADMIN_USERNAME") ?? Prompt("Admin username: ");

    var trimmed = username.Trim();
    if (trimmed.Length is 0 or > 100)
    {
        throw new InvalidOperationException("Username must be 1-100 characters (dbo.AdminUsers.Username is NVARCHAR(100)).");
    }

    return trimmed;
}

static string ResolvePassword()
{
    var fromEnv = ReadEnv("SILEN_ADMIN_PASSWORD");
    if (fromEnv is not null)
    {
        ValidatePassword(fromEnv);
        return fromEnv;
    }

    var password = PromptSecret("Admin password: ");
    var confirm = PromptSecret("Confirm password: ");
    if (!string.Equals(password, confirm, StringComparison.Ordinal))
    {
        throw new InvalidOperationException("Passwords did not match.");
    }

    ValidatePassword(password);
    return password;
}

static void ValidatePassword(string password)
{
    if (password.Length < 12)
    {
        throw new InvalidOperationException("Choose a password of at least 12 characters - it guards the console and there is no reset-email flow behind it.");
    }
}

/* Null means "leave whatever's on file alone" - distinct from an explicit empty
   string, which clears it. Mirrors usp_Admin_UpsertAccount's own @Email handling. */
static string? ResolveEmail(string[] args)
{
    var fromArgs = args.FirstOrDefault(a => a.StartsWith("--email=", StringComparison.OrdinalIgnoreCase));
    var email = fromArgs is not null ? fromArgs["--email=".Length..] : ReadEnv("SILEN_ADMIN_EMAIL");

    return email?.Trim();
}

static string Prompt(string label)
{
    Console.Write(label);
    return Console.ReadLine() ?? string.Empty;
}

// Masked, so the password never lands in scrollback or a CI log.
static string PromptSecret(string label)
{
    Console.Write(label);
    var buffer = new System.Text.StringBuilder();

    while (true)
    {
        var key = Console.ReadKey(intercept: true);
        switch (key.Key)
        {
            case ConsoleKey.Enter:
                Console.WriteLine();
                return buffer.ToString();
            case ConsoleKey.Backspace when buffer.Length > 0:
                buffer.Length--;
                Console.Write("\b \b");
                break;
            default:
                if (!char.IsControl(key.KeyChar))
                {
                    buffer.Append(key.KeyChar);
                    Console.Write('*');
                }

                break;
        }
    }
}

// Base32 in groups of four is far easier to type into an app by hand than one long run.
static string FormatSecretForReading(string secret) =>
    string.Join(' ', Enumerable.Range(0, (secret.Length + 3) / 4).Select(i => secret.Substring(i * 4, Math.Min(4, secret.Length - i * 4))));

static void PrintEnrollment(string totpSecret, string otpAuthUri, int digits, int stepSeconds)
{
    Console.WriteLine();
    Console.WriteLine("Authenticator enrollment - add this to Google Authenticator / Authy / 1Password:");
    Console.WriteLine($"  secret: {FormatSecretForReading(totpSecret)}");
    Console.WriteLine($"  uri:    {otpAuthUri}");
    Console.WriteLine($"  current code right now: {TotpHelper.ComputeCode(totpSecret, DateTime.UtcNow, digits, stepSeconds)}");
}

// Terminal QR for the otpauth URI, so a remote operator can scan it straight off an
// SSH session instead of shuttling an image around. Always forced black-on-white via
// ANSI colours, because a scanner needs dark modules on a light field and the
// operator's terminal theme is unknown. Each text row packs two module rows using the
// half-block glyphs; QRCoder's matrix already carries the required quiet zone.
static void PrintTerminalQr(string otpAuthUri)
{
    using var generator = new QRCodeGenerator();
    using var qr = generator.CreateQrCode(otpAuthUri, QRCodeGenerator.ECCLevel.M);
    var matrix = qr.ModuleMatrix;

    var rows = matrix.Count;
    var columns = matrix[0].Length;

    Console.WriteLine();
    Console.WriteLine("Scan from your authenticator app (Add account -> Scan QR code):");

    for (var top = 0; top < rows; top += 2)
    {
        var line = new System.Text.StringBuilder("\u001b[30;47m");
        for (var column = 0; column < columns; column++)
        {
            var upper = matrix[top][column];
            var lower = top + 1 < rows && matrix[top + 1][column];
            line.Append((upper, lower) switch
            {
                (true, true) => '█',
                (true, false) => '▀',
                (false, true) => '▄',
                _ => ' '
            });
        }

        line.Append("\u001b[0m");
        Console.WriteLine(line.ToString());
    }
}

static async Task<Guid?> GetAccountIdAsync(SqlConnection connection, string username)
{
    await using var command = new SqlCommand("dbo.usp_Admin_GetAccountByUsername", connection) { CommandType = CommandType.StoredProcedure };
    command.Parameters.AddWithValue("@Username", username);

    await using var reader = await command.ExecuteReaderAsync();
    return await reader.ReadAsync() ? reader.GetGuid(0) : null;
}

static async Task<string> ReadEnrolledSecretAsync(SqlConnection connection, string username, byte[] masterKey)
{
    await using var command = new SqlCommand("dbo.usp_Admin_GetAccountByUsername", connection) { CommandType = CommandType.StoredProcedure };
    command.Parameters.AddWithValue("@Username", username);

    await using var reader = await command.ExecuteReaderAsync();
    if (!await reader.ReadAsync())
    {
        throw new InvalidOperationException($"No admin account named '{username}' exists, so there is no enrolled authenticator secret to read.");
    }

    var cipher = (byte[])reader["TotpSecretCipher"];
    return AdminTotpSecretCipher.Decrypt(cipher, masterKey);
}

static async Task UpsertAccountAsync(
    SqlConnection connection,
    string username,
    byte[] passwordHash,
    byte[] passwordSalt,
    byte[] totpSecretCipher,
    string? email)
{
    await using var command = new SqlCommand("dbo.usp_Admin_UpsertAccount", connection) { CommandType = CommandType.StoredProcedure };
    command.Parameters.AddWithValue("@Username", username);
    command.Parameters.AddWithValue("@PasswordHash", passwordHash);
    command.Parameters.AddWithValue("@PasswordSalt", passwordSalt);
    command.Parameters.AddWithValue("@TotpSecretCipher", totpSecretCipher);
    command.Parameters.AddWithValue("@Email", (object?)email ?? DBNull.Value);

    await command.ExecuteNonQueryAsync();
}

static async Task SetEmailAsync(SqlConnection connection, Guid adminUserId, string email)
{
    await using var command = new SqlCommand("dbo.usp_Admin_SetEmail", connection) { CommandType = CommandType.StoredProcedure };
    command.Parameters.AddWithValue("@AdminUserId", adminUserId);
    command.Parameters.AddWithValue("@Email", email.Length == 0 ? DBNull.Value : email);

    await command.ExecuteNonQueryAsync();
}
