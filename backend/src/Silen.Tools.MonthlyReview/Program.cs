// Monthly review batch - see deploy/README.md ("Monthly progress emails").
//
// Two passes, run back to back by default:
//   subscribers -> every active PRO/ADVANCED subscriber gets the full AI
//                  monthly overview (AnalyticsService caches per user+month);
//   free        -> every active non-paying user with logged activity gets a
//                  stats teaser + upgrade CTA. No AI call, so it costs nothing
//                  per recipient and does not give away the paid report.
//
// Idempotent for both: users already emailed for the period are skipped, and
// AI reports are never regenerated once cached, so re-running is cheap.
//
// Intended to be scheduled once a month (deploy.sh installs a cron entry that
// runs it on the 1st). Can also be run by hand for a backfill.
//
// Usage:
//   ConnectionStrings__SilenDb="..." Encryption__MasterKeyBase64="<base64>" \
//   OpenRouter__ApiKey="..." Smtp__Host="smtp.example.com" \
//     dotnet run --project backend/src/Silen.Tools.MonthlyReview
//
// Flags (all optional):
//   --year=2025 --month=8   period to process (default: previous UTC month)
//   --plan=ADVANCED         subscriber plan code to process (default: MonthlyReview:PlanCode)
//   --audience=all          all (default) | subscribers | free
//   --dry-run               generate + store reports/teasers, send no email
//
// Exit codes: 0 = all processed, 1 = a run failed outright, 2 = completed with per-user failures.

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

builder.Services.Configure<OpenRouterOptions>(builder.Configuration.GetSection(OpenRouterOptions.SectionName));
builder.Services.Configure<SmtpOptions>(builder.Configuration.GetSection(SmtpOptions.SectionName));
builder.Services.Configure<EncryptionOptions>(builder.Configuration.GetSection(EncryptionOptions.SectionName));
builder.Services.Configure<MonthlyReviewOptions>(builder.Configuration.GetSection(MonthlyReviewOptions.SectionName));

builder.Services.AddSilenData();
builder.Services.AddSilenServices();

var year = ParseInt(ArgValue(args, "year"));
var month = ParseInt(ArgValue(args, "month"));
var planCode = ArgValue(args, "plan");
var dryRun = HasFlag(args, "dry-run") || HasFlag(args, "no-email");

var audience = (ArgValue(args, "audience") ?? "all").Trim().ToLowerInvariant();
var runSubscribers = audience is "all" or "subscribers";
var runFree = audience is "all" or "free" or "nonsubscribers" or "non-subscribers";
if (!runSubscribers && !runFree)
{
    Console.Error.WriteLine($"Unknown --audience={audience}. Use all, subscribers or free.");
    return 1;
}

using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    cancellation.Cancel();
};

using var host = builder.Build();
using var scope = host.Services.CreateScope();
var reviewService = scope.ServiceProvider.GetRequiredService<IMonthlyReviewService>();

Console.WriteLine($"Monthly review starting (year={year?.ToString() ?? "previous"}, month={month?.ToString() ?? "previous"}, " +
                  $"plan={planCode ?? "configured"}, audience={audience}, dryRun={dryRun}).");

var exitCode = 0;

if (runSubscribers)
{
    Console.WriteLine("Pass 1/2: paying subscribers (full AI report).");
    var result = await reviewService.RunAsync(year, month, planCode, dryRun, cancellation.Token);
    if (!result.IsSuccess || result.Data is null)
    {
        Console.Error.WriteLine($"Monthly review (subscribers) failed: {result.LogMessage ?? result.UserMessage}");
        return 1;
    }

    PrintSummary(result.Data);
    if (result.Data.Failures > 0)
    {
        exitCode = 2;
    }
}

if (runFree)
{
    Console.WriteLine("Pass 2/2: non-paying users (stats teaser + upgrade CTA).");
    var result = await reviewService.RunUpsellAsync(year, month, dryRun, cancellation.Token);
    if (!result.IsSuccess || result.Data is null)
    {
        Console.Error.WriteLine($"Monthly review (non-paying) failed: {result.LogMessage ?? result.UserMessage}");
        return 1;
    }

    PrintSummary(result.Data);
    if (result.Data.Failures > 0)
    {
        exitCode = 2;
    }
}

return exitCode;

static void PrintSummary(MonthlyReviewSummaryDto summary)
{
    Console.WriteLine(JsonSerializer.Serialize(summary, new JsonSerializerOptions { WriteIndented = true }));
    var noun = string.Equals(summary.Audience, MonthlyReviewAudiences.NonSubscribers, StringComparison.Ordinal)
        ? "teaser(s)"
        : "report(s)";
    Console.WriteLine($"Period {summary.Year}-{summary.Month:00} [{summary.Audience}]: {summary.ReportsGenerated} {noun} generated, " +
                      $"{summary.EmailsSent} email(s) sent, {summary.Skipped} skipped, {summary.Failures} failed.");

    foreach (var failure in summary.FailureDetails)
    {
        Console.Error.WriteLine($"  FAILED {failure.UserId} ({failure.Email ?? "no email"}): {failure.Message}");
    }
}

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
