using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Silen.Common.Models;
using Silen.Data.Abstractions;
using Silen.Services.Implementations;
using Xunit;

namespace Silen.Tests.Implementations;

public class PartnerFoodCatalogClientTests
{
    [Fact]
    public void Parse_MapsTheContract()
    {
        using var json = JsonDocument.Parse("""
            { "name": " Ajvar blagi ", "brandName": "Zito", "productUrl": "https://paket.mk/p/1", "imageUrl": "http://x/y.jpg",
              "caloriesKcal": 120, "proteinG": "2.5", "carbohydrateG": 10, "fatG": 8 }
            """);

        var product = PartnerFoodCatalogClient.Parse("5310000000017", json.RootElement)!;

        Assert.Equal("Ajvar blagi", product.Name);
        Assert.Equal(2.5m, product.ProteinG);
        Assert.Equal("https://paket.mk/p/1", product.SourceUrl);
        Assert.Null(product.ImageUrl); // http isn't shown in the app
        Assert.True(product.IsPartnerProduct);
        Assert.True(product.HasHeadlineNutrients);
    }

    [Fact]
    public void Parse_NoName_IsNull()
    {
        using var json = JsonDocument.Parse("""{ "caloriesKcal": 120 }""");
        Assert.Null(PartnerFoodCatalogClient.Parse("5310000000017", json.RootElement));
    }

    [Fact]
    public async Task NoCatalogSwitchedOn_NeverCallsOut()
    {
        var sut = Client(null, new ThrowingHandler());

        Assert.Null(await sut.GetProductAsync("5310000000017"));
    }

    [Theory]
    [InlineData("https://api.paket.mk/products")]          // no placeholder
    [InlineData("http://api.paket.mk/products/{barcode}")] // not https
    public async Task BadCatalogLink_NeverCallsOut(string url)
    {
        var sut = Client(new PartnerBarcodeCatalogModel { Name = "Paket.mk", ProductUrl = url }, new ThrowingHandler());

        Assert.Null(await sut.GetProductAsync("5310000000017"));
    }

    [Fact]
    public async Task SwitchedOn_AsksTheConsoleLinkWithTheKey_AndTagsThePartner()
    {
        HttpRequestMessage? sent = null;
        var handler = new JsonHandler(request => sent = request, """{ "name": "Ajvar blagi", "caloriesKcal": 120 }""");
        var sut = Client(new PartnerBarcodeCatalogModel
        {
            Name = "Paket.mk", ProductUrl = "https://api.paket.mk/products/{barcode}", ApiKey = "secret"
        }, handler);

        var result = await sut.GetProductAsync("5310000000017");

        Assert.Equal("Paket.mk", result!.SourceName);
        Assert.Equal("Ajvar blagi", result.Product.Name);
        Assert.Equal("https://api.paket.mk/products/5310000000017", sent!.RequestUri!.ToString());
        Assert.Equal("Bearer secret", sent.Headers.Authorization!.ToString());
    }

    private static PartnerFoodCatalogClient Client(PartnerBarcodeCatalogModel? catalog, HttpMessageHandler handler)
    {
        var providers = new Mock<ISupplementProvidersProvider>();
        providers.Setup(p => p.GetBarcodeCatalogAsync(It.IsAny<CancellationToken>())).ReturnsAsync(catalog);
        return new PartnerFoodCatalogClient(new HttpClient(handler), providers.Object, NullLogger<PartnerFoodCatalogClient>.Instance);
    }

    private sealed class JsonHandler(Action<HttpRequestMessage> onSend, string json) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            onSend(request);
            return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK)
            {
                Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json")
            });
        }
    }

    private sealed class ThrowingHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            throw new InvalidOperationException("The disabled client must not call out.");
    }
}
