using Microsoft.Extensions.DependencyInjection;
using Silen.Data.Abstractions;
using Silen.Data.Providers;

namespace Silen.Data;

/// <summary>Single place that wires every Data-layer type into DI.</summary>
public static class DataServiceCollectionExtensions
{
    public static IServiceCollection AddSilenData(this IServiceCollection services)
    {
        services.AddSingleton<ISqlExecutor, SqlExecutor>();

        services.AddScoped<IAuthProvider, AuthProvider>();
        services.AddScoped<IUserSettingsProvider, UserSettingsProvider>();
        services.AddScoped<IHydrationProvider, HydrationProvider>();
        services.AddScoped<IBodyweightProvider, BodyweightProvider>();
        services.AddScoped<IStreakProvider, StreakProvider>();
        services.AddScoped<IWorkoutSessionProvider, WorkoutSessionProvider>();
        services.AddScoped<ISplitsProvider, SplitsProvider>();
        services.AddScoped<IExercisesProvider, ExercisesProvider>();
        services.AddScoped<IPlansProvider, PlansProvider>();
        services.AddScoped<IUserProfileProvider, UserProfileProvider>();
        services.AddScoped<IMealPlanningProvider, MealPlanningProvider>();
        services.AddScoped<IAnalyticsProvider, AnalyticsProvider>();

        return services;
    }
}
