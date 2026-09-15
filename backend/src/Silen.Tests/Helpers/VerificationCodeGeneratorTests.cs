using System.Text.RegularExpressions;
using Silen.Common.Helpers;
using Xunit;

namespace Silen.Tests.Helpers;

public partial class VerificationCodeGeneratorTests
{
    [GeneratedRegex(@"^\d{6}$")]
    private static partial Regex SixDigitCode();

    [Fact]
    public void GenerateCode_IsAlwaysSixDigits_WithLeadingZerosPreserved()
    {
        // No seed hook exists for forcing a low draw, so run enough iterations
        // that a leading-zero value (< 100,000, ~10% chance per draw) is
        // effectively certain to appear and get exercised by the format check.
        for (var i = 0; i < 200; i++)
        {
            var code = VerificationCodeGenerator.GenerateCode();
            Assert.Matches(SixDigitCode(), code);
        }
    }

    [Fact]
    public void GenerateCode_StaysWithinTheDocumentedRange()
    {
        for (var i = 0; i < 200; i++)
        {
            var code = int.Parse(VerificationCodeGenerator.GenerateCode());
            Assert.InRange(code, 0, 999_999);
        }
    }
}
