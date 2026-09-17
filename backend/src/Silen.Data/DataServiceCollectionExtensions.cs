using Microsoft.Extensions.Configuration;
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
        services.AddScoped<IDietPlansProvider, DietPlansProvider>();
        services.AddScoped<IDietGuidesProvider, DietGuidesProvider>();
        services.AddScoped<IPlansProvider, PlansProvider>();
        services.AddScoped<IUserProfileProvider, UserProfileProvider>();
        services.AddScoped<IMealPlanningProvider, MealPlanningProvider>();
        services.AddScoped<IAnalyticsProvider, AnalyticsProvider>();
        services.AddScoped<IMonthlyReviewProvider, MonthlyReviewProvider>();
        services.AddScoped<IWeeklyPlanGenerationProvider, WeeklyPlanGenerationProvider>();
        services.AddScoped<INotificationProvider, NotificationProvider>();
        services.AddScoped<IAdminProvider, AdminProvider>();
        services.AddScoped<IAdminRbacProvider, AdminRbacProvider>();
        services.AddScoped<IAdminContentProvider, AdminContentProvider>();
        services.AddScoped<IAccountProvider, AccountProvider>();

        // Singleton like SqlExecutor: it holds no per-request state, and the CLI tool
        // builds the same type from environment variables rather than DI, which is why
        // the constructor takes plain values instead of IConfiguration/IOptions.
        services.AddSingleton<IMockDataSeeder>(serviceProvider =>
        {
            var configuration = serviceProvider.GetRequiredService<IConfiguration>();
            var connectionString = configuration.GetConnectionString("SilenDb")
                ?? throw new InvalidOperationException("Connection string 'SilenDb' is not configured.");

            // The key is passed through raw and parsed on first use by the seeder, so
            // a missing/malformed key breaks only the mock-data action, not every
            // console request that happens to construct AdminConsoleService.
            return new MockDataSeeder(connectionString, configuration["Encryption:MasterKeyBase64"] ?? string.Empty);
        });

        return services;
    }
}
