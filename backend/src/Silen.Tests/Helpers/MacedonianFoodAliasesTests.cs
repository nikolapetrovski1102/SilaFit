using Silen.Services.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public class MacedonianFoodAliasesTests
{
    [Theory]
    [InlineData("пилешко", "chicken")]
    [InlineData("пил", "chicken")]
    [InlineData("пилешки гради", "chicken breast")]
    [InlineData("пилешки гр", "chicken breast")]
    [InlineData("јајца варени", "egg boiled")]
    [InlineData("кисело млеко", "yogurt")]
    [InlineData("протеин 80", "protein 80")]
    [InlineData("непознато пиле", "chicken")]
    public void ToEnglishQuery_TranslatesKnownWords(string query, string expected)
    {
        Assert.Equal(expected, MacedonianFoodAliases.ToEnglishQuery(query));
    }

    [Theory]
    [InlineData("chicken breast")]
    [InlineData("непознато")]
    [InlineData("пи")]
    [InlineData("")]
    public void ToEnglishQuery_NothingToTranslate_ReturnsNull(string query)
    {
        Assert.Null(MacedonianFoodAliases.ToEnglishQuery(query));
    }
}
