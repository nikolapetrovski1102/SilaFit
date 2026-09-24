using System.Data;
using System.Globalization;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ExcelDataReader;

internal sealed class SourceImporters(HttpClient http, string cacheDirectory, SqlFoodWriter writer, IReadOnlySet<string> usdaTypes)
{
    public const string UsdaPage = "https://fdc.nal.usda.gov/download-datasets/";
    public const string CnfUrl = "https://open.canada.ca/data/dataset/1b6139bd-ed7e-4043-bc28-ff00e10f3109/resource/019f2a90-e3a9-489d-b6e1-f74f4ba1d006/download/cnf_fcen_all-files-data_2026.zip";
    public const string CofidUrl = "https://assets.publishing.service.gov.uk/media/60538b91e90e07527df82ae4/McCance_Widdowsons_Composition_of_Foods_Integrated_Dataset_2021..xlsx";
    public const string OffUrl = "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz";

    private static readonly CultureInfo Invariant = CultureInfo.InvariantCulture;

    public async Task ImportUsdaAsync(CancellationToken cancellationToken)
    {
        Console.WriteLine("Discovering current USDA FoodData Central JSON releases...");
        var html = await http.GetStringAsync(UsdaPage, cancellationToken);
        var links = Regex.Matches(html, @"href=[""'](?<url>[^""']+\.zip)[""']", RegexOptions.IgnoreCase)
            .Select(m => new Uri(new Uri(UsdaPage), m.Groups["url"].Value).AbsoluteUri)
            .Where(url => url.Contains("_json_", StringComparison.OrdinalIgnoreCase))
            .Where(url => url.Contains("foundation", StringComparison.OrdinalIgnoreCase)
                       || url.Contains("branded", StringComparison.OrdinalIgnoreCase)
                       || url.Contains("survey", StringComparison.OrdinalIgnoreCase)
                       || url.Contains("sr_legacy", StringComparison.OrdinalIgnoreCase))
            .Where(url => usdaTypes.Contains(UsdaFamily(url).ToLowerInvariant()))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        // The download page also contains historical releases. Keep the first
        // link for each dataset family; latest releases are listed first.
        links = links.GroupBy(UsdaFamily, StringComparer.OrdinalIgnoreCase).Select(group => group.First()).ToList();
        if (links.Count == 0)
            throw new InvalidOperationException("No USDA JSON downloads were found on the official download page.");

        foreach (var url in links.OrderBy(UsdaPriority))
        {
            var path = await DownloadAsync(url, cancellationToken);
            Console.WriteLine($"Importing USDA {UsdaFamily(url)}...");
            using var archive = ZipFile.OpenRead(path);
            var entry = archive.Entries.FirstOrDefault(item => item.Name.EndsWith(".json", StringComparison.OrdinalIgnoreCase))
                ?? throw new InvalidDataException($"No JSON file found in {path}.");
            await using var entryStream = entry.Open();
            await using var stream = new RootJsonArrayStream(entryStream);

            await foreach (var food in JsonSerializer.DeserializeAsyncEnumerable<JsonElement>(stream, cancellationToken: cancellationToken))
            {
                if (food.ValueKind != JsonValueKind.Object) continue;
                var row = ParseUsda(food, url);
                if (row is not null) await writer.AddAsync(row, cancellationToken);
            }
            await writer.FlushAsync(cancellationToken);
        }
    }

    public async Task ImportOpenFoodFactsAsync(CancellationToken cancellationToken)
    {
        var path = await DownloadAsync(OffUrl, cancellationToken);
        Console.WriteLine("Importing Open Food Facts (this is the largest source)...");
        await using var file = File.OpenRead(path);
        await using var gzip = new GZipStream(file, CompressionMode.Decompress);
        using var text = new StreamReader(gzip, Encoding.UTF8, true, 1 << 20);
        using var csv = new DelimitedTextReader(text, '\t');
        using var rows = csv.ReadRows().GetEnumerator();
        if (!rows.MoveNext()) return;
        var header = Header(rows.Current);

        while (rows.MoveNext())
        {
            cancellationToken.ThrowIfCancellationRequested();
            var values = rows.Current;
            var code = Get(values, header, "code");
            var name = First(Get(values, header, "product_name"), Get(values, header, "product_name_en"));
            if (string.IsNullOrWhiteSpace(code) || string.IsNullOrWhiteSpace(name)) continue;

            var row = new FoodNutritionRow(
                name, Get(values, header, "brands"), code, "Branded", "Open Food Facts", code,
                $"https://world.openfoodfacts.org/product/{Uri.EscapeDataString(code)}",
                Number(First(Get(values, header, "serving_quantity"), Get(values, header, "serving_size"))),
                Number(Get(values, header, "energy-kcal_100g")),
                Number(Get(values, header, "proteins_100g")),
                Number(Get(values, header, "carbohydrates_100g")),
                Number(Get(values, header, "fat_100g")),
                Number(Get(values, header, "fiber_100g")),
                Number(Get(values, header, "sugars_100g")),
                Multiply(Number(Get(values, header, "sodium_100g")), 1000m),
                true);
            await writer.AddAsync(row, cancellationToken);
        }
        await writer.FlushAsync(cancellationToken);
    }

    public async Task ImportCnfAsync(CancellationToken cancellationToken)
    {
        var path = await DownloadAsync(CnfUrl, cancellationToken);
        Console.WriteLine("Importing Canadian Nutrient File...");
        using var archive = ZipFile.OpenRead(path);
        var foodEntry = FindEntry(archive, "food_name.csv");
        var nutrientNameEntry = FindEntry(archive, "nutrient_name.csv");
        var amountEntry = FindEntry(archive, "nutrient_amount.csv");
        var measureEntry = archive.Entries.FirstOrDefault(entry => entry.Name.Equals("measure_weight_conversion.csv", StringComparison.OrdinalIgnoreCase));

        var foods = ReadCsv(foodEntry).Skip(1)
            .Where(row => row.Length >= 3 && IsEnglish(row))
            .GroupBy(row => row[0]).ToDictionary(group => group.Key, group => group.First().FirstOrDefault(value => !string.IsNullOrWhiteSpace(value) && value != group.Key) ?? group.Key);

        var nutrients = ReadCsv(nutrientNameEntry).Skip(1)
            .Where(row => row.Length >= 2 && IsEnglish(row))
            .GroupBy(row => row[0]).ToDictionary(group => group.Key, group => string.Join(' ', group.First()).ToLowerInvariant());

        var values = new Dictionary<string, Dictionary<string, decimal>>(StringComparer.Ordinal);
        foreach (var row in ReadCsv(amountEntry).Skip(1))
        {
            if (row.Length < 3 || !decimal.TryParse(row[2], NumberStyles.Float, Invariant, out var amount)) continue;
            if (!values.TryGetValue(row[0], out var foodValues)) values[row[0]] = foodValues = new(StringComparer.Ordinal);
            foodValues[row[1]] = amount;
        }

        var servings = new Dictionary<string, decimal>();
        if (measureEntry is not null)
        {
            foreach (var row in ReadCsv(measureEntry).Skip(1))
            {
                if (row.Length >= 3 && decimal.TryParse(row[^1], NumberStyles.Float, Invariant, out var grams) && !servings.ContainsKey(row[0]))
                    servings[row[0]] = grams;
            }
        }

        foreach (var (id, name) in foods)
        {
            values.TryGetValue(id, out var foodValues);
            decimal? Find(params string[] terms) => foodValues is null ? null : foodValues
                .Where(pair => nutrients.TryGetValue(pair.Key, out var nutrient) && terms.All(nutrient.Contains))
                .Select(pair => (decimal?)pair.Value).FirstOrDefault();

            await writer.AddAsync(new FoodNutritionRow(
                name, null, null, "Generic", "CNF", id, CnfUrl,
                servings.GetValueOrDefault(id) is var serving && serving > 0 ? serving : null,
                Find("energy", "kcal"), Find("protein"), Find("carbohydrate"), Find("fat", "total"),
                Find("fibre", "total"), Find("sugars", "total"), Find("sodium"), false), cancellationToken);
        }
        await writer.FlushAsync(cancellationToken);
    }

    public async Task ImportCofidAsync(CancellationToken cancellationToken)
    {
        var path = await DownloadAsync(CofidUrl, cancellationToken);
        Console.WriteLine("Importing UK CoFID...");
        Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
        await using var stream = File.OpenRead(path);
        using var excel = ExcelReaderFactory.CreateReader(stream);
        var data = excel.AsDataSet(new ExcelDataSetConfiguration
        {
            ConfigureDataTable = _ => new ExcelDataTableConfiguration { UseHeaderRow = false }
        });

        foreach (DataTable sheet in data.Tables)
        {
            var headerRowIndex = FindHeaderRow(sheet, "Food Name");
            if (headerRowIndex < 0) continue;
            var header = Header(sheet.Rows[headerRowIndex].ItemArray.Select(Cell).ToArray());
            for (var i = headerRowIndex + 1; i < sheet.Rows.Count; i++)
            {
                var values = sheet.Rows[i].ItemArray.Select(Cell).ToArray();
                var name = GetFuzzy(values, header, "food name");
                var code = GetFuzzy(values, header, "food code");
                if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(code)) continue;

                await writer.AddAsync(new FoodNutritionRow(
                    name, null, null, "Generic", "CoFID", code, CofidUrl, null,
                    Number(GetFuzzy(values, header, "energy", "kcal")),
                    Number(GetFuzzy(values, header, "protein", "g")),
                    Number(GetFuzzy(values, header, "carbohydrate", "g")),
                    Number(GetFuzzy(values, header, "fat", "g")),
                    Number(First(GetFuzzy(values, header, "aoac", "fibre"), GetFuzzy(values, header, "fibre", "g"))),
                    Number(GetFuzzy(values, header, "total sugars")),
                    Number(GetFuzzy(values, header, "sodium", "mg")), false), cancellationToken);
            }
        }
        await writer.FlushAsync(cancellationToken);
    }

    private FoodNutritionRow? ParseUsda(JsonElement food, string sourceUrl)
    {
        var id = Property(food, "fdcId");
        var name = Property(food, "description");
        if (id is null || name is null) return null;
        var dataType = Property(food, "dataType") ?? UsdaFamily(sourceUrl);
        var nutrients = new Dictionary<int, decimal>();
        if (food.TryGetProperty("foodNutrients", out var items))
        {
            foreach (var item in items.EnumerateArray())
            {
                if (!item.TryGetProperty("amount", out var amountElement) || !amountElement.TryGetDecimal(out var amount)) continue;
                var nutrientId = item.TryGetProperty("nutrient", out var nutrient) && nutrient.TryGetProperty("id", out var nestedId)
                    ? nestedId.GetInt32()
                    : item.TryGetProperty("nutrientId", out var flatId) ? flatId.GetInt32() : 0;
                if (nutrientId > 0) nutrients[nutrientId] = amount;
            }
        }

        decimal? N(params int[] ids) => ids.Select(value => nutrients.TryGetValue(value, out var amount) ? (decimal?)amount : null).FirstOrDefault(value => value is not null);
        decimal? serving = DecimalProperty(food, "servingSize");
        if (serving is null && food.TryGetProperty("foodPortions", out var portions))
            serving = portions.EnumerateArray().Select(portion => DecimalProperty(portion, "gramWeight")).FirstOrDefault(value => value is > 0);
        var branded = dataType.Contains("Branded", StringComparison.OrdinalIgnoreCase);
        var sourceName = branded ? "USDA Branded" : dataType.Contains("Foundation", StringComparison.OrdinalIgnoreCase)
            ? "USDA Foundation" : dataType.Contains("Survey", StringComparison.OrdinalIgnoreCase)
            ? "USDA Survey" : "USDA Legacy";

        return new FoodNutritionRow(name, Property(food, "brandOwner") ?? Property(food, "brandName"),
            Property(food, "gtinUpc"), dataType, sourceName, id, sourceUrl, serving,
            N(1008, 2047, 2048), N(1003), N(1005), N(1004), N(1079), N(2000, 1063), N(1093), branded);
    }

    private async Task<string> DownloadAsync(string url, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(cacheDirectory);
        var fileName = Uri.UnescapeDataString(new Uri(url).Segments.Last()).Replace("..", ".");
        var path = Path.Combine(cacheDirectory, fileName);
        if (File.Exists(path) && new FileInfo(path).Length > 0)
        {
            Console.WriteLine($"Using cached {fileName}");
            return path;
        }

        var partial = path + ".partial";
        Console.WriteLine($"Downloading {url}");
        using var response = await http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using (var input = await response.Content.ReadAsStreamAsync(cancellationToken))
        await using (var output = File.Create(partial))
            await input.CopyToAsync(output, cancellationToken);
        File.Move(partial, path, true);
        return path;
    }

    private static IEnumerable<string[]> ReadCsv(ZipArchiveEntry entry)
    {
        using var stream = entry.Open();
        using var text = new StreamReader(stream, Encoding.UTF8, true);
        using var csv = new DelimitedTextReader(text, ',');
        foreach (var row in csv.ReadRows()) yield return row;
    }

    private static ZipArchiveEntry FindEntry(ZipArchive archive, string name) => archive.Entries.FirstOrDefault(entry => entry.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
        ?? throw new InvalidDataException($"{name} was not found in the CNF archive.");
    private static Dictionary<string, int> Header(string[] values) => values.Select((value, index) => (value: value.Trim().TrimStart('\uFEFF').ToLowerInvariant(), index)).GroupBy(pair => pair.value).ToDictionary(group => group.Key, group => group.First().index);
    private static string? Get(string[] row, IReadOnlyDictionary<string, int> header, string name) => header.TryGetValue(name.ToLowerInvariant(), out var index) && index < row.Length ? Null(row[index]) : null;
    private static string? GetFuzzy(string[] row, IReadOnlyDictionary<string, int> header, params string[] terms) { var match = header.FirstOrDefault(pair => terms.All(term => pair.Key.Contains(term, StringComparison.OrdinalIgnoreCase))); return match.Key is null || match.Value >= row.Length ? null : Null(row[match.Value]); }
    private static string? First(params string?[] values) => values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
    private static string? Null(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    private static decimal? Number(string? value) { if (string.IsNullOrWhiteSpace(value)) return null; var match = Regex.Match(value, @"[-+]?\d+(?:[.,]\d+)?"); return match.Success && decimal.TryParse(match.Value.Replace(',', '.'), NumberStyles.Float, Invariant, out var number) ? number : null; }
    private static decimal? Multiply(decimal? value, decimal factor) => value is null ? null : value * factor;
    private static string? Property(JsonElement element, string name) => element.TryGetProperty(name, out var property) ? property.ValueKind == JsonValueKind.String ? Null(property.GetString()) : property.ToString() : null;
    private static decimal? DecimalProperty(JsonElement element, string name) => element.TryGetProperty(name, out var property) && property.TryGetDecimal(out var value) ? value : null;
    private static string UsdaFamily(string url) => url.Contains("foundation", StringComparison.OrdinalIgnoreCase) ? "Foundation" : url.Contains("branded", StringComparison.OrdinalIgnoreCase) ? "Branded" : url.Contains("survey", StringComparison.OrdinalIgnoreCase) ? "Survey" : "Legacy";
    private static int UsdaPriority(string url) => UsdaFamily(url) switch { "Foundation" => 0, "Survey" => 1, "Legacy" => 2, _ => 3 };
    private static bool IsEnglish(string[] row) => !row.Any(value => value.Equals("F", StringComparison.OrdinalIgnoreCase) || value.Equals("French", StringComparison.OrdinalIgnoreCase));
    private static string Cell(object? value) => value is null or DBNull ? string.Empty : Convert.ToString(value, Invariant) ?? string.Empty;
    private static int FindHeaderRow(DataTable table, string text) { for (var i = 0; i < Math.Min(table.Rows.Count, 30); i++) if (table.Rows[i].ItemArray.Any(value => Cell(value).Contains(text, StringComparison.OrdinalIgnoreCase))) return i; return -1; }
}
