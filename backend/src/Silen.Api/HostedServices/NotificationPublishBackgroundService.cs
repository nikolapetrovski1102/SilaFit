using Microsoft.Extensions.Options;
using Silen.Common.Options;
using Silen.Services.Abstractions;

namespace Silen.Api.HostedServices;

/// <summary>
/// Optional in-process host for the notification publisher. Off by default
/// (NotificationPublish:RunInApi) because the deployment runs the same service
/// from a frequent cron entry; the dedupe keys make an accidental overlap
/// harmless, just redundant. Handy when you'd rather not have a system cron.
/// </summary>
public sealed class NotificationPublishBackgroundService(
    IServiceScopeFactory scopeFactory,
    IOptions<NotificationPublishOptions> options,
    ILogger<NotificationPublishBackgroundService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var settings = options.Value;
        if (!settings.Enabled || !settings.RunInApi)
        {
            logger.LogInformation("In-API notification publisher is disabled (RunInApi={RunInApi}).", settings.RunInApi);
            return;
        }

        var interval = TimeSpan.FromMinutes(Math.Max(1, settings.PollMinutes));
        logger.LogInformation("In-API notification publisher started (every {Interval}).", interval);

        using var timer = new PeriodicTimer(interval);
        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                await RunOnceAsync(stoppingToken).ConfigureAwait(false);
                if (!await timer.WaitForNextTickAsync(stoppingToken).ConfigureAwait(false))
                {
                    break;
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Normal shutdown.
        }
    }

    private async Task RunOnceAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var scope = scopeFactory.CreateScope();
            var publisher = scope.ServiceProvider.GetRequiredService<INotificationPublishService>();
            var result = await publisher.RunAsync(cancellationToken: cancellationToken).ConfigureAwait(false);

            if (!result.IsSuccess || result.Data is null)
            {
                logger.LogError("Notification publish run failed: {Message}", result.LogMessage ?? result.UserMessage);
                return;
            }

            logger.LogInformation(
                "Notification publish: candidates={Candidates} created={Created} sent={Sent} skipped={Skipped} failed={Failed}.",
                result.Data.CandidatesConsidered, result.Data.Created, result.Data.Sent,
                result.Data.Skipped, result.Data.Failed);

            var flushResult = await publisher.FlushPendingAsync(cancellationToken: cancellationToken).ConfigureAwait(false);
            if (flushResult.IsSuccess && flushResult.Data is not null)
            {
                logger.LogInformation(
                    "Notification pending flush: considered={Considered} sent={Sent} skipped={Skipped} failed={Failed}.",
                    flushResult.Data.PendingConsidered, flushResult.Data.PendingSent,
                    flushResult.Data.PendingSkipped, flushResult.Data.PendingFailed);
            }
            else
            {
                logger.LogError(
                    "Notification pending flush failed: {Message}",
                    flushResult.LogMessage ?? flushResult.UserMessage);
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            // Shutting down.
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Notification publish run threw.");
        }
    }
}
