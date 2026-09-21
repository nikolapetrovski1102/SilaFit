using System.Data;
using Microsoft.Data.SqlClient;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;

namespace Silen.Data.Providers;

/// <inheritdoc cref="IMockDataSeeder"/>
/// <remarks>
/// The seeding functions here were lifted verbatim from the standalone
/// Silen.Tools.SeedMockData console app once the admin console needed to run the
/// same generator against an existing user, so there is exactly one copy of the
/// month-building logic. The constructor takes the connection string and the
/// FieldCipher master key (base64) directly rather than configuration, so the CLI
/// tool can build one from its environment variables and DI can build one from
/// app config.
/// </remarks>
public sealed class MockDataSeeder(string connectionString, string masterKeyBase64) : IMockDataSeeder
{
    // Seeding is hundreds of small inserts over a month; a remote SQL Server can
    // take longer than the driver's 30s default for a single connection's run.
    private const int CommandTimeoutSeconds = 120;

    // Parsed on first use rather than in the constructor: DI builds one of these to
    // satisfy AdminConsoleService for *every* console request, so a missing key must
    // only fail this feature, not the whole console.
    private byte[]? key;

    private byte[] Key => key ??= ResolveKey();

    public IReadOnlyList<string> Profiles => MockDataProfiles.All;

    public async Task<MockDataSeedResult?> SeedUserAsync(
        Guid userId,
        string profile,
        int days,
        int? seed,
        AdminActorModel? actor = null,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken).ConfigureAwait(false);

        if (!await UserExistsAsync(connection, userId, cancellationToken).ConfigureAwait(false))
        {
            return null;
        }

        var result = await SeedCoreAsync(connection, userId, userId.ToString(), profile, days, seed, setDisplayName: false, cancellationToken)
            .ConfigureAwait(false);

        if (actor is not null)
        {
            await WriteAuditAsync(connection, actor, userId, result, cancellationToken).ConfigureAwait(false);
        }

        return result;
    }

    public async Task<MockDataSeedResult> SeedDeviceAsync(
        string deviceId,
        string profile,
        int days,
        int? seed,
        CancellationToken cancellationToken = default)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken).ConfigureAwait(false);

        var userId = await GetOrCreateDeviceUserAsync(connection, deviceId, cancellationToken).ConfigureAwait(false);
        return await SeedCoreAsync(connection, userId, deviceId, profile, days, seed, setDisplayName: true, cancellationToken)
            .ConfigureAwait(false);
    }

    // ---------------------------------------------------------------------
    // One user, start to finish
    // ---------------------------------------------------------------------

    private async Task<MockDataSeedResult> SeedCoreAsync(
        SqlConnection connection, Guid userId, string rngKey, string profile, int days, int? seed,
        bool setDisplayName, CancellationToken cancellationToken)
    {
        if (days <= 0)
        {
            days = 30;
        }

        var spec = ResolveTierSpec(profile);
        var tier = await BuildTierProfileAsync(connection, spec, cancellationToken).ConfigureAwait(false);
        var random = new Random((seed ?? Environment.TickCount) ^ StableHash(rngKey));

        if (setDisplayName)
        {
            await SetDisplayNameAsync(connection, userId, "Mock Test User", cancellationToken).ConfigureAwait(false);
        }

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var goal = random.Next(2) == 0 ? "LoseFat" : "BuildMuscle";
        var startWeightKg = goal == "LoseFat" ? 86.0m : 72.0m;
        var weightTrendPerDay = goal == "LoseFat" ? -0.06m : 0.04m;

        await UpsertProfileAsync(connection, userId, gender: "Male", ageYears: 29, heightCm: 179.0m, weightKg: startWeightKg, goal, cancellationToken)
            .ConfigureAwait(false);

        var targetCalories = goal == "LoseFat" ? 2200 : 2900;
        var targetProtein = goal == "LoseFat" ? 170 : 190;
        var targetCarbs = goal == "LoseFat" ? 210 : 320;
        var targetFats = goal == "LoseFat" ? 65 : 90;
        await UpsertNutritionTargetsAsync(connection, userId, targetCalories, targetProtein, targetCarbs, targetFats, cancellationToken)
            .ConfigureAwait(false);

        await GrantSubscriptionAsync(connection, userId, tier.PlanId, cancellationToken).ConfigureAwait(false);

        // Backdate activation well before the seeded range so the split's own day-cycle
        // math (see usp_WorkoutSession_GetTodayScheduled) lines up for every date we write,
        // and keeps lining up for "today" after this tool has finished running.
        var activatedAtUtc = today.AddDays(-(days + 14)).ToDateTime(TimeOnly.MinValue);
        await ActivateSplitAsync(connection, userId, tier.Split.SplitId, activatedAtUtc, cancellationToken).ConfigureAwait(false);

        await WipeExistingMockDataAsync(connection, userId, cancellationToken).ConfigureAwait(false);

        var startDate = today.AddDays(-(days - 1));
        var sessionsCompleted = 0;
        var sessionsMissed = 0;
        var mealsLogged = 0;
        var hydrationEntries = 0;
        var bodyweightEntries = 0;
        var currentWeightKg = startWeightKg;

        for (var offsetFromStart = 0; offsetFromStart < days; offsetFromStart++)
        {
            var date = startDate.AddDays(offsetFromStart);
            var daysFromToday = (today.ToDateTime(TimeOnly.MinValue) - date.ToDateTime(TimeOnly.MinValue)).Days;

            var cycleIndex = (int)(((date.ToDateTime(TimeOnly.MinValue) - activatedAtUtc).Days % tier.Split.DurationDays + tier.Split.DurationDays) % tier.Split.DurationDays);
            var splitDay = tier.Split.Days.FirstOrDefault(d => d.DayIndex == cycleIndex);

            if (splitDay is not null)
            {
                // The final week is always a hit so there's a live streak the moment
                // someone opens the app right after running this tool; earlier weeks get
                // the tier's own adherence rate, with one deliberate multi-day gap for variety.
                var isGuaranteedHit = daysFromToday <= 6;
                var isDeliberateGapWeek = offsetFromStart is >= 9 and <= 11;
                var completed = splitDay.IsRestDay
                    ? (bool?)null
                    : isGuaranteedHit ? true : !isDeliberateGapWeek && random.NextDouble() < tier.BaseAdherence;

                if (splitDay.IsRestDay)
                {
                    await InsertWorkoutSessionAsync(connection, userId, splitDay.SplitDayId, date, "ActiveRest", null, null, null, null, null, null, cancellationToken)
                        .ConfigureAwait(false);
                }
                else if (completed == true)
                {
                    var (durationMinutes, caloriesEstimate, rpeScore, tonnageKg, setLogs) =
                        BuildCompletedWorkout(splitDay, offsetFromStart, tier.ProgressionScale, random);

                    var sessionId = await InsertWorkoutSessionAsync(
                        connection, userId, splitDay.SplitDayId, date, "Completed",
                        date.ToDateTime(new TimeOnly(7, 0)), date.ToDateTime(new TimeOnly(7, 0)).AddMinutes(durationMinutes),
                        durationMinutes, caloriesEstimate, rpeScore, tonnageKg, cancellationToken).ConfigureAwait(false);
                    await InsertSetLogsAsync(connection, sessionId, userId, setLogs, date.ToDateTime(new TimeOnly(7, 0)).AddMinutes(durationMinutes), cancellationToken)
                        .ConfigureAwait(false);
                    sessionsCompleted++;
                }
                else
                {
                    await InsertWorkoutSessionAsync(connection, userId, splitDay.SplitDayId, date, "Missed", null, null, null, null, null, null, cancellationToken)
                        .ConfigureAwait(false);
                    sessionsMissed++;
                }
            }

            mealsLogged += await SeedMealsAsync(connection, userId, date, targetCalories, targetProtein, targetCarbs, targetFats, tier, random, cancellationToken).ConfigureAwait(false);
            hydrationEntries += await SeedHydrationAsync(connection, userId, date, tier, random, cancellationToken).ConfigureAwait(false);

            // Not every day - a bodyweight log every 2-3 days reads far more like a real
            // user than one at exactly the same time every morning. Always log the very
            // first and last day so the monthly snapshot has a start/end weight to diff.
            var logsBodyweight = offsetFromStart == 0 || offsetFromStart == days - 1 || random.NextDouble() < 0.4;
            if (logsBodyweight)
            {
                currentWeightKg += weightTrendPerDay * (offsetFromStart == 0 ? 0 : 2.5m) + (decimal)(random.NextDouble() * 0.6 - 0.3);
                await InsertBodyweightAsync(connection, userId, date, Math.Round(currentWeightKg, 1), cancellationToken).ConfigureAwait(false);
                bodyweightEntries++;
            }
        }

        return new MockDataSeedResult(
            userId, spec.Label, tier.Split.Name, days,
            sessionsCompleted, sessionsMissed, mealsLogged, hydrationEntries, bodyweightEntries);
    }

    // ---------------------------------------------------------------------
    // Workout generation
    // ---------------------------------------------------------------------

    private static (short DurationMinutes, short CaloriesEstimate, decimal RpeScore, decimal TonnageKg, List<MockSetLog> SetLogs) BuildCompletedWorkout(
        MockSplitDay splitDay, int offsetFromStart, decimal progressionScale, Random random)
    {
        var setLogs = new List<MockSetLog>();
        decimal tonnageKg = 0;

        foreach (var exercise in splitDay.Exercises)
        {
            // Mild progressive overload across the month, heavier for compound lifts,
            // plus per-set noise so it doesn't look machine-generated. progressionScale
            // is the tier knob: Advanced accounts progress at the full rate, Pro accounts
            // at a flatter rate (less consistent training shows up as less overload too).
            var baseWeight = exercise.IsCompound ? 60m : 20m;
            var progression = (decimal)offsetFromStart * (exercise.IsCompound ? 0.35m : 0.15m) * progressionScale;

            for (byte setNumber = 1; setNumber <= exercise.TargetSets; setNumber++)
            {
                var reps = random.Next(exercise.TargetRepsLow, exercise.TargetRepsHigh + 1);
                var weight = Math.Round(baseWeight + progression + (decimal)(random.NextDouble() * 5 - 2.5), 1);
                weight = Math.Max(weight, 2.5m);

                setLogs.Add(new MockSetLog(exercise.ExerciseId, setNumber, weight, (short)reps));
                tonnageKg += weight * reps;
            }
        }

        var durationMinutes = (short)Math.Max(20, splitDay.EstimatedMinutes + random.Next(-10, 15));
        var caloriesEstimate = (short)(durationMinutes * (8 + random.Next(0, 4)));
        var rpeScore = Math.Round(6.5m + (decimal)random.NextDouble() * 2.5m, 1);

        return (durationMinutes, caloriesEstimate, rpeScore, Math.Round(tonnageKg, 2), setLogs);
    }

    // ---------------------------------------------------------------------
    // Meals
    // ---------------------------------------------------------------------

    private async Task<int> SeedMealsAsync(
        SqlConnection connection, Guid userId, DateOnly date,
        int targetCalories, int targetProtein, int targetCarbs, int targetFats, TierProfile tier, Random random,
        CancellationToken cancellationToken)
    {
        // Some days run a bit over target, some under - a flat 100%-of-target every day
        // would make the monthly nutrition adherence chart look fake.
        var dayFactor = 0.85 + random.NextDouble() * 0.3;
        var logged = 0;
        var titles = tier.Spec.Label == "Pro" ? MealCatalog.ProTitles : MealCatalog.AdvancedTitles;

        foreach (var (mealType, baseLoggedChance, plannedTime, share) in MealCatalog.Plan)
        {
            // MealLoggedBonus is the tier knob: Advanced accounts log meals close to plan,
            // Pro accounts log meals less reliably (planned-but-never-logged more often).
            var loggedChance = Math.Clamp(baseLoggedChance + tier.MealLoggedBonus, 0.05, 0.98);
            if (random.NextDouble() > loggedChance + 0.1)
            {
                continue; // some days skip a meal entirely (most often the snack)
            }

            var isLogged = random.NextDouble() < loggedChance;

            // MealJitterScale is the other tier knob: Advanced accounts hit their macro
            // targets fairly precisely, Pro accounts are noisier (wider jitter range)
            // around the same targets.
            var jitterWidth = 0.3 * tier.MealJitterScale;
            var jitter = (1.0 - jitterWidth / 2) + random.NextDouble() * jitterWidth;
            var calories = (int)(targetCalories * share * dayFactor * jitter);
            var protein = (int)(targetProtein * share * dayFactor * jitter);
            var carbs = (int)(targetCarbs * share * dayFactor * jitter);
            var fats = (int)(targetFats * share * dayFactor * jitter);
            var mealTitles = titles[mealType];
            var title = mealTitles[random.Next(mealTitles.Length)];

            await UpsertMealLogAsync(connection, userId, date, mealType, title, calories, protein, carbs, fats,
                isLogged ? "Logged" : "Planned", plannedTime, cancellationToken).ConfigureAwait(false);

            if (isLogged)
            {
                logged++;
            }
        }

        return logged;
    }

    // ---------------------------------------------------------------------
    // Hydration
    // ---------------------------------------------------------------------

    private async Task<int> SeedHydrationAsync(
        SqlConnection connection, Guid userId, DateOnly date, TierProfile tier, Random random, CancellationToken cancellationToken)
    {
        var entryCount = random.Next(tier.HydrationMin, tier.HydrationMax);
        var hour = 7;

        for (var i = 0; i < entryCount; i++)
        {
            hour = Math.Min(22, hour + random.Next(1, 4));
            var amountMl = (short)(random.Next(4, 11) * 50); // 200-500ml, rounded to a real bottle/glass size
            var loggedAtUtc = date.ToDateTime(new TimeOnly(hour, random.Next(0, 60)));
            await InsertHydrationAsync(connection, userId, loggedAtUtc, amountMl, cancellationToken).ConfigureAwait(false);
        }

        return entryCount;
    }

    // ---------------------------------------------------------------------
    // Data access
    // ---------------------------------------------------------------------

    private static async Task<bool> UserExistsAsync(SqlConnection connection, Guid userId, CancellationToken cancellationToken)
    {
        await using var command = NewCommand(connection, "SELECT COUNT(1) FROM dbo.Users WHERE UserId = @UserId");
        command.Parameters.AddWithValue("@UserId", userId);
        return Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false)) > 0;
    }

    private static async Task<Guid> GetOrCreateDeviceUserAsync(SqlConnection connection, string deviceId, CancellationToken cancellationToken)
    {
        await using var command = NewCommand(connection, "dbo.usp_Auth_GetOrCreateDeviceUser", storedProcedure: true);
        command.Parameters.AddWithValue("@DeviceId", deviceId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
        await reader.ReadAsync(cancellationToken).ConfigureAwait(false);
        return reader.GetGuid(reader.GetOrdinal("UserId"));
    }

    private static async Task SetDisplayNameAsync(SqlConnection connection, Guid userId, string displayName, CancellationToken cancellationToken)
    {
        await using var command = NewCommand(connection, "UPDATE dbo.Users SET DisplayName = @DisplayName WHERE UserId = @UserId");
        command.Parameters.AddWithValue("@DisplayName", displayName);
        command.Parameters.AddWithValue("@UserId", userId);
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task UpsertProfileAsync(
        SqlConnection connection, Guid userId, string gender, int ageYears, decimal heightCm, decimal weightKg, string goal,
        CancellationToken cancellationToken)
    {
        await using var command = NewCommand(connection, "dbo.usp_UserProfile_Upsert", storedProcedure: true);
        command.Parameters.AddWithValue("@UserId", userId);
        command.Parameters.AddWithValue("@Gender", FieldCipher.EncryptString(gender, Key));
        command.Parameters.AddWithValue("@AgeYears", FieldCipher.EncryptInt(ageYears, Key));
        command.Parameters.AddWithValue("@HeightCm", FieldCipher.EncryptDecimal(heightCm, Key));
        command.Parameters.AddWithValue("@WeightKg", FieldCipher.EncryptDecimal(weightKg, Key));
        command.Parameters.AddWithValue("@Goal", FieldCipher.EncryptString(goal, Key));
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task UpsertNutritionTargetsAsync(
        SqlConnection connection, Guid userId, int calories, int protein, int carbs, int fats, CancellationToken cancellationToken)
    {
        await using var command = NewCommand(connection, "dbo.usp_UserNutritionTargets_Upsert", storedProcedure: true);
        command.Parameters.AddWithValue("@UserId", userId);
        command.Parameters.AddWithValue("@TargetCalories", FieldCipher.EncryptInt(calories, Key));
        command.Parameters.AddWithValue("@TargetProteinG", FieldCipher.EncryptInt(protein, Key));
        command.Parameters.AddWithValue("@TargetCarbsG", FieldCipher.EncryptInt(carbs, Key));
        command.Parameters.AddWithValue("@TargetFatsG", FieldCipher.EncryptInt(fats, Key));
        command.Parameters.AddWithValue("@IsManualOverride", false);
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private static async Task<Guid> GetPlanIdAsync(SqlConnection connection, string code, CancellationToken cancellationToken)
    {
        await using var command = NewCommand(connection, "SELECT PlanId FROM dbo.SubscriptionPlans WHERE Code = @Code");
        command.Parameters.AddWithValue("@Code", code);
        var result = await command.ExecuteScalarAsync(cancellationToken).ConfigureAwait(false)
            ?? throw new InvalidOperationException($"Subscription plan '{code}' not found - run database/seed/001_SeedReferenceData.sql first.");
        return (Guid)result;
    }

    private static async Task GrantSubscriptionAsync(SqlConnection connection, Guid userId, Guid planId, CancellationToken cancellationToken)
    {
        // Yearly so it stays active for the whole time someone will spend poking at this
        // mock account, and so Pro/Advanced-gated features are reachable without relying
        // on the FeatureFlags:DevTiersFree escape hatch.
        await using var command = NewCommand(connection, "dbo.usp_Subscription_Purchase", storedProcedure: true);
        command.Parameters.AddWithValue("@UserId", userId);
        command.Parameters.AddWithValue("@PlanId", planId);
        command.Parameters.AddWithValue("@BillingCycle", "Yearly");
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private static async Task ActivateSplitAsync(SqlConnection connection, Guid userId, Guid splitId, DateTime activatedAtUtc, CancellationToken cancellationToken)
    {
        const string sql = """
            MERGE dbo.UserActiveSplits AS target
            USING (SELECT @UserId AS UserId) AS source ON target.UserId = source.UserId
            WHEN MATCHED THEN UPDATE SET SplitId = @SplitId, ActivatedAtUtc = @ActivatedAtUtc
            WHEN NOT MATCHED THEN INSERT (UserId, SplitId, ActivatedAtUtc) VALUES (@UserId, @SplitId, @ActivatedAtUtc);
            """;
        await using var command = NewCommand(connection, sql);
        command.Parameters.AddWithValue("@UserId", userId);
        command.Parameters.AddWithValue("@SplitId", splitId);
        command.Parameters.AddWithValue("@ActivatedAtUtc", activatedAtUtc);
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private static async Task WipeExistingMockDataAsync(SqlConnection connection, Guid userId, CancellationToken cancellationToken)
    {
        const string sql = """
            -- Cached recaps contain snapshots of the logs below. They must be
            -- invalidated in the same seed operation or a test account can keep
            -- showing a pre-seed weekly/monthly report until its cache expires.
            DELETE FROM dbo.WeeklyAnalyticsReports WHERE UserId = @UserId;
            DELETE FROM dbo.MonthlyAnalyticsReports WHERE UserId = @UserId;
            DELETE FROM dbo.WorkoutSetLogs WHERE UserId = @UserId;
            DELETE FROM dbo.WorkoutSessions WHERE UserId = @UserId;
            DELETE FROM dbo.MealLogs WHERE UserId = @UserId;
            DELETE FROM dbo.HydrationLogs WHERE UserId = @UserId;
            DELETE FROM dbo.BodyweightLogs WHERE UserId = @UserId;
            """;
        await using var command = NewCommand(connection, sql);
        command.Parameters.AddWithValue("@UserId", userId);
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private static async Task<Guid> InsertWorkoutSessionAsync(
        SqlConnection connection, Guid userId, Guid splitDayId, DateOnly scheduledDateUtc, string status,
        DateTime? startedAtUtc, DateTime? completedAtUtc, short? durationMinutes, short? caloriesEstimate,
        decimal? rpeScore, decimal? tonnageKg, CancellationToken cancellationToken)
    {
        var sessionId = Guid.NewGuid();
        const string sql = """
            INSERT INTO dbo.WorkoutSessions
                (WorkoutSessionId, UserId, SplitDayId, ScheduledDateUtc, Status, StartedAtUtc, CompletedAtUtc,
                 DurationMinutes, CaloriesEstimate, RpeScore, TonnageKg)
            VALUES
                (@WorkoutSessionId, @UserId, @SplitDayId, @ScheduledDateUtc, @Status, @StartedAtUtc, @CompletedAtUtc,
                 @DurationMinutes, @CaloriesEstimate, @RpeScore, @TonnageKg);
            """;
        await using var command = NewCommand(connection, sql);
        command.Parameters.AddWithValue("@WorkoutSessionId", sessionId);
        command.Parameters.AddWithValue("@UserId", userId);
        command.Parameters.AddWithValue("@SplitDayId", splitDayId);
        command.Parameters.AddWithValue("@ScheduledDateUtc", scheduledDateUtc.ToDateTime(TimeOnly.MinValue));
        command.Parameters.AddWithValue("@Status", status);
        command.Parameters.AddWithValue("@StartedAtUtc", (object?)startedAtUtc ?? DBNull.Value);
        command.Parameters.AddWithValue("@CompletedAtUtc", (object?)completedAtUtc ?? DBNull.Value);
        command.Parameters.AddWithValue("@DurationMinutes", (object?)durationMinutes ?? DBNull.Value);
        command.Parameters.AddWithValue("@CaloriesEstimate", (object?)caloriesEstimate ?? DBNull.Value);
        command.Parameters.AddWithValue("@RpeScore", (object?)rpeScore ?? DBNull.Value);
        command.Parameters.AddWithValue("@TonnageKg", (object?)tonnageKg ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
        return sessionId;
    }

    private static async Task InsertSetLogsAsync(
        SqlConnection connection, Guid sessionId, Guid userId, List<MockSetLog> setLogs, DateTime completedAtUtc, CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO dbo.WorkoutSetLogs (WorkoutSessionId, UserId, ExerciseId, SetNumber, WeightKg, Reps, CompletedAtUtc)
            VALUES (@WorkoutSessionId, @UserId, @ExerciseId, @SetNumber, @WeightKg, @Reps, @CompletedAtUtc);
            """;
        foreach (var setLog in setLogs)
        {
            await using var command = NewCommand(connection, sql);
            command.Parameters.AddWithValue("@WorkoutSessionId", sessionId);
            command.Parameters.AddWithValue("@UserId", userId);
            command.Parameters.AddWithValue("@ExerciseId", setLog.ExerciseId);
            command.Parameters.AddWithValue("@SetNumber", setLog.SetNumber);
            command.Parameters.AddWithValue("@WeightKg", setLog.WeightKg);
            command.Parameters.AddWithValue("@Reps", setLog.Reps);
            command.Parameters.AddWithValue("@CompletedAtUtc", completedAtUtc);
            await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
        }
    }

    private async Task UpsertMealLogAsync(
        SqlConnection connection, Guid userId, DateOnly logDateUtc, string mealType, string title,
        int calories, int protein, int carbs, int fats, string status, TimeOnly plannedLocalTime, CancellationToken cancellationToken)
    {
        await using var command = NewCommand(connection, "dbo.usp_MealLogs_Upsert", storedProcedure: true);
        command.Parameters.AddWithValue("@MealLogId", DBNull.Value);
        command.Parameters.AddWithValue("@UserId", userId);
        command.Parameters.AddWithValue("@LogDateUtc", logDateUtc.ToDateTime(TimeOnly.MinValue));
        command.Parameters.AddWithValue("@MealType", mealType);
        command.Parameters.AddWithValue("@Title", FieldCipher.EncryptString(title, Key));
        command.Parameters.AddWithValue("@CaloriesKcal", FieldCipher.EncryptInt(calories, Key));
        command.Parameters.AddWithValue("@ProteinG", FieldCipher.EncryptInt(protein, Key));
        command.Parameters.AddWithValue("@CarbsG", FieldCipher.EncryptInt(carbs, Key));
        command.Parameters.AddWithValue("@FatsG", FieldCipher.EncryptInt(fats, Key));
        command.Parameters.AddWithValue("@Status", status);
        command.Parameters.AddWithValue("@PlannedLocalTime", plannedLocalTime);
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private static async Task InsertHydrationAsync(SqlConnection connection, Guid userId, DateTime loggedAtUtc, short amountMl, CancellationToken cancellationToken)
    {
        const string sql = "INSERT INTO dbo.HydrationLogs (UserId, LoggedAtUtc, AmountMl) VALUES (@UserId, @LoggedAtUtc, @AmountMl);";
        await using var command = NewCommand(connection, sql);
        command.Parameters.AddWithValue("@UserId", userId);
        command.Parameters.AddWithValue("@LoggedAtUtc", loggedAtUtc);
        command.Parameters.AddWithValue("@AmountMl", amountMl);
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task InsertBodyweightAsync(SqlConnection connection, Guid userId, DateOnly date, decimal weightKg, CancellationToken cancellationToken)
    {
        const string sql = "INSERT INTO dbo.BodyweightLogs (UserId, LoggedAtUtc, WeightKg) VALUES (@UserId, @LoggedAtUtc, @WeightKg);";
        await using var command = NewCommand(connection, sql);
        command.Parameters.AddWithValue("@UserId", userId);
        command.Parameters.AddWithValue("@LoggedAtUtc", date.ToDateTime(new TimeOnly(6, 30)));
        command.Parameters.AddWithValue("@WeightKg", FieldCipher.EncryptDecimal(weightKg, Key));
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private static async Task WriteAuditAsync(
        SqlConnection connection, AdminActorModel actor, Guid userId, MockDataSeedResult result, CancellationToken cancellationToken)
    {
        const string sql = """
            INSERT INTO dbo.AdminAuditLog (AdminUserId, Username, Action, EntityType, EntityId, Summary, CreatedFromIp)
            VALUES (@AdminUserId, @Username, N'Seed mock data', N'User', @EntityId, @Summary, @Ip);
            """;
        await using var command = NewCommand(connection, sql);
        command.Parameters.AddWithValue("@AdminUserId", (object?)actor.AdminUserId ?? DBNull.Value);
        command.Parameters.AddWithValue("@Username", actor.Username);
        command.Parameters.AddWithValue("@EntityId", userId.ToString());
        command.Parameters.AddWithValue(
            "@Summary",
            $"Generated {result.Days} day(s) of {result.Profile} mock data ({result.WorkoutsCompleted} workouts, {result.MealsLogged} meals logged).");
        command.Parameters.AddWithValue("@Ip", (object?)actor.Ip ?? DBNull.Value);
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);
    }

    private async Task<TierProfile> BuildTierProfileAsync(SqlConnection connection, TierSpec spec, CancellationToken cancellationToken)
    {
        var planId = await GetPlanIdAsync(connection, spec.PlanCode, cancellationToken).ConfigureAwait(false);
        var split = await LoadSplitAsync(connection, spec.SplitCategory, cancellationToken).ConfigureAwait(false);
        return new TierProfile(spec, planId, split);
    }

    private static async Task<MockSplit> LoadSplitAsync(SqlConnection connection, string category, CancellationToken cancellationToken)
    {
        Guid splitId;
        string name;
        byte durationDays;

        const string splitSql = """
            SELECT TOP (1) SplitId, Name, DurationDays
            FROM dbo.WorkoutSplits
            WHERE IsSystemDefault = 1 AND Category = @Category
            ORDER BY SortOrder;
            """;
        await using (var command = NewCommand(connection, splitSql))
        {
            command.Parameters.AddWithValue("@Category", category);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
            if (!await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
            {
                throw new InvalidOperationException($"No system-default '{category}' split found - run database/seed/001_SeedReferenceData.sql first.");
            }

            splitId = reader.GetGuid(0);
            name = reader.GetString(1);
            durationDays = reader.GetByte(2);
        }

        var days = new List<MockSplitDay>();
        const string daysSql = "SELECT SplitDayId, DayIndex, EstimatedMinutes, IsRestDay FROM dbo.SplitDays WHERE SplitId = @SplitId ORDER BY DayIndex;";
        await using (var command = NewCommand(connection, daysSql))
        {
            command.Parameters.AddWithValue("@SplitId", splitId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
            while (await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
            {
                days.Add(new MockSplitDay(
                    reader.GetGuid(0), reader.GetByte(1), reader.GetInt16(2), reader.GetBoolean(3), []));
            }
        }

        const string exercisesSql = """
            SELECT sde.SplitDayId, sde.ExerciseId, e.IsCompound, sde.TargetSets, sde.TargetRepsLow, sde.TargetRepsHigh
            FROM dbo.SplitDayExercises sde
            INNER JOIN dbo.Exercises e ON e.ExerciseId = sde.ExerciseId
            WHERE sde.SplitDayId IN (SELECT SplitDayId FROM dbo.SplitDays WHERE SplitId = @SplitId)
            ORDER BY sde.SplitDayId, sde.SortOrder;
            """;
        await using (var command = NewCommand(connection, exercisesSql))
        {
            command.Parameters.AddWithValue("@SplitId", splitId);
            await using var reader = await command.ExecuteReaderAsync(cancellationToken).ConfigureAwait(false);
            while (await reader.ReadAsync(cancellationToken).ConfigureAwait(false))
            {
                var splitDayId = reader.GetGuid(0);
                var day = days.First(d => d.SplitDayId == splitDayId);
                day.Exercises.Add(new MockSplitExercise(
                    reader.GetGuid(1), reader.GetBoolean(2), reader.GetByte(3), reader.GetByte(4), reader.GetByte(5)));
            }
        }

        return new MockSplit(splitId, name, durationDays, days);
    }

    // ---------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------

    private byte[] ResolveKey()
    {
        if (string.IsNullOrWhiteSpace(masterKeyBase64))
        {
            throw new InvalidOperationException(
                "The encryption master key is not configured (Encryption:MasterKeyBase64 / ENCRYPTION_MASTER_KEY); mock-data seeding needs it.");
        }

        var resolved = Convert.FromBase64String(masterKeyBase64);
        if (resolved.Length != FieldCipher.KeySizeBytes)
        {
            throw new InvalidOperationException(
                $"The encryption master key must decode to {FieldCipher.KeySizeBytes} bytes, got {resolved.Length}.");
        }

        return resolved;
    }

    private static SqlCommand NewCommand(SqlConnection connection, string commandText, bool storedProcedure = false)
    {
        var command = new SqlCommand(commandText, connection) { CommandTimeout = CommandTimeoutSeconds };
        if (storedProcedure)
        {
            command.CommandType = CommandType.StoredProcedure;
        }

        return command;
    }

    private static TierSpec ResolveTierSpec(string profile) =>
        profile switch
        {
            MockDataProfiles.Advanced => TierProfiles.Advanced,
            MockDataProfiles.Pro => TierProfiles.Pro,
            _ => throw new ArgumentOutOfRangeException(nameof(profile), profile, "Unknown mock-data profile.")
        };

    // string.GetHashCode() is randomized per process, so it can't be used to seed a
    // Random and still call the run reproducible - this is deterministic instead.
    private static int StableHash(string value)
    {
        unchecked
        {
            var hash = 17;
            foreach (var c in value)
            {
                hash = hash * 31 + c;
            }

            return hash;
        }
    }
}

// ---------------------------------------------------------------------
// Generation models (private to the seeder)
// ---------------------------------------------------------------------

internal sealed record MockSplit(Guid SplitId, string Name, byte DurationDays, List<MockSplitDay> Days);

internal sealed record MockSplitDay(Guid SplitDayId, byte DayIndex, short EstimatedMinutes, bool IsRestDay, List<MockSplitExercise> Exercises);

internal sealed record MockSplitExercise(Guid ExerciseId, bool IsCompound, byte TargetSets, byte TargetRepsLow, byte TargetRepsHigh);

internal sealed record MockSetLog(Guid ExerciseId, byte SetNumber, decimal WeightKg, short Reps);

// A tier's generation knobs, before the split/plan lookups have run.
internal sealed record TierSpec(
    string Label,
    string PlanCode,
    string SplitCategory,
    double BaseAdherence,
    decimal ProgressionScale,
    double MealJitterScale,
    double MealLoggedBonus,
    int HydrationMin,
    int HydrationMax);

// A tier's knobs plus the resolved plan id and workout split, ready to hand to
// the per-user seeding functions.
internal sealed record TierProfile(TierSpec Spec, Guid PlanId, MockSplit Split)
{
    public double BaseAdherence => Spec.BaseAdherence;
    public decimal ProgressionScale => Spec.ProgressionScale;
    public double MealJitterScale => Spec.MealJitterScale;
    public double MealLoggedBonus => Spec.MealLoggedBonus;
    public int HydrationMin => Spec.HydrationMin;
    public int HydrationMax => Spec.HydrationMax;
}

internal static class TierProfiles
{
    // Advanced is the pricier/premium tier (see database/seed/001_SeedReferenceData.sql):
    // heavier split, tighter adherence, precise macro logging - today's original
    // (pre-tier-split) behavior, kept as the baseline.
    public static readonly TierSpec Advanced = new(
        Label: "Advanced",
        PlanCode: "ADVANCED",
        SplitCategory: "PushPullLegs",
        BaseAdherence: 0.8,
        ProgressionScale: 1.0m,
        MealJitterScale: 1.0,
        MealLoggedBonus: 0.0,
        HydrationMin: 4,
        HydrationMax: 8);

    // Pro is the cheaper tier: simpler split, looser adherence, flatter progressive
    // overload, and noisier/less-reliable meal logging - a believable "here some
    // days, off other days" account.
    public static readonly TierSpec Pro = new(
        Label: "Pro",
        PlanCode: "PRO",
        SplitCategory: "UpperLower",
        BaseAdherence: 0.6,
        ProgressionScale: 0.5m,
        MealJitterScale: 1.6,
        MealLoggedBonus: -0.15,
        HydrationMin: 3,
        HydrationMax: 6);
}

internal static class MealCatalog
{
    public static readonly (string MealType, double BaseLoggedChance, TimeOnly PlannedTime, double ShareOfDailyTarget)[] Plan =
    [
        ("Breakfast", 0.9, new TimeOnly(8, 0), 0.25),
        ("Lunch", 0.9, new TimeOnly(13, 0), 0.3),
        ("Dinner", 0.85, new TimeOnly(19, 0), 0.3),
        ("Snack", 0.55, new TimeOnly(16, 0), 0.15)
    ];

    // Advanced accounts read as deliberate meal-prep; Pro accounts read as grabbing
    // whatever's convenient - a small, low-risk way for the two tiers' demo data to
    // look different in the app's meal list too, not just in the underlying numbers.
    public static readonly IReadOnlyDictionary<string, string[]> AdvancedTitles = new Dictionary<string, string[]>
    {
        ["Breakfast"] = ["Egg White Omelet & Oats", "Greek Yogurt, Berries & Granola", "Protein Pancakes", "Overnight Oats & Whey", "Cottage Cheese & Fruit Bowl"],
        ["Lunch"] = ["Meal-Prepped Chicken & Rice", "Grilled Salmon & Quinoa", "Lean Beef & Sweet Potato Bowl", "Turkey Meatballs & Brown Rice", "Tuna & Bean Salad"],
        ["Dinner"] = ["Baked Cod & Roasted Veggies", "Sirloin Steak & Asparagus", "Chicken Breast & Wild Rice", "Turkey Chili (Meal-Prepped)", "Shrimp & Broccoli Stir-Fry"],
        ["Snack"] = ["Whey Protein Shake", "Cottage Cheese", "Almonds & Protein Bar", "Rice Cakes & Peanut Butter", "Hard-Boiled Eggs"],
    };

    public static readonly IReadOnlyDictionary<string, string[]> ProTitles = new Dictionary<string, string[]>
    {
        ["Breakfast"] = ["Drive-Thru Breakfast Sandwich", "Cereal & Milk", "Coffee & a Bagel", "Protein Bar on the Go", "Toast & Peanut Butter"],
        ["Lunch"] = ["Chipotle-Style Bowl", "Deli Sandwich", "Chicken Wrap (Takeout)", "Poke Bowl", "Leftovers"],
        ["Dinner"] = ["Takeout Pad Thai", "Frozen Pizza", "Burger & Fries", "Pasta with Jar Sauce", "Delivery Burrito"],
        ["Snack"] = ["Chips", "Store-Bought Protein Shake", "Trail Mix", "Granola Bar", "Fruit"],
    };
}
