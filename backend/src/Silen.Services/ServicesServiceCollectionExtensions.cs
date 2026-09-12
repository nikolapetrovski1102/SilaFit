using Microsoft.Extensions.DependencyInjection;
using Silen.Services.Abstractions;
using Silen.Services.Implementations;

namespace Silen.Services;

/// <summary>Single place that wires every Services-layer type into DI.</summary>
public static class ServicesServiceCollectionExtensions
{
    public static IServiceCollection AddSilenServices(this IServiceCollection services)
    {
        services.AddScoped<IAuthService, AuthService>();
        services.AddScoped<ITodayService, TodayService>();
        services.AddScoped<IProgressService, ProgressService>();
        services.AddScoped<IPlanService, PlanService>();
        services.AddScoped<ISplitService, SplitService>();
        services.AddScoped<ISettingsService, SettingsService>();
        services.AddScoped<IUserProfileService, UserProfileService>();
        services.AddScoped<IMealPlanningService, MealPlanningService>();
        services.AddScoped<IAnalyticsService, AnalyticsService>();
        services.AddScoped<ISubscriptionGate, SubscriptionGate>();

        services.AddScoped<IGoogleTokenVerifier, GoogleTokenVerifier>();
        services.AddHttpClient<IAppleTokenVerifier, AppleTokenVerifier>();
        services.AddHttpClient<IOpenRouterClient, OpenRouterClient>();

        return services;
    }
}
