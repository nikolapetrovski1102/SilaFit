using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;

namespace Silen.Services.Implementations;

/// <inheritdoc cref="IFoodService"/>
public sealed partial class FoodService(IFoodNutritionProvider foodNutritionProvider) : IFoodService
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
            return await foodNutritionProvider.SearchAsync(userId, normalized, resolvedTake, cancellationToken);
        });

    public Task<ServiceResult<FoodNutritionModel>> CreateCustomAsync(
        Guid userId, CreateCustomFoodRequest request, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            request.Name = request.Name?.Trim() ?? string.Empty;
            request.BrandName = string.IsNullOrWhiteSpace(request.BrandName) ? null : request.BrandName.Trim();

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
