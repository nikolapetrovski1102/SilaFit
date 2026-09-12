namespace Silen.Common.Helpers;

/// <summary>
/// Base32 (RFC 4648, alphabet A-Z2-7) encoding for TOTP secrets, because that is
/// the format every authenticator app expects to be handed in an otpauth:// URI.
/// Kept separate from <see cref="TotpHelper"/> so the padding/case tolerance that
/// typed-in secrets need is testable on its own.
/// </summary>
public static class Base32Helper
{
    private const string Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
    private const int BitsPerCharacter = 5;

    /// <summary>Encodes without padding - authenticator apps accept unpadded secrets and the URI reads better.</summary>
    public static string Encode(byte[] bytes)
    {
        if (bytes.Length == 0)
        {
            return string.Empty;
        }

        var result = new System.Text.StringBuilder((bytes.Length * 8 + BitsPerCharacter - 1) / BitsPerCharacter);
        var buffer = 0;
        var bitsInBuffer = 0;

        foreach (var value in bytes)
        {
            buffer = (buffer << 8) | value;
            bitsInBuffer += 8;

            while (bitsInBuffer >= BitsPerCharacter)
            {
                bitsInBuffer -= BitsPerCharacter;
                result.Append(Alphabet[(buffer >> bitsInBuffer) & 0x1F]);
            }
        }

        if (bitsInBuffer > 0)
        {
            result.Append(Alphabet[(buffer << (BitsPerCharacter - bitsInBuffer)) & 0x1F]);
        }

        return result.ToString();
    }

    /// <summary>
    /// Decodes a secret as typed/scanned by a human: case-insensitive, ignores
    /// spaces and dashes (people paste them from wherever the secret was shown)
    /// and tolerates trailing '=' padding.
    /// </summary>
    public static byte[] Decode(string encoded)
    {
        var result = new List<byte>(encoded.Length * BitsPerCharacter / 8);
        var buffer = 0;
        var bitsInBuffer = 0;

        foreach (var character in encoded)
        {
            if (character is '=' or ' ' or '-')
            {
                continue;
            }

            var index = Alphabet.IndexOf(char.ToUpperInvariant(character));
            if (index < 0)
            {
                throw new FormatException($"'{character}' is not a valid base32 character.");
            }

            buffer = (buffer << BitsPerCharacter) | index;
            bitsInBuffer += BitsPerCharacter;

            if (bitsInBuffer >= 8)
            {
                bitsInBuffer -= 8;
                result.Add((byte)((buffer >> bitsInBuffer) & 0xFF));
            }
        }

        return [.. result];
    }
}
