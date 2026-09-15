// Notification publish batch - see deploy/README.md ("Push reminders").
//
// Walks every opted-in user with an active device token, works out each one's
// local time from their stored timezone, and sends at most one due reminder
// (gym time, log-your-sets, calories/meal idea, motivation, or the comeback
// message after a couple of quiet days). Idempotent: every candidate has a
// dedupe key, so running this every few minutes never double-sends.
//
// Intended to be scheduled frequently (deploy.sh installs a cron entry every
// five minutes). Can be run by hand for testing or a backfill.
//
// Usage:
//   ConnectionStrings__SilenDb="..." \
//   Push__Enabled="true" Push__ProjectId="..." Push__ServiceAccountJsonPath="/secrets/fcm.json" \
//     dotnet run --project backend/src/Silen.Tools.NotificationPublish
//
// Flags (all optional):
//   --dry-run         decide + log what would send, write nothing
//   --user=<guid>     only process one user (handy for testing)
//   --limit=<n>       only process the first n candidates
//   --no-flush        skip the pending-flush pass (see deploy/README.md)
//
// Exit codes: 0 = all processed, 1 = the run failed outright, 2 = completed with failures.

using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Silen.Common.Dtos;
using Silen.Common.Options;
using Silen.Data;
using Silen.Services;
using Silen.Services.Abstractions;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.Configure<NotificationPublishOptions>(builder.Configuration.GetSection(NotificationPublishOptions.SectionName));
builder.Services.Configure<PushNotificationOptions>(builder.Configuration.GetSection(PushNotificationOptions.SectionName));

builder.Services.AddSilenData();
builder.Services.AddSilenServices();

var dryRun = HasFlag(args, "dry-run");
var onlyUser = ParseGuid(ArgValue(args, "user"));
var limit = ParseInt(ArgValue(args, "limit"));
var noFlush = HasFlag(args, "no-flush");

using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    cancellation.Cancel();
};

using var host = builder.Build();
using var scope = host.Services.CreateScope();
var publisher = scope.ServiceProvider.GetRequiredService<INotificationPublishService>();

Console.WriteLine(
    $"Notification publish starting (dryRun={dryRun}, user={onlyUser?.ToString() ?? "all"}, limit={limit?.ToString() ?? "none"}).");

var result = await publisher.RunAsync(dryRun, onlyUser, limit, cancellation.Token);
if (!result.IsSuccess || result.Data is null)
{
    Console.Error.WriteLine($"Notification publish failed: {result.LogMessage ?? result.UserMessage}");
    return 1;
}

var summary = result.Data;
Console.WriteLine(JsonSerializer.Serialize(summary, new JsonSerializerOptions { WriteIndented = true }));

if (!summary.PushConfigured)
{
    Console.WriteLine("NOTE: no push provider configured (Push:Enabled + service account). " +
                      "Messages were recorded by the log-only sender instead of being delivered.");
}

Console.WriteLine(
    $"Candidates {summary.CandidatesConsidered}: wouldSend {summary.WouldSend}, created {summary.Created}, " +
    $"sent {summary.Sent}, skipped {summary.Skipped}, suppressed {summary.Suppressed}, failed {summary.Failed}.");

var failures = new List<NotificationPublishFailureDto>(summary.Failures);

if (!noFlush)
{
    var flushResult = await publisher.FlushPendingAsync(dryRun, onlyUser, cancellation.Token);
    if (!flushResult.IsSuccess || flushResult.Data is null)
    {
        Console.Error.WriteLine($"Pending flush failed: {flushResult.LogMessage ?? flushResult.UserMessage}");
        return 1;
    }

    var flush = flushResult.Data;
    Console.WriteLine(
        $"Pending flush: considered {flush.PendingConsidered}, sent {flush.PendingSent}, " +
        $"skipped {flush.PendingSkipped}, failed {flush.PendingFailed}.");
    failures.AddRange(flush.Failures);
}

if (failures.Count > 0)
{
    foreach (var failure in failures)
    {
        Console.Error.WriteLine($"  FAILED {failure.UserId} ({failure.Category}): {failure.Message}");
    }

    return 2;
}

return 0;

static string? ArgValue(string[] args, string name)
{
    var prefix = $"--{name}=";
    for (var i = 0; i < args.Length; i++)
    {
        if (args[i].StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return args[i][prefix.Length..];
        }

        if (string.Equals(args[i], $"--{name}", StringComparison.OrdinalIgnoreCase)
            && i + 1 < args.Length
            && !args[i + 1].StartsWith("--", StringComparison.Ordinal))
        {
            return args[i + 1];
        }
    }

    return null;
}

static bool HasFlag(string[] args, string name) =>
    args.Any(a => string.Equals(a, $"--{name}", StringComparison.OrdinalIgnoreCase)
                  || a.StartsWith($"--{name}=", StringComparison.OrdinalIgnoreCase));

static int? ParseInt(string? value) => int.TryParse(value, out var parsed) ? parsed : null;

static Guid? ParseGuid(string? value) => Guid.TryParse(value, out var parsed) ? parsed : null;
