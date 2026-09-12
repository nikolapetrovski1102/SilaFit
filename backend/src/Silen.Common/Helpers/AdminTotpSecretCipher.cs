namespace Silen.Common.Helpers;

/// <summary>
/// Wraps the TOTP secret in FieldCipher's AES-256-GCM, keyed by the same
/// Encryption:MasterKeyBase64 the column-encryption rollout already uses.
///
/// The second factor is only as private as its shared secret, so it is never
/// stored in the clear: `AdminUsers.TotpSecretCipher` holds FieldCipher output and
/// the master key lives with the other deployment secrets (deploy/.env), not in
/// the database. Shared by <c>Silen.Services.AdminAuthService</c> (decrypt at
/// sign-in) and <c>Silen.Tools.AdminProvision</c> (encrypt at enrollment) so both
/// sides can never drift.
/// </summary>
public static class AdminTotpSecretCipher
{
    public static byte[] Encrypt(string base32Secret, byte[] masterKey) =>
        FieldCipher.EncryptString(base32Secret, masterKey);

    public static string Decrypt(byte[] ciphertext, byte[] masterKey) =>
        FieldCipher.DecryptString(ciphertext, masterKey);

    /// <summary>
    /// Turns the base64 master key into bytes, failing loudly with a message that
    /// names the setting - a misconfigured key must never look like a wrong
    /// password, and it must never silently fall back to plaintext.
    /// </summary>
    public static byte[] ParseMasterKey(string masterKeyBase64)
    {
        if (string.IsNullOrWhiteSpace(masterKeyBase64))
        {
            throw new InvalidOperationException("Encryption:MasterKeyBase64 (ENCRYPTION_MASTER_KEY) is not configured, so the TOTP secret cannot be decrypted.");
        }

        byte[] key;
        try
        {
            key = Convert.FromBase64String(masterKeyBase64);
        }
        catch (FormatException ex)
        {
            throw new InvalidOperationException("Encryption:MasterKeyBase64 is not valid base64.", ex);
        }

        if (key.Length != FieldCipher.KeySizeBytes)
        {
            throw new InvalidOperationException($"Encryption:MasterKeyBase64 must decode to {FieldCipher.KeySizeBytes} bytes, got {key.Length}.");
        }

        return key;
    }
}
