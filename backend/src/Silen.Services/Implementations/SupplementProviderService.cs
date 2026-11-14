using Silen.Common.Authorization;
using Silen.Common.Contracts;
using Silen.Common.Dtos;
using Silen.Common.Exceptions;
using Silen.Common.Helpers;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Abstractions;
using Silen.Services.Helpers;

namespace Silen.Services.Implementations;

public sealed class SupplementProviderService(
    IAdminProvider adminProvider,
    IAdminRbacProvider adminRbacProvider,
    ISupplementProvidersProvider providersProvider,
    IImageUploadService imageUploadService) : ISupplementProviderService
{
    public Task<ServiceResult<List<SupplementProviderModel>>> GetActiveAsync(CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(() => providersProvider.GetActiveAsync(cancellationToken));

    public Task<ServiceResult<List<AdminSupplementProviderModel>>> GetAllAsync(string? sessionToken, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await AdminPermissionGuard.RequireAsync(adminProvider, adminRbacProvider, sessionToken, AdminPermissions.ProvidersRead, null, cancellationToken);
            return await providersProvider.GetAllAsync(cancellationToken);
        });

    public Task<ServiceResult<AdminWriteResultDto>> SaveAsync(
        string? sessionToken, AdminSupplementProviderUpsertRequest request, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await AdminPermissionGuard.RequireAsync(
                adminProvider, adminRbacProvider, sessionToken, AdminPermissions.ProvidersWrite, clientIp, cancellationToken);

            request.Name = request.Name?.Trim() ?? string.Empty;
            if (request.Name.Length is 0 or > 120)
            {
                throw new ValidationException("Provider save with a blank or long name.", "Give the provider a name (up to 120 characters).");
            }

            ThrowIfTooLong(request.Tagline, 200, "Tagline");
            ThrowIfTooLong(request.PromoCode, 60, "Discount code");
            ThrowIfTooLong(request.DiscountLabel, 60, "Discount label");
            request.ShopUrl = RequireHttpsUrl(request.ShopUrl, "Shop link");
            request.SearchUrl = RequireSearchUrl(request.SearchUrl);
            request.BarcodeCatalogUrl = RequirePlaceholderUrl(request.BarcodeCatalogUrl, BarcodePlaceholder, "Barcode catalog link");
            if (request.BarcodeCatalogEnabled && request.BarcodeCatalogUrl is null)
            {
                throw new ValidationException(
                    "Barcode catalog switched on without a link.",
                    $"Add the barcode catalog link (with {BarcodePlaceholder}) before switching it on.");
            }

            request.BarcodeCatalogApiKey = string.IsNullOrWhiteSpace(request.BarcodeCatalogApiKey) ? null : request.BarcodeCatalogApiKey.Trim();
            ThrowIfTooLong(request.BarcodeCatalogApiKey, 500, "Barcode catalog API key");
            request.LogoUrl = string.IsNullOrWhiteSpace(request.LogoUrl) ? null : request.LogoUrl.Trim();
            ThrowIfTooLong(request.LogoUrl, 500, "Logo");

            var mutation = await providersProvider.UpsertAsync(request, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, $"Provider '{request.Name}' saved.");
        });

    public Task<ServiceResult<AdminWriteResultDto>> DeleteAsync(
        string? sessionToken, Guid providerId, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            var actor = await AdminPermissionGuard.RequireAsync(
                adminProvider, adminRbacProvider, sessionToken, AdminPermissions.ProvidersWrite, clientIp, cancellationToken);

            var mutation = await providersProvider.DeleteAsync(providerId, actor, cancellationToken);
            return AdminMutationOutcomeMapper.Resolve(mutation, "Provider deleted.");
        });

    public Task<ServiceResult<AdminImageUploadResultDto>> UploadLogoAsync(
        string? sessionToken, ImageUploadRequest upload, string? clientIp, CancellationToken cancellationToken = default) =>
        ServiceExecutor.RunAsync(async () =>
        {
            await AdminPermissionGuard.RequireAsync(
                adminProvider, adminRbacProvider, sessionToken, AdminPermissions.ProvidersWrite, clientIp, cancellationToken);

            return new AdminImageUploadResultDto { Url = await imageUploadService.SaveAsync(upload, cancellationToken) };
        });

    /// <summary>The app opens this link in the browser, so only a real https address is accepted.</summary>
    public static string? RequireHttpsUrl(string? value, string field)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var trimmed = value.Trim();
        if (trimmed.Length > 500 || !Uri.TryCreate(trimmed, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)
        {
            throw new ValidationException($"Provider {field} '{trimmed}' is not an https URL.", $"{field} must be an https:// address.");
        }
        return uri.ToString();
    }

    /// <summary>The search link is filled per ingredient, so it has to say where the text goes.
    /// Checked as an https URL with the placeholder swapped for a sample word.</summary>
    public static string? RequireSearchUrl(string? value) =>
        RequirePlaceholderUrl(value, SearchQueryPlaceholder, "Search link");

    /// <summary>An https link with <paramref name="placeholder"/> where the per-use text goes;
    /// blank gives null.</summary>
    public static string? RequirePlaceholderUrl(string? value, string placeholder, string field)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var trimmed = value.Trim();
        if (!trimmed.Contains(placeholder, StringComparison.Ordinal))
        {
            throw new ValidationException(
                $"Provider {field} '{trimmed}' has no {placeholder}.",
                $"{field} must contain {placeholder} where the {(placeholder == BarcodePlaceholder ? "barcode" : "search text")} goes.");
        }

        RequireHttpsUrl(trimmed.Replace(placeholder, "1", StringComparison.Ordinal), field);
        return trimmed;
    }

    public const string SearchQueryPlaceholder = "{query}";

    public const string BarcodePlaceholder = "{barcode}";

    private static void ThrowIfTooLong(string? value, int max, string field)
    {
        if (value is not null && value.Trim().Length > max)
        {
            throw new ValidationException($"Provider {field} longer than {max}.", $"{field} can be at most {max} characters.");
        }
    }
}
