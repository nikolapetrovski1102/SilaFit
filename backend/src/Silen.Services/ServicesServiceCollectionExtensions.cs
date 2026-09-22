using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Silen.Common.Options;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;
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
        services.AddScoped<IExercisesService, ExercisesService>();
        services.AddScoped<IDietPlanService, DietPlanService>();
        services.AddScoped<IDietGuideService, DietGuideService>();
        services.AddScoped<ISettingsService, SettingsService>();
        services.AddScoped<IUserProfileService, UserProfileService>();
        services.AddScoped<IMealPlanningService, MealPlanningService>();
        services.AddScoped<IAnalyticsService, AnalyticsService>();
        services.AddScoped<IMonthlyReviewService, MonthlyReviewService>();
        services.AddScoped<IWeeklyPlanGenerationService, WeeklyPlanGenerationService>();
        services.AddScoped<INotificationService, NotificationService>();
        services.AddScoped<INotificationPublishService, NotificationPublishService>();
        services.AddScoped<ISubscriptionGate, SubscriptionGate>();
        // Singleton: the "force refresh" cooldown must persist across requests.
        services.AddSingleton<IAiRefreshThrottle, AiRefreshThrottle>();
        services.AddScoped<IAdminAuthService, AdminAuthService>();
        services.AddScoped<IAdminRbacService, AdminRbacService>();
        services.AddScoped<IAdminConsoleService, AdminConsoleService>();
        services.AddScoped<IAccountService, AccountService>();
        services.AddScoped<IImageUploadService, ImageUploadService>();
        services.AddScoped<ISubscriptionReceiptService, SubscriptionReceiptService>();

        services.AddScoped<IGoogleTokenVerifier, GoogleTokenVerifier>();
        services.AddHttpClient<IAppleTokenVerifier, AppleTokenVerifier>();
        services.AddHttpClient<IOpenRouterClient, OpenRouterClient>();
        services.AddHttpClient<IAppStoreServerClient, AppStoreServerClient>();
        services.AddHttpClient<IGooglePlayDeveloperClient, GooglePlayDeveloperClient>();
        services.AddScoped<IEmailSender, SmtpEmailSender>();

        // Push transport: a real FCM sender when Push:Enabled with a service
        // account, otherwise a log-only sender that keeps the pipeline working
        // end to end without credentials.
        services.AddHttpClient();
        services.AddScoped<IPushNotificationSender>(sp =>
        {
            var pushOptions = sp.GetRequiredService<IOptions<PushNotificationOptions>>().Value;
            return FcmPushNotificationSender.CanConfigure(pushOptions)
                ? ActivatorUtilities.CreateInstance<FcmPushNotificationSender>(sp)
                : ActivatorUtilities.CreateInstance<LoggingPushNotificationSender>(sp);
        });

        return services;
    }
}
