namespace Silen.Services.Helpers;

/// <summary>The allowed onboarding answers, shared by the app's own profile save
/// (UserProfileService) and profiles the partner website sends with a lead
/// (PartnerPayloadCodec), so the two can never drift apart.</summary>
public static class UserProfileRules
{
    public static readonly string[] Genders = ["Male", "Female", "Other"];
    public static readonly string[] Goals = ["BuildMuscle", "LoseFat", "MaintainActive"];
    public static readonly string[] TrainingExperiences = ["Beginner", "Intermediate", "Advanced"];
    public static readonly string[] EquipmentAccesses = ["FullGym", "Dumbbells", "Bodyweight"];
    public static readonly string[] DailyActivityLevels = ["Sedentary", "LightlyActive", "Active", "VeryActive"];

    public const int MinAgeYears = 13;
    public const int MaxAgeYears = 100;
    public const decimal MinHeightCm = 100;
    public const decimal MaxHeightCm = 250;
    public const decimal MinWeightKg = 30;
    public const decimal MaxWeightKg = 300;
    public const int MinTrainingDaysPerWeek = 1;
    public const int MaxTrainingDaysPerWeek = 7;
    public const int MinSessionDurationMinutes = 15;
    public const int MaxSessionDurationMinutes = 180;

    /// <summary>What first-run onboarding saves for session duration - it never asks.</summary>
    public const int DefaultSessionDurationMinutes = 45;
}
