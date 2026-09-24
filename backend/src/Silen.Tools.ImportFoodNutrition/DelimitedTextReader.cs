using System.Text;

internal sealed class DelimitedTextReader(TextReader reader, char delimiter) : IDisposable
{
    public IEnumerable<string[]> ReadRows()
    {
        var fields = new List<string>();
        var field = new StringBuilder();
        var quoted = false;

        while (true)
        {
            var next = reader.Read();
            if (next < 0)
            {
                if (quoted)
                {
                    throw new InvalidDataException("Delimited input ended inside a quoted field.");
                }

                if (field.Length > 0 || fields.Count > 0)
                {
                    fields.Add(field.ToString());
                    yield return fields.ToArray();
                }
                yield break;
            }

            var c = (char)next;
            if (quoted)
            {
                if (c == '"')
                {
                    var peek = reader.Peek();
                    if (peek == '"')
                    {
                        reader.Read();
                        field.Append('"');
                    }
                    else
                    {
                        quoted = false;
                    }
                }
                else
                {
                    field.Append(c);
                }
                continue;
            }

            if (c == '"' && field.Length == 0)
            {
                quoted = true;
            }
            else if (c == delimiter)
            {
                fields.Add(field.ToString());
                field.Clear();
            }
            else if (c == '\n')
            {
                fields.Add(field.ToString().TrimEnd('\r'));
                field.Clear();
                yield return fields.ToArray();
                fields.Clear();
            }
            else
            {
                field.Append(c);
            }
        }
    }

    public void Dispose() => reader.Dispose();
}
