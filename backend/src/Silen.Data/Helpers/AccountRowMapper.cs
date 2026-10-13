using Npgsql;
using Silen.Common.Models;

namespace Silen.Data.Helpers;

/// <summary>Outside helper mapping the export-only rows usp_Account_Export introduces
/// (identities/hydration-history/workout-session-history/set-log-history) - every
/// other section of the export reuses an existing feature's row mapper.</summary>
public static class AccountRowMapper
{
    public static LinkedIdentityModel MapLinkedIdentity(NpgsqlDataReader reader) => new()
    {
        Provider = reader.GetStringValue("Provider"),
        ExternalId = reader.GetStringValue("ExternalId"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc")
    };

    public static HydrationEntryModel MapHydrationEntry(NpgsqlDataReader reader) => new()
    {
        HydrationLogId = reader.GetGuidValue("HydrationLogId"),
        AmountMl = reader.GetInt16Value("AmountMl"),
        LoggedAtUtc = reader.GetDateTimeValue("LoggedAtUtc")
    };

    public static WorkoutSessionHistoryModel MapWorkoutSessionHistory(NpgsqlDataReader reader) => new()
    {
        WorkoutSessionId = reader.GetGuidValue("WorkoutSessionId"),
        ScheduledDateUtc = reader.GetDateTimeValue("ScheduledDateUtc"),
        Status = reader.GetStringValue("Status"),
        StartedAtUtc = reader.GetNullableDateTime("StartedAtUtc"),
        CompletedAtUtc = reader.GetNullableDateTime("CompletedAtUtc"),
        DurationMinutes = reader.GetNullableInt16("DurationMinutes"),
        CaloriesEstimate = reader.GetNullableInt16("CaloriesEstimate"),
        RpeScore = reader.GetNullableDecimal("RpeScore"),
        TonnageKg = reader.GetNullableDecimal("TonnageKg"),
        CreatedAtUtc = reader.GetDateTimeValue("CreatedAtUtc")
    };

    public static WorkoutSetLogEntryModel MapWorkoutSetLogEntry(NpgsqlDataReader reader) => new()
    {
        WorkoutSetLogId = reader.GetGuidValue("WorkoutSetLogId"),
        WorkoutSessionId = reader.GetGuidValue("WorkoutSessionId"),
        ExerciseId = reader.GetGuidValue("ExerciseId"),
        SetNumber = reader.GetByteValue("SetNumber"),
        WeightKg = reader.GetDecimalValue("WeightKg"),
        Reps = reader.GetInt16Value("Reps"),
        CompletedAtUtc = reader.GetDateTimeValue("CompletedAtUtc")
    };
}
