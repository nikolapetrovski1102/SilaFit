using System.Security.Cryptography;
using System.Text.Json;
using System.Text;
using System.Text.RegularExpressions;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IFoodService"/>
public sealed partial class FoodService(
    IFoodNutritionProvider foodNutritionProvider,
    IOpenFoodFactsClient openFoodFactsClient,
    ISubscriptionGate subscriptionGate,
    IFoodScanProvider foodScanProvider,
    IPartnerFoodCatalogClient partnerFoodCatalog,
    BarcodeOffTickets offTickets) : IFoodService
{
    private const int MinQueryLength = 2;
    private const int DefaultTake = 25;
    private const int MaxTake = 50;
    private const int MaxNameLength = 200;
    private const int MaxBrandLength = 120;

    // Per-100 g ceilings: pure fat is ~900 kcal, and no macro can outweigh the 100 g it's measured in.
    private const decimal MaxKcalPer100G = 900;
    private const decimal MaxGramsPer100G = 100;
    private const decimal MaxSodiumMgPer100G = 40000;
    private const decimal MaxServingSizeG = 5000;

    public Task<ServiceResult<List<FoodNutritionModel>>> SearchAsync(
        Guid userId, string? query, int? take, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var normalized = Normalize(query);
            if (normalized.Length < MinQueryLength)
            {
                return new List<FoodNutritionModel>();
            }

            var resolvedTake = Math.Clamp(take ?? DefaultTake, 1, MaxTake);
            var direct = await foodNutritionProvider.SearchAsync(userId, normalized, resolvedTake, cancellationToken);

            // The catalog is English. A Macedonian query ("пилешки гради") also searches
            // its English form. Direct matches stay first: those are the user's own
            // foods they named in Macedonian.
            var english = MacedonianFoodAliases.ToEnglishQuery(normalized);
            if (english is null || direct.Count >= resolvedTake)
            {
                return direct;
            }

            var translated = await foodNutritionProvider.SearchAsync(userId, english, resolvedTake, cancellationToken);
            return direct
                .Concat(translated)
                .DistinctBy(food => food.FoodNutritionId)
                .Take(resolvedTake)
                .ToList();
        });

    public Task<ServiceResult<FoodNutritionModel>> CreateCustomAsync(
        Guid userId, CreateCustomFoodRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            request.Name = request.Name?.Trim() ?? string.Empty;
            request.BrandName = string.IsNullOrWhiteSpace(request.BrandName) ? null : request.BrandName.Trim();
            if (string.IsNullOrWhiteSpace(request.Barcode))
            {
                request.Barcode = null;
            }
            else
            {
                request.Barcode = NormalizeBarcode(request.Barcode)
                    ?? throw new ValidationException("Custom food barcode was not 8-14 digits.", "That barcode doesn't look right.");
            }

            var normalizedName = Normalize(request.Name);
            if (normalizedName.Length == 0)
            {
                throw new ValidationException("Custom food name was blank.", "Give the food a name.");
            }

            if (request.Name.Length > MaxNameLength || request.BrandName?.Length > MaxBrandLength)
            {
                throw new ValidationException("Custom food name was too long.", "That name is too long.");
            }

            ValidateNutrients(request);

            // A fresh id per food: user foods are never deduplicated against the
            // catalog or each other, so the hash only has to be unique.
            var sourceFoodId = $"user:{userId:N}:{Guid.NewGuid():N}";
            var contentHash = SHA256.HashData(Encoding.UTF8.GetBytes(sourceFoodId));

            return await foodNutritionProvider.CreateCustomAsync(
                userId, request, normalizedName, sourceFoodId, contentHash, cancellationToken);
        });

    public Task<ServiceResult<BarcodeLookupResultDto>> LookupBarcodeAsync(
        Guid userId, string? barcode, bool openFoodFactsOnDevice = false, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var code = NormalizeBarcode(barcode)
                ?? throw new ValidationException($"Barcode '{barcode}' was not 8-14 digits.", "That barcode doesn't look right. Try scanning it again.");

            // Barcode scanning is Pro. A Free account gets a few lookups (the app never says how
            // many); the one after that is refused and the app opens the plans.
            long? trialScanId = null;
            if (!await subscriptionGate.HasActiveProAsync(userId, cancellationToken))
            {
                var reservation = await foodScanProvider.TryReserveAsync(
                    userId, BarcodeScanKind, isTrial: true, DateTime.UtcNow, dailyLimit: 0,
                    IFoodScanService.BarcodeTrialLimit, cancellationToken);
                if (!reservation.Allowed || reservation.FoodScanId is null)
                {
                    throw new ProUpgradeRequiredException(
                        $"User {userId} used all {IFoodScanService.BarcodeTrialLimit} free barcode scans.",
                        "Upgrade to Pro to scan barcodes.");
                }

                trialScanId = reservation.FoodScanId;
            }

            try
            {
                return await LookupBarcodeCoreAsync(userId, code, openFoodFactsOnDevice, cancellationToken);
            }
            catch when (trialScanId is { } scanId)
            {
                // The lookup itself failed (Open Food Facts down, a database error) - not the
                // user's fault, so the trial scan isn't spent. CancellationToken.None: the request
                // may be the thing that was cancelled.
                await foodScanProvider.ReleaseAsync(userId, scanId, CancellationToken.None);
                throw;
            }
        });

    private const string BarcodeScanKind = "barcode";

    public Task<ServiceResult<BarcodeLookupResultDto>> SaveDeviceOpenFoodFactsProductAsync(
        Guid userId, string? barcode, JsonElement openFoodFactsResponse, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var code = NormalizeBarcode(barcode)
                ?? throw new ValidationException($"Barcode '{barcode}' was not 8-14 digits.", "That barcode doesn't look right. Try scanning it again.");

            // Only a product this user just scanned and missed: the ticket is the proof the
            // lookup passed the Pro / trial gate, and it can be spent once.
            if (!offTickets.TryConsume(userId, code))
            {
                throw new ValidationException(
                    $"User {userId} posted an Open Food Facts product for {code} without a live lookup ticket.",
                    "Scan the barcode again.");
            }

            // Someone else's scan may have saved it while this phone was asking OFF.
            foreach (var candidate in BarcodeCandidates(code))
            {
                if (await foodNutritionProvider.GetByBarcodeAsync(userId, candidate, cancellationToken) is { } local)
                {
                    return new BarcodeLookupResultDto { Barcode = code, Food = local };
                }
            }

            // Parsed by the same code the server's own OFF lookup uses, and held to the same
            // plausibility rules, so a tampered payload can't save nonsense nutrition.
            var product = OpenFoodFactsClient.Parse(code, openFoodFactsResponse);
            return product is null ? new BarcodeLookupResultDto { Barcode = code } : await SaveOrHintAsync(code, product, IFoodNutritionProvider.OpenFoodFactsSourceName, cancellationToken);
        });

    private async Task<BarcodeLookupResultDto> LookupBarcodeCoreAsync(
        Guid userId, string code, bool openFoodFactsOnDevice, CancellationToken cancellationToken)
    {
        foreach (var candidate in BarcodeCandidates(code))
        {
            var local = await foodNutritionProvider.GetByBarcodeAsync(userId, candidate, cancellationToken);
            if (local is not null)
            {
                return new BarcodeLookupResultDto { Barcode = code, Food = local };
            }
        }

        // The grocery partner first, when it's switched on: it stocks what's on Macedonian
        // shelves. A product it knows but can't give full nutrition for still falls through
        // to OFF, which may have the label.
        var partner = await partnerFoodCatalog.GetProductAsync(code, cancellationToken);
        if (partner is not null && await TrySaveAsync(partner.Product, partner.SourceName, cancellationToken) is { } partnerFood)
        {
            return new BarcodeLookupResultDto { Barcode = code, Food = partnerFood };
        }

        if (openFoodFactsOnDevice)
        {
            // Current apps ask OFF from the phone - each device on its own IP and its own
            // budget - instead of every scan queueing behind this server's one OFF quota.
            // A partner product too thin to save still prefills the form if OFF has nothing;
            // otherwise what another user called it (local products OFF never had).
            offTickets.Issue(userId, code);
            return new BarcodeLookupResultDto
            {
                Barcode = code,
                CheckOpenFoodFacts = true,
                Hint = partner is null
                    ? await foodNutritionProvider.GetBarcodeSuggestionAsync(userId, code, cancellationToken)
                    : HintFor(partner.Product)
            };
        }

        // Older app versions: the server asks OFF itself.
        var product = await openFoodFactsClient.GetProductAsync(code, cancellationToken) ?? partner?.Product;
        if (product is null)
        {
            return new BarcodeLookupResultDto
            {
                Barcode = code,
                Hint = await foodNutritionProvider.GetBarcodeSuggestionAsync(userId, code, cancellationToken)
            };
        }

        var sourceName = product.IsPartnerProduct && partner is not null
            ? partner.SourceName
            : IFoodNutritionProvider.OpenFoodFactsSourceName;
        return await SaveOrHintAsync(code, product, sourceName, cancellationToken);
    }

    /// <summary>The saved food when the product is complete and plausible; otherwise a hint
    /// that prefills the "add it" form with what is known.</summary>
    private async Task<BarcodeLookupResultDto> SaveOrHintAsync(
        string code, OpenFoodFactsProductModel product, string sourceName, CancellationToken cancellationToken)
    {
        if (await TrySaveAsync(product, sourceName, cancellationToken) is { } saved)
        {
            return new BarcodeLookupResultDto { Barcode = code, Food = saved };
        }

        // OFF knows the product but not enough (or implausible) nutrition: prefill
        // the "add it" form with what it does know.
        return new BarcodeLookupResultDto { Barcode = code, Hint = HintFor(product) };
    }

    private static BarcodeProductHintDto HintFor(OpenFoodFactsProductModel product) => new()
    {
        Name = TrimmedName(product),
        BrandName = product.BrandName?.Length > MaxBrandLength ? product.BrandName[..MaxBrandLength] : product.BrandName,
        ImageUrl = product.ImageUrl,
        ServingSizeG = product.ServingSizeG <= MaxServingSizeG ? product.ServingSizeG : null
    };

    /// <summary>Saves a looked-up product in the shared catalog when it has a name and
    /// plausible nutrition; null (nothing saved) otherwise.</summary>
    private async Task<FoodNutritionModel?> TrySaveAsync(
        OpenFoodFactsProductModel product, string sourceName, CancellationToken cancellationToken)
    {
        var name = TrimmedName(product);
        var normalizedName = Normalize(name);
        if (normalizedName.Length == 0 || !IsPlausible(product))
        {
            return null;
        }

        // OFF rows keep their original hash key; partner rows get their own, so the same
        // barcode from both sources is two rows rather than one overwriting the other.
        var hashKey = product.IsPartnerProduct ? $"partner-live:{sourceName}:{product.Barcode}" : $"off-live:{product.Barcode}";
        return await foodNutritionProvider.SaveOpenFoodFactsAsync(
            product, name!, normalizedName, SHA256.HashData(Encoding.UTF8.GetBytes(hashKey)), sourceName, cancellationToken);
    }

    private static string? TrimmedName(OpenFoodFactsProductModel product)
    {
        var name = product.Name?.Trim();
        return name?.Length > MaxNameLength ? name[..MaxNameLength] : name;
    }

    /// <summary>Digits only, 8-14 long (EAN-8, UPC-A, EAN-13, GTIN-14); spaces and dashes
    /// a user might type are dropped. Null when it can't be a retail barcode.</summary>
    internal static string? NormalizeBarcode(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var digits = new string(value.Where(c => c is not (' ' or '-')).ToArray());
        return digits.Length is >= 8 and <= 14 && digits.All(char.IsAsciiDigit) ? digits : null;
    }

    /// <summary>The scanned code, then its other common spelling: a 12-digit UPC-A is
    /// the same product as the EAN-13 with a leading zero, and sources store either.</summary>
    internal static IEnumerable<string> BarcodeCandidates(string code)
    {
        yield return code;
        if (code.Length == 12)
        {
            yield return "0" + code;
        }
        else if (code.Length == 13 && code[0] == '0')
        {
            yield return code[1..];
        }
    }

    /// <summary>The same per-100 g ceilings custom foods are held to, plus an energy
    /// check against the macros, so a mistyped OFF entry (kJ as kcal) isn't saved.</summary>
    private static bool IsPlausible(OpenFoodFactsProductModel product)
    {
        if (!product.HasHeadlineNutrients)
        {
            return false;
        }

        decimal kcal = product.CaloriesKcal!.Value, protein = product.ProteinG!.Value,
                carbs = product.CarbohydrateG!.Value, fat = product.FatG!.Value;
        decimal?[] all = [kcal, protein, carbs, fat, product.FiberG, product.SugarG, product.SodiumMg];
        if (all.Any(value => value < 0) || kcal > MaxKcalPer100G
            || protein + carbs + fat > MaxGramsPer100G || product.SodiumMg > MaxSodiumMgPer100G)
        {
            return false;
        }

        // All zeros passes: water and zero-sugar drinks are real products people log.
        // Mirrors dbo.foodnutrition_prune's energy rule.
        var atwater = 4 * protein + 4 * carbs + 9 * fat;
        return !(atwater - kcal > 50 && kcal < 0.5m * atwater) && kcal - atwater <= 300;
    }

    private static void ValidateNutrients(CreateCustomFoodRequest request)
    {
        decimal?[] all =
        [
            request.CaloriesKcal, request.ProteinG, request.CarbohydrateG, request.FatG,
            request.FiberG, request.SugarG, request.SodiumMg, request.ServingSizeG
        ];
        if (all.Any(value => value < 0))
        {
            throw new ValidationException("Custom food had a negative nutrient.", "Nutrition values can't be negative.");
        }

        if (request.CaloriesKcal > MaxKcalPer100G)
        {
            throw new ValidationException($"Custom food kcal '{request.CaloriesKcal}' exceeded 900/100 g.", "Calories can't exceed 900 per 100 g.");
        }

        decimal?[] grams = [request.ProteinG, request.CarbohydrateG, request.FatG, request.FiberG, request.SugarG];
        if (grams.Any(value => value > MaxGramsPer100G)
            || request.ProteinG + request.CarbohydrateG + request.FatG > MaxGramsPer100G)
        {
            throw new ValidationException("Custom food macros exceeded 100 g per 100 g.", "Macros can't add up to more than 100 g per 100 g.");
        }

        if (request.SodiumMg > MaxSodiumMgPer100G || request.ServingSizeG is 0 or > MaxServingSizeG)
        {
            throw new ValidationException("Custom food sodium or serving size was out of range.", "Check the sodium and serving size.");
        }

        if (request.CaloriesKcal == 0 && request.ProteinG == 0 && request.CarbohydrateG == 0 && request.FatG == 0)
        {
            throw new ValidationException("Custom food had no nutrition.", "Enter at least calories or one macro.");
        }

        request.CaloriesKcal = Math.Round(request.CaloriesKcal, 1);
        request.ProteinG = Math.Round(request.ProteinG, 1);
        request.CarbohydrateG = Math.Round(request.CarbohydrateG, 1);
        request.FatG = Math.Round(request.FatG, 1);
    }

    /// <summary>The importer's NormalizedName folding: lower-case, every run of
    /// non-letter/non-digit characters becomes one space, trimmed.</summary>
    internal static string Normalize(string? value) =>
        string.IsNullOrWhiteSpace(value)
            ? string.Empty
            : NonAlphanumeric().Replace(value.ToLowerInvariant(), " ").Trim();

    [GeneratedRegex(@"[^\p{L}\p{N}]+")]
    private static partial Regex NonAlphanumeric();
}
