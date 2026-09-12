namespace Silen.Common.Enums;

/// <summary>
/// Guest accounts are created automatically from a device id and can use the
/// core tracking features. Registered accounts have linked at least one real
/// identity (email, Google or Apple) and are the only tier allowed to access
/// progress analytics, purchases and other account-gated features.
/// </summary>
public enum AccountTier
{
    Guest = 0,
    Registered = 1
}
