namespace Silen.Common.Helpers;

/// <summary>
/// Partially hides an email address for display (e.g. "we sent a code to
/// n***@sila.fitness") without hiding it completely - unlike <see cref="LogRedaction"/>,
/// the point here is to let the recipient recognize their own address, not to make it
/// unrecoverable.
/// </summary>
public static class EmailMasking
{
    public static string Mask(string email)
    {
        var atIndex = email.IndexOf('@');
        if (atIndex <= 0)
        {
            return "***";
        }

        var localPart = email[..atIndex];
        var domain = email[atIndex..];
        var visible = localPart[..1];

        return $"{visible}***{domain}";
    }
}
