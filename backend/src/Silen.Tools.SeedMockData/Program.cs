using Microsoft.Data.SqlClient;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Providers;

// Fills demo accounts with a realistic month of history - workouts, meals,
// hydration and bodyweight - so the Today dashboard, Progress heatmap and the
// monthly overview all have something worth looking at instead of empty states.
//
// The month-building logic itself lives in Silen.Data.Providers.MockDataSeeder,
// which the admin console calls for an existing user too (POST
// /api/admin/content/users/mock-data, super-admin only). This tool has two entry
// points: the device-id one creates/reuses the demo Guest accounts (one per
// paying tier, differentiated - see the seeder's TierProfiles), and the
// --user-id/--email one targets an existing account that already signed in with
// a real identity (those have DeviceId NULL, so device-id seeding can't reach them).
//
// Re-running for the same user wipes and regenerates that user's workouts/
// meals/hydration/bodyweight (profile, split and subscription are re-upserted),
// so it's safe to run repeatedly while iterating on the app.
//
// Usage:
//   SILEN_CONNECTION_STRING="..." ENCRYPTION_MASTER_KEY="<base64>" \
//     dotnet run --project backend/src/Silen.Tools.SeedMockData
//
//   Flags (all optional):
//     --advanced-device-id=<id>[,<id>...]  device id(s) to seed as Advanced tier
//                                          (default: silen-demo-advanced)
//     --pro-device-id=<id>[,<id>...]       device id(s) to seed as Pro tier
//                                          (default: silen-demo-pro)
//                                          Each becomes/reuses a Guest account - log into
//                                          the app with this same device id
//                                          (POST /api/auth/device) to view it.
//     --user-id=<guid>[,<guid>...]         existing user id(s) to seed (skips the
//                                          device-id path entirely when given)
//     --email=<email>[,<email>...]         existing user(s) resolved by Email
//                                          (same as --user-id once looked up)
//     --profile=<Advanced|Pro>             tier profile for --user-id/--email
//                                          (default: Advanced)
//     --days=<n>                           how many days of history to generate,
//                                          ending today (default: 30)
//     --seed=<n>                           RNG seed, for a reproducible run
//                                          (default: random, printed below)

var connectionString = ReadEnv("SILEN_CONNECTION_STRING")
    ?? throw new InvalidOperationException("SILEN_CONNECTION_STRING is not set.");
var masterKeyBase64 = ReadEnv("ENCRYPTION_MASTER_KEY")
    ?? throw new InvalidOperationException("ENCRYPTION_MASTER_KEY is not set.");
var key = Convert.FromBase64String(masterKeyBase64);
if (key.Length != FieldCipher.KeySizeBytes)
{
    throw new InvalidOperationException($"ENCRYPTION_MASTER_KEY must decode to {FieldCipher.KeySizeBytes} bytes, got {key.Length}.");
}

var advancedDeviceIds = GetArg(args, "--advanced-device-id")?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
    ?? ["silen-demo-advanced"];
var proDeviceIds = GetArg(args, "--pro-device-id")?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
    ?? ["silen-demo-pro"];
var userIds = SplitArg(args, "--user-id");
var emails = SplitArg(args, "--email");
var userProfile = ResolveProfile(GetArg(args, "--profile") ?? MockDataProfiles.Advanced);
var days = int.TryParse(GetArg(args, "--days"), out var parsedDays) && parsedDays > 0 ? parsedDays : 30;
var seed = int.TryParse(GetArg(args, "--seed"), out var parsedSeed) ? parsedSeed : Environment.TickCount;

var seeder = new MockDataSeeder(connectionString, masterKeyBase64);

// --user-id/--email target existing accounts explicitly, so the device-id demo
// accounts are only touched when neither was given.
if (userIds.Count > 0 || emails.Count > 0)
{
    Console.WriteLine($"Seeding {days} day(s) of {userProfile} mock data for {userIds.Count} user id(s) and {emails.Count} email(s), RNG seed {seed}.");
    Console.WriteLine("(pass --seed={0} to reproduce this exact run)", seed);
    Console.WriteLine();

    foreach (var rawUserId in userIds)
    {
        if (!Guid.TryParse(rawUserId, out var userId))
        {
            Console.WriteLine($"! skipping invalid --user-id value '{rawUserId}' (expected a GUID).");
            continue;
        }

        PrintUserResult(userId, await seeder.SeedUserAsync(userId, userProfile, days, seed));
    }

    foreach (var email in emails)
    {
        var userId = await FindUserIdByEmailAsync(connectionString, email);
        if (userId is null)
        {
            Console.WriteLine($"! no active user found with email '{email}'.");
            continue;
        }

        PrintUserResult(userId.Value, await seeder.SeedUserAsync(userId.Value, userProfile, days, seed));
    }

    Console.WriteLine();
    Console.WriteLine("Done.");
    return;
}

Console.WriteLine($"Seeding {days} day(s) of mock data for {advancedDeviceIds.Length} Advanced and {proDeviceIds.Length} Pro account(s), RNG seed {seed}.");
Console.WriteLine("(pass --seed={0} to reproduce this exact run)", seed);
Console.WriteLine();

foreach (var deviceId in advancedDeviceIds)
{
    Print(await seeder.SeedDeviceAsync(deviceId, MockDataProfiles.Advanced, days, seed));
}

foreach (var deviceId in proDeviceIds)
{
    Print(await seeder.SeedDeviceAsync(deviceId, MockDataProfiles.Pro, days, seed));
}

Console.WriteLine();
Console.WriteLine("Done. Log in from the app with POST /api/auth/device { \"deviceId\": \"<one of the ids above>\" }.");

return;

static void Print(MockDataSeedResult result)
{
    Console.WriteLine();
    Console.WriteLine($"--- user {result.UserId} ({result.Profile} tier, split '{result.SplitName}') ---");
    Console.WriteLine($"  workouts: {result.WorkoutsCompleted} completed, {result.WorkoutsMissed} missed");
    Console.WriteLine($"  meals logged: {result.MealsLogged}, hydration entries: {result.HydrationEntries}, bodyweight entries: {result.BodyweightEntries}");
}

static void PrintUserResult(Guid userId, MockDataSeedResult? result)
{
    if (result is null)
    {
        Console.WriteLine();
        Console.WriteLine($"! user {userId} not found (or inactive) - skipped.");
        return;
    }

    Print(result);
}

static async Task<Guid?> FindUserIdByEmailAsync(string connectionString, string email)
{
    await using var connection = new SqlConnection(connectionString);
    await connection.OpenAsync();

    await using var command = connection.CreateCommand();
    command.CommandText = "SELECT TOP (1) UserId FROM dbo.Users WHERE Email = @Email AND IsActive = 1;";
    command.Parameters.AddWithValue("@Email", email);

    return await command.ExecuteScalarAsync() is Guid userId ? userId : null;
}

static string ResolveProfile(string value)
{
    var match = MockDataProfiles.All.FirstOrDefault(p =>
        string.Equals(p, value, StringComparison.OrdinalIgnoreCase));

    return match ?? throw new InvalidOperationException(
        $"--profile must be one of: {string.Join(", ", MockDataProfiles.All)}.");
}

static List<string> SplitArg(string[] args, string prefix) =>
    GetArg(args, prefix)?.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList()
    ?? [];

static string? ReadEnv(string name)
{
    var value = Environment.GetEnvironmentVariable(name);
    return string.IsNullOrWhiteSpace(value) ? null : value;
}

static string? GetArg(string[] args, string prefix)
{
    var match = args.FirstOrDefault(a => a.StartsWith(prefix + "=", StringComparison.OrdinalIgnoreCase));
    return match?[(prefix.Length + 1)..];
}
