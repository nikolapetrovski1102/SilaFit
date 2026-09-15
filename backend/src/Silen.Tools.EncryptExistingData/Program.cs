using Microsoft.Data.SqlClient;
using Silen.Common.Helpers;

// One-time backfill tool for the column-encryption rollout (see
// database/schema/024_ColumnEncryptionAdd.sql / 025_ColumnEncryptionCutover.sql).
//
// Run this AFTER 024 has been applied and ENCRYPTION_MASTER_KEY exists, and
// BEFORE running 025 or deploying the updated backend. It reads every row's
// plaintext columns, encrypts them with the same AES-256-GCM FieldCipher the
// app will use, and writes the ciphertext into the matching "*Enc" column
// added by 024 - leaving the original plaintext columns untouched.
//
// Safe to re-run: only rows whose *Enc column is still NULL are processed,
// so an interrupted run just picks up where it left off. It is also safe to
// run unconditionally on every deploy (deploy.sh does, right before applying
// 025) even long after the cutover: each table is skipped once its "_Legacy"
// column exists, since that is 025's own signal that it already promoted
// that table's *Enc columns into place - at that point the columns this tool
// would read as plaintext hold real ciphertext instead (a bare "*Enc IS
// NULL" check can't tell the difference, and reading ciphertext bytes back
// as a string throws System.InvalidCastException).
//
// Usage:
//   SILEN_CONNECTION_STRING="..." ENCRYPTION_MASTER_KEY="<base64>" \
//     dotnet run --project backend/src/Silen.Tools.EncryptExistingData

var connectionString = Environment.GetEnvironmentVariable("SILEN_CONNECTION_STRING")
    ?? throw new InvalidOperationException("SILEN_CONNECTION_STRING is not set.");
var masterKeyBase64 = Environment.GetEnvironmentVariable("ENCRYPTION_MASTER_KEY")
    ?? throw new InvalidOperationException("ENCRYPTION_MASTER_KEY is not set.");
var key = Convert.FromBase64String(masterKeyBase64);
if (key.Length != FieldCipher.KeySizeBytes)
{
    throw new InvalidOperationException($"ENCRYPTION_MASTER_KEY must decode to {FieldCipher.KeySizeBytes} bytes, got {key.Length}.");
}

await using var connection = new SqlConnection(connectionString);
await connection.OpenAsync();

await EncryptUserProfilesAsync(connection, key);
await EncryptBodyweightLogsAsync(connection, key);
await EncryptMealLogsAsync(connection, key);
await EncryptUserNutritionTargetsAsync(connection, key);

Console.WriteLine("Backfill complete.");
return;

static async Task<bool> ColumnExistsAsync(SqlConnection connection, string table, string column)
{
    await using var cmd = new SqlCommand(
        "SELECT COL_LENGTH(@Table, @Column)", connection);
    cmd.Parameters.AddWithValue("@Table", table);
    cmd.Parameters.AddWithValue("@Column", column);
    var result = await cmd.ExecuteScalarAsync();
    return result is not DBNull and not null;
}

static async Task EncryptUserProfilesAsync(SqlConnection connection, byte[] key)
{
    if (await ColumnExistsAsync(connection, "dbo.UserProfiles", "Gender_Legacy"))
    {
        Console.WriteLine("UserProfiles: already cut over, skipping.");
        return;
    }

    const string selectSql = """
        SELECT UserId, Gender, AgeYears, HeightCm, WeightKg, Goal
        FROM dbo.UserProfiles
        WHERE GenderEnc IS NULL AND AgeYearsEnc IS NULL AND HeightCmEnc IS NULL
              AND WeightKgEnc IS NULL AND GoalEnc IS NULL
        """;

    var rows = new List<(Guid UserId, string? Gender, byte? AgeYears, decimal? HeightCm, decimal? WeightKg, string? Goal)>();
    await using (var select = new SqlCommand(selectSql, connection))
    await using (var reader = await select.ExecuteReaderAsync())
    {
        while (await reader.ReadAsync())
        {
            rows.Add((
                reader.GetGuid(0),
                reader.IsDBNull(1) ? null : reader.GetString(1),
                reader.IsDBNull(2) ? null : reader.GetByte(2),
                reader.IsDBNull(3) ? null : reader.GetDecimal(3),
                reader.IsDBNull(4) ? null : reader.GetDecimal(4),
                reader.IsDBNull(5) ? null : reader.GetString(5)));
        }
    }

    const string updateSql = """
        UPDATE dbo.UserProfiles
        SET GenderEnc = @GenderEnc, AgeYearsEnc = @AgeYearsEnc, HeightCmEnc = @HeightCmEnc,
            WeightKgEnc = @WeightKgEnc, GoalEnc = @GoalEnc
        WHERE UserId = @UserId
        """;

    foreach (var row in rows)
    {
        await using var update = new SqlCommand(updateSql, connection);
        update.Parameters.AddWithValue("@UserId", row.UserId);
        update.Parameters.AddWithValue("@GenderEnc", (object?)(row.Gender is null ? null : FieldCipher.EncryptString(row.Gender, key)) ?? DBNull.Value);
        update.Parameters.AddWithValue("@AgeYearsEnc", (object?)(row.AgeYears is null ? null : FieldCipher.EncryptInt(row.AgeYears.Value, key)) ?? DBNull.Value);
        update.Parameters.AddWithValue("@HeightCmEnc", (object?)(row.HeightCm is null ? null : FieldCipher.EncryptDecimal(row.HeightCm.Value, key)) ?? DBNull.Value);
        update.Parameters.AddWithValue("@WeightKgEnc", (object?)(row.WeightKg is null ? null : FieldCipher.EncryptDecimal(row.WeightKg.Value, key)) ?? DBNull.Value);
        update.Parameters.AddWithValue("@GoalEnc", (object?)(row.Goal is null ? null : FieldCipher.EncryptString(row.Goal, key)) ?? DBNull.Value);
        await update.ExecuteNonQueryAsync();
    }

    Console.WriteLine($"UserProfiles: encrypted {rows.Count} row(s).");
}

static async Task EncryptBodyweightLogsAsync(SqlConnection connection, byte[] key)
{
    if (await ColumnExistsAsync(connection, "dbo.BodyweightLogs", "WeightKg_Legacy"))
    {
        Console.WriteLine("BodyweightLogs: already cut over, skipping.");
        return;
    }

    const string selectSql = "SELECT BodyweightLogId, WeightKg FROM dbo.BodyweightLogs WHERE WeightKgEnc IS NULL";

    var rows = new List<(Guid Id, decimal WeightKg)>();
    await using (var select = new SqlCommand(selectSql, connection))
    await using (var reader = await select.ExecuteReaderAsync())
    {
        while (await reader.ReadAsync())
        {
            rows.Add((reader.GetGuid(0), reader.GetDecimal(1)));
        }
    }

    const string updateSql = "UPDATE dbo.BodyweightLogs SET WeightKgEnc = @WeightKgEnc WHERE BodyweightLogId = @Id";
    foreach (var row in rows)
    {
        await using var update = new SqlCommand(updateSql, connection);
        update.Parameters.AddWithValue("@Id", row.Id);
        update.Parameters.AddWithValue("@WeightKgEnc", FieldCipher.EncryptDecimal(row.WeightKg, key));
        await update.ExecuteNonQueryAsync();
    }

    Console.WriteLine($"BodyweightLogs: encrypted {rows.Count} row(s).");
}

static async Task EncryptMealLogsAsync(SqlConnection connection, byte[] key)
{
    if (await ColumnExistsAsync(connection, "dbo.MealLogs", "Title_Legacy"))
    {
        Console.WriteLine("MealLogs: already cut over, skipping.");
        return;
    }

    const string selectSql = """
        SELECT MealLogId, Title, CaloriesKcal, ProteinG, CarbsG, FatsG
        FROM dbo.MealLogs
        WHERE TitleEnc IS NULL
        """;

    var rows = new List<(Guid Id, string Title, short Calories, short Protein, short Carbs, short Fats)>();
    await using (var select = new SqlCommand(selectSql, connection))
    await using (var reader = await select.ExecuteReaderAsync())
    {
        while (await reader.ReadAsync())
        {
            rows.Add((
                reader.GetGuid(0), reader.GetString(1),
                reader.GetInt16(2), reader.GetInt16(3), reader.GetInt16(4), reader.GetInt16(5)));
        }
    }

    const string updateSql = """
        UPDATE dbo.MealLogs
        SET TitleEnc = @TitleEnc, CaloriesKcalEnc = @CaloriesKcalEnc,
            ProteinGEnc = @ProteinGEnc, CarbsGEnc = @CarbsGEnc, FatsGEnc = @FatsGEnc
        WHERE MealLogId = @Id
        """;

    foreach (var row in rows)
    {
        await using var update = new SqlCommand(updateSql, connection);
        update.Parameters.AddWithValue("@Id", row.Id);
        update.Parameters.AddWithValue("@TitleEnc", FieldCipher.EncryptString(row.Title, key));
        update.Parameters.AddWithValue("@CaloriesKcalEnc", FieldCipher.EncryptInt(row.Calories, key));
        update.Parameters.AddWithValue("@ProteinGEnc", FieldCipher.EncryptInt(row.Protein, key));
        update.Parameters.AddWithValue("@CarbsGEnc", FieldCipher.EncryptInt(row.Carbs, key));
        update.Parameters.AddWithValue("@FatsGEnc", FieldCipher.EncryptInt(row.Fats, key));
        await update.ExecuteNonQueryAsync();
    }

    Console.WriteLine($"MealLogs: encrypted {rows.Count} row(s).");
}

static async Task EncryptUserNutritionTargetsAsync(SqlConnection connection, byte[] key)
{
    if (await ColumnExistsAsync(connection, "dbo.UserNutritionTargets", "TargetCalories_Legacy"))
    {
        Console.WriteLine("UserNutritionTargets: already cut over, skipping.");
        return;
    }

    const string selectSql = """
        SELECT UserId, TargetCalories, TargetProteinG, TargetCarbsG, TargetFatsG
        FROM dbo.UserNutritionTargets
        WHERE TargetCaloriesEnc IS NULL
        """;

    var rows = new List<(Guid UserId, short Calories, short Protein, short Carbs, short Fats)>();
    await using (var select = new SqlCommand(selectSql, connection))
    await using (var reader = await select.ExecuteReaderAsync())
    {
        while (await reader.ReadAsync())
        {
            rows.Add((
                reader.GetGuid(0),
                reader.GetInt16(1), reader.GetInt16(2), reader.GetInt16(3), reader.GetInt16(4)));
        }
    }

    const string updateSql = """
        UPDATE dbo.UserNutritionTargets
        SET TargetCaloriesEnc = @TargetCaloriesEnc, TargetProteinGEnc = @TargetProteinGEnc,
            TargetCarbsGEnc = @TargetCarbsGEnc, TargetFatsGEnc = @TargetFatsGEnc
        WHERE UserId = @UserId
        """;

    foreach (var row in rows)
    {
        await using var update = new SqlCommand(updateSql, connection);
        update.Parameters.AddWithValue("@UserId", row.UserId);
        update.Parameters.AddWithValue("@TargetCaloriesEnc", FieldCipher.EncryptInt(row.Calories, key));
        update.Parameters.AddWithValue("@TargetProteinGEnc", FieldCipher.EncryptInt(row.Protein, key));
        update.Parameters.AddWithValue("@TargetCarbsGEnc", FieldCipher.EncryptInt(row.Carbs, key));
        update.Parameters.AddWithValue("@TargetFatsGEnc", FieldCipher.EncryptInt(row.Fats, key));
        await update.ExecuteNonQueryAsync();
    }

    Console.WriteLine($"UserNutritionTargets: encrypted {rows.Count} row(s).");
}
