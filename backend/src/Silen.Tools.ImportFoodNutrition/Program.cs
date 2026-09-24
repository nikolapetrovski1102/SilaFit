using System.Net.Http.Headers;

// Downloads and merges four official/open nutrition catalogs into the single
// dbo.FoodNutrition table. Archives are cached outside source control and a
// rerun updates existing source rows instead of duplicating them.
//
// Usage:
//   SILEN_CONNECTION_STRING="..." dotnet run \
//     --project backend/src/Silen.Tools.ImportFoodNutrition -- \
//     --sources=usda,cnf,cofid,off
//
// Optional:
//   --cache-dir=/path/to/cache   (default: data/import/food-nutrition)
//   --sources=usda,cnf,cofid,off (default: all)
//   --usda-types=foundation,survey,legacy,branded (default: all)

var connectionString = Environment.GetEnvironmentVariable("SILEN_CONNECTION_STRING");
if (string.IsNullOrWhiteSpace(connectionString))
    throw new InvalidOperationException("SILEN_CONNECTION_STRING is not set.");

var sources = (GetArg(args, "--sources") ?? "usda,cnf,cofid,off")
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
    .Select(value => value.ToLowerInvariant()).ToHashSet();
var supported = new HashSet<string> { "usda", "cnf", "cofid", "off" };
var unknown = sources.Except(supported).ToArray();
if (unknown.Length > 0) throw new InvalidOperationException($"Unknown source(s): {string.Join(", ", unknown)}. Use usda, cnf, cofid, or off.");
var usdaTypes = (GetArg(args, "--usda-types") ?? "foundation,survey,legacy,branded")
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
    .Select(value => value.ToLowerInvariant()).ToHashSet();
var unknownUsdaTypes = usdaTypes.Except(new[] { "foundation", "survey", "legacy", "branded" }).ToArray();
if (unknownUsdaTypes.Length > 0) throw new InvalidOperationException($"Unknown USDA type(s): {string.Join(", ", unknownUsdaTypes)}.");

var cacheDirectory = Path.GetFullPath(GetArg(args, "--cache-dir") ?? Path.Combine("data", "import", "food-nutrition"));
using var http = new HttpClient { Timeout = Timeout.InfiniteTimeSpan };
http.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("SilaFit-FoodImporter", "1.0"));
http.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("(+https://sila.fitness)"));

using var cancellation = new CancellationTokenSource();
Console.CancelKeyPress += (_, eventArgs) => { eventArgs.Cancel = true; cancellation.Cancel(); };

await using var writer = new SqlFoodWriter(connectionString);
await writer.OpenAsync(cancellation.Token);
var importers = new SourceImporters(http, cacheDirectory, writer, usdaTypes);

if (sources.Contains("usda")) await importers.ImportUsdaAsync(cancellation.Token);
if (sources.Contains("cnf")) await importers.ImportCnfAsync(cancellation.Token);
if (sources.Contains("cofid")) await importers.ImportCofidAsync(cancellation.Token);
if (sources.Contains("off")) await importers.ImportOpenFoodFactsAsync(cancellation.Token);

await writer.FlushAsync(cancellation.Token);
Console.WriteLine($"Done. Processed {writer.Accepted:N0} source rows into dbo.FoodNutrition.");
Console.WriteLine("Attribution: USDA FoodData Central (CC0), Health Canada CNF (OGL-Canada), UK CoFID (OGL v3), Open Food Facts (ODbL). Personal use is permitted; preserve attribution if redistributed.");

static string? GetArg(string[] args, string name)
{
    var prefix = name + "=";
    return args.FirstOrDefault(value => value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))?[prefix.Length..];
}
