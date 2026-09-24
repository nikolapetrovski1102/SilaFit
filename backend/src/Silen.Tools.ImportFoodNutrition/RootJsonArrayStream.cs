// Presents the first JSON array inside an object-wrapped export as a standalone
// stream. This keeps USDA's multi-gigabyte JSON archives streaming: no full
// extraction and no in-memory JsonDocument are required.
internal sealed class RootJsonArrayStream(Stream inner) : Stream
{
    private readonly byte[] input = new byte[64 * 1024];
    private int inputOffset;
    private int inputLength;
    private bool started;
    private bool completed;
    private bool inString;
    private bool escaped;
    private int arrayDepth;

    public override bool CanRead => true;
    public override bool CanSeek => false;
    public override bool CanWrite => false;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }

    public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
    {
        if (completed || buffer.Length == 0) return 0;
        var written = 0;

        while (written < buffer.Length && !completed)
        {
            if (inputOffset >= inputLength)
            {
                inputLength = await inner.ReadAsync(input, cancellationToken);
                inputOffset = 0;
                if (inputLength == 0)
                {
                    completed = true;
                    break;
                }
            }

            var value = input[inputOffset++];
            if (!started)
            {
                if (value != (byte)'[') continue;
                started = true;
                arrayDepth = 1;
            }
            else if (inString)
            {
                if (escaped) escaped = false;
                else if (value == (byte)'\\') escaped = true;
                else if (value == (byte)'"') inString = false;
            }
            else if (value == (byte)'"')
            {
                inString = true;
            }
            else if (value == (byte)'[')
            {
                arrayDepth++;
            }
            else if (value == (byte)']')
            {
                arrayDepth--;
                if (arrayDepth == 0) completed = true;
            }

            buffer.Span[written++] = value;
        }

        return written;
    }

    public override int Read(byte[] buffer, int offset, int count) =>
        ReadAsync(buffer.AsMemory(offset, count)).AsTask().GetAwaiter().GetResult();
    public override void Flush() { }
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    protected override void Dispose(bool disposing) { if (disposing) inner.Dispose(); base.Dispose(disposing); }
    public override async ValueTask DisposeAsync() { await inner.DisposeAsync(); GC.SuppressFinalize(this); }
}
