using System.Data;
using Microsoft.Data.SqlClient;
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
//     SILEN_ADMIN_USERNAME, SILEN_ADMIN_PASSWORD
//   Flags:
//     --username=<name>   operator name (else SILEN_ADMIN_USERNAME, else prompt)
//     --keep-totp         keep the enrolled authenticator secret, reprint its URI
//                         (for password-only rotation; otherwise a new secret is
//                         generated and must be re-enrolled in the app)

var connectionString = ReadEnv("SILEN_CONNECTION_STRING")
    ?? throw new InvalidOperationException("SILEN_CONNECTION_STRING is not set.");
var masterKey = AdminTotpSecretCipher.ParseMasterKey(ReadEnv("ENCRYPTION_MASTER_KEY") ?? string.Empty);
var keepTotp = args.Any(a => string.Equals(a, "--keep-totp", StringComparison.OrdinalIgnoreCase));

var username = ResolveUsername(args);
var password = ResolvePassword();

await using var connection = new SqlConnection(connectionString);
await connection.OpenAsync();

var existing = await GetAccountIdAsync(connection, username);
var isNewAccount = existing is null;

var totpSecret = keepTotp
    ? await ReadEnrolledSecretAsync(connection, username, masterKey)
    : TotpHelper.GenerateSecret();

var (passwordHash, passwordSalt) = PasswordHasher.Hash(password);

await UpsertAccountAsync(connection, username, passwordHash, passwordSalt, AdminTotpSecretCipher.Encrypt(totpSecret, masterKey));

var otpAuthUri = TotpHelper.BuildOtpAuthUri("SilaFit Admin", username, totpSecret, digits: 6, stepSeconds: 30);

Console.WriteLine();
Console.WriteLine(isNewAccount
    ? $"Created admin account '{username}'."
    : $"Rotated credentials for existing admin account '{username}' (all its sessions were signed out).");
Console.WriteLine();
Console.WriteLine("Authenticator enrollment - add this to Google Authenticator / Authy / 1Password:");
Console.WriteLine($"  secret: {FormatSecretForReading(totpSecret)}");
Console.WriteLine($"  uri:    {otpAuthUri}");
Console.WriteLine($"  current code right now: {TotpHelper.ComputeCode(totpSecret, DateTime.UtcNow, 6, 30)}");
Console.WriteLine();
Console.WriteLine("Store the secret somewhere safe (password manager): it is the only copy.");
Console.WriteLine("Sign in at /admin-login.html with the username, password and a code from the app.");
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
        throw new InvalidOperationException($"--keep-totp was requested but '{username}' does not exist yet; run without it to enroll a new authenticator secret.");
    }

    var cipher = (byte[])reader["TotpSecretCipher"];
    return AdminTotpSecretCipher.Decrypt(cipher, masterKey);
}

static async Task UpsertAccountAsync(
    SqlConnection connection,
    string username,
    byte[] passwordHash,
    byte[] passwordSalt,
    byte[] totpSecretCipher)
{
    await using var command = new SqlCommand("dbo.usp_Admin_UpsertAccount", connection) { CommandType = CommandType.StoredProcedure };
    command.Parameters.AddWithValue("@Username", username);
    command.Parameters.AddWithValue("@PasswordHash", passwordHash);
    command.Parameters.AddWithValue("@PasswordSalt", passwordSalt);
    command.Parameters.AddWithValue("@TotpSecretCipher", totpSecretCipher);

    await command.ExecuteNonQueryAsync();
}
