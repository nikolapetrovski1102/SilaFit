// Subscription reconciliation batch - see deploy/README.md ("Subscription sync").
//
// Walks active, auto-renewing SubscriptionReceipts rows
// (usp_SubscriptionReceipt_GetForReconciliation) and re-verifies each against
// the issuing store, applying whatever status change (renewal, cancellation,
// refund, expiry) a missed or late webhook wouldn't have caught. A safety net
// alongside SubscriptionWebhooksController, not the primary path - idempotent
// by construction since activation is keyed on (Store, TransactionId).
//
// Intended to be scheduled every few hours (deploy.sh installs a cron entry).
// Can be run by hand for testing or a backfill.
//
// Usage:
//   ConnectionStrings__SilenDb="..." \
//   AppStoreServer__KeyId="..." AppStoreServer__IssuerId="..." AppStoreServer__BundleId="..." AppStoreServer__PrivateKeyPath="/secrets/appstore.p8" \
//   GooglePlay__PackageName="..." GooglePlay__ServiceAccountJsonPath="/secrets/play.json" \
//     dotnet run --project backend/src/Silen.Tools.SubscriptionSync
//
// Flags (all optional):
//   --dry-run         log which receipts would be re-checked, re-verify nothing
//   --user=<guid>     only process receipts for one user (handy for testing)
//   --limit=<n>       batch size passed to the reconciliation query (default 200)
//
// Exit codes: 0 = all processed, 1 = the run failed outright, 2 = completed with failures.

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Silen.Common.Options;
using Silen.Data;
using Silen.Data.Abstractions;
using Silen.Services;
using Silen.Services.Abstractions;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.Configure<AppStoreServerOptions>(builder.Configuration.GetSection(AppStoreServerOptions.SectionName));
builder.Services.Configure<GooglePlayOptions>(builder.Configuration.GetSection(GooglePlayOptions.SectionName));

builder.Services.AddSilenData();
builder.Services.AddSilenServices();

var dryRun = HasFlag(args, "dry-run");
var onlyUser = ParseGuid(ArgValue(args, "user"));
var limit = ParseInt(ArgValue(args, "limit")) ?? 200;

using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) =>
{
    eventArgs.Cancel = true;
    cancellation.Cancel();
};

using var host = builder.Build();
using var scope = host.Services.CreateScope();
var plansProvider = scope.ServiceProvider.GetRequiredService<IPlansProvider>();
var subscriptionReceiptService = scope.ServiceProvider.GetRequiredService<ISubscriptionReceiptService>();

Console.WriteLine(
    $"Subscription sync starting (dryRun={dryRun}, user={onlyUser?.ToString() ?? "all"}, limit={limit}).");

try
{
    var receipts = await plansProvider.GetReceiptsForReconciliationAsync(limit, cancellation.Token);
    if (onlyUser is not null)
    {
        receipts = receipts.Where(r => r.UserId == onlyUser).ToList();
    }

    Console.WriteLine($"Found {receipts.Count} active, auto-renewing receipt(s) due for a re-check.");

    var processed = 0;
    var failed = 0;

    foreach (var receipt in receipts)
    {
        if (cancellation.IsCancellationRequested)
        {
            break;
        }

        if (dryRun)
        {
            Console.WriteLine($"  WOULD CHECK {receipt.Store}/{receipt.TransactionId} (user {receipt.UserId}).");
            continue;
        }

        try
        {
            await subscriptionReceiptService.ApplyStoreNotificationAsync(receipt.Store, receipt.TransactionId, cancellation.Token);
            processed++;
            Console.WriteLine($"  OK {receipt.Store}/{receipt.TransactionId} (user {receipt.UserId}).");
        }
        catch (Exception ex)
        {
            failed++;
            Console.Error.WriteLine($"  FAILED {receipt.Store}/{receipt.TransactionId} (user {receipt.UserId}): {ex.Message}");
        }
    }

    Console.WriteLine($"Considered {receipts.Count}: processed {processed}, failed {failed}.");

    return failed > 0 ? 2 : 0;
}
catch (Exception ex)
{
    Console.Error.WriteLine($"Subscription sync failed: {ex.Message}");
    return 1;
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

static Guid? ParseGuid(string? value) => Guid.TryParse(value, out var parsed) ? parsed : null;
