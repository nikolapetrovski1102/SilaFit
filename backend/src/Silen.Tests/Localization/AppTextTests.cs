using Silen.Common.Contracts;
using Silen.Common.Localization;
using Silen.Common.Models;
using Silen.Services.Helpers;
using Xunit;

namespace Silen.Tests.Localization;

public class AppTextTests
{
    [Fact]
    public void Translate_English_ReturnsTextUnchanged()
    {
        Assert.Equal("Give the split a name.", AppText.Translate("Give the split a name.", AppText.English));
    }

    [Fact]
    public void Translate_Macedonian_UsesExactEntry()
    {
        Assert.Equal("Дај му име на сплитот.", AppText.Translate("Give the split a name.", "mk-MK"));
    }

    [Fact]
    public void Translate_Macedonian_FillsTemplateValues()
    {
        Assert.Equal(
            "Ги искористи сите 3 увози на тренинзи за денес. Се обновуваат на полноќ.",
            AppText.Translate("You've used all 3 workout imports for today. They reset at midnight.", AppText.Macedonian));
    }

    [Fact]
    public void Translate_Macedonian_UnknownMessage_FallsBackToEnglish()
    {
        Assert.Equal("Some brand-new message.", AppText.Translate("Some brand-new message.", AppText.Macedonian));
    }

    [Theory]
    [InlineData(null, "en")]
    [InlineData("", "en")]
    [InlineData("de", "en")]
    [InlineData("en-US", "en")]
    [InlineData("mk", "mk")]
    [InlineData("MK-mk", "mk")]
    public void Normalize_MapsToSupportedLanguage(string? input, string expected)
    {
        Assert.Equal(expected, AppText.Normalize(input));
    }

    [Fact]
    public async Task ApiResponseFail_FollowsRequestLanguage_AndOutsideRequestStaysEnglish()
    {
        await Task.Run(() =>
        {
            AppText.SetRequestLanguage("mk");
            Assert.Equal("Нешто тргна наопаку", ApiResponse.Fail("Something went wrong").Message);
        });

        Assert.Equal("Something went wrong", ApiResponse.Fail("Something went wrong").Message);
    }

    [Fact]
    public void Composer_UsesCandidateLanguage()
    {
        var candidate = new NotificationCandidateModel { UserId = Guid.NewGuid(), DisplayName = "Ана Петрова", Language = "mk" };
        var content = NotificationMessageComposer.Comeback(candidate, new DateOnly(2026, 11, 12));

        Assert.Matches("[а-шѓѕјљњќџ]", content.Title);
        Assert.Equal("today", content.Screen);
    }

    [Fact]
    public void TrainerProgramAssigned_Macedonian()
    {
        var content = NotificationMessageComposer.TrainerProgramAssigned(true, "Push Pull Legs", null, false, "mk");

        Assert.Equal("нов сплит од тренерот 💪", content.Title);
        Assert.Equal("твојот тренер ти додели Push Pull Legs. отвори го и почни.", content.Body);
    }
}
