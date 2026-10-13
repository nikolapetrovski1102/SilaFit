using Npgsql;
using NpgsqlTypes;

internal sealed class SqlFoodWriter : IAsyncDisposable
{
    private const int BatchSize = 5000;
    private readonly NpgsqlConnection connection;
    private readonly List<FoodNutritionRow> batch = new(BatchSize);
    private long accepted;

    public SqlFoodWriter(string connectionString) => connection = new NpgsqlConnection(connectionString);

    public long Accepted => accepted;

    public async Task OpenAsync(CancellationToken cancellationToken)
    {
        await connection.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = "SELECT to_regclass('dbo.foodnutrition') IS NOT NULL;";
        if (await command.ExecuteScalarAsync(cancellationToken) is not true)
            throw new InvalidOperationException("dbo.foodnutrition is missing. Run database/apply.sh first.");
    }

    public async Task AddAsync(FoodNutritionRow row, CancellationToken cancellationToken)
    {
        row = row.Sanitize();
        if (!row.HasUsefulMacros || !row.IsCatalogQuality
            || string.IsNullOrWhiteSpace(row.Name) || string.IsNullOrWhiteSpace(row.SourceFoodId))
        {
            return;
        }

        batch.Add(row);
        if (batch.Count >= BatchSize)
        {
            await FlushAsync(cancellationToken);
        }
    }

    public async Task FlushAsync(CancellationToken cancellationToken)
    {
        if (batch.Count == 0) return;

        await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
        await using (var create = new NpgsqlCommand("""
            CREATE TEMP TABLE foodnutritionimport
            (
                name varchar(500) COLLATE ci, normalizedname varchar(500) COLLATE "C", brandname varchar(300) COLLATE ci,
                barcode varchar(80) COLLATE ci, datatype varchar(50) COLLATE ci, sourcename varchar(40) COLLATE ci,
                sourcefoodid varchar(120) COLLATE ci, sourceurl varchar(1000) COLLATE ci,
                servingsizeg numeric(12,3), calorieskcal numeric(12,3), proteing numeric(12,3),
                carbohydrateg numeric(12,3), fatg numeric(12,3), fiberg numeric(12,3), sugarg numeric(12,3),
                sodiummg numeric(12,3), isbranded boolean, contenthash bytea
            ) ON COMMIT DROP;
            """, connection, transaction))
        {
            await create.ExecuteNonQueryAsync(cancellationToken);
        }

        await using (var import = await connection.BeginBinaryImportAsync("""
            COPY foodnutritionimport (name, normalizedname, brandname, barcode, datatype, sourcename, sourcefoodid,
                sourceurl, servingsizeg, calorieskcal, proteing, carbohydrateg, fatg, fiberg, sugarg, sodiummg,
                isbranded, contenthash) FROM STDIN (FORMAT BINARY)
            """, cancellationToken))
        {
            foreach (var row in batch)
            {
                await import.StartRowAsync(cancellationToken);
                await WriteText(import, Fit(row.Name, 500), cancellationToken);
                await WriteText(import, Fit(row.NormalizedName, 500), cancellationToken);
                await WriteText(import, Fit(row.BrandName, 300), cancellationToken);
                await WriteText(import, Fit(row.Barcode, 80), cancellationToken);
                await WriteText(import, Fit(row.DataType, 50), cancellationToken);
                await WriteText(import, Fit(row.SourceName, 40), cancellationToken);
                await WriteText(import, Fit(row.SourceFoodId, 120), cancellationToken);
                await WriteText(import, Fit(row.SourceUrl, 1000), cancellationToken);
                foreach (var value in new[] { row.ServingSizeG, row.CaloriesKcal, row.ProteinG, row.CarbohydrateG, row.FatG, row.FiberG, row.SugarG, row.SodiumMg })
                {
                    if (value is { } number) await import.WriteAsync(number, NpgsqlDbType.Numeric, cancellationToken);
                    else await import.WriteNullAsync(cancellationToken);
                }
                await import.WriteAsync(row.IsBranded, NpgsqlDbType.Boolean, cancellationToken);
                await import.WriteAsync(row.ContentHash, NpgsqlDbType.Bytea, cancellationToken);
            }
            await import.CompleteAsync(cancellationToken);
        }

        // Matching source rows are refreshed; new rows are inserted once per source key and
        // content hash, and skipped when another source already holds the same content.
        await using (var merge = new NpgsqlCommand("""
            INSERT INTO dbo.foodnutrition
            (
                name, normalizedname, brandname, barcode, datatype, sourcename, sourcefoodid, sourceurl,
                servingsizeg, calorieskcal, proteing, carbohydrateg, fatg, fiberg, sugarg, sodiummg,
                isbranded, contenthash
            )
            SELECT s.name, s.normalizedname, s.brandname, s.barcode, s.datatype, s.sourcename, s.sourcefoodid,
                   s.sourceurl, s.servingsizeg, s.calorieskcal, s.proteing, s.carbohydrateg, s.fatg, s.fiberg,
                   s.sugarg, s.sodiummg, s.isbranded, s.contenthash
            FROM
            (
                SELECT i.*, ROW_NUMBER() OVER (PARTITION BY sourcename, sourcefoodid ORDER BY sourcefoodid) AS sourcerank,
                            ROW_NUMBER() OVER (PARTITION BY contenthash ORDER BY sourcefoodid) AS hashrank
                FROM foodnutritionimport i
            ) s
            WHERE s.sourcerank = 1
              AND (EXISTS (SELECT 1 FROM dbo.foodnutrition t WHERE t.sourcename = s.sourcename AND t.sourcefoodid = s.sourcefoodid)
                   OR (s.hashrank = 1 AND NOT EXISTS (SELECT 1 FROM dbo.foodnutrition e WHERE e.contenthash = s.contenthash)))
            ON CONFLICT (sourcename, sourcefoodid) DO UPDATE SET
                name = excluded.name, normalizedname = excluded.normalizedname, brandname = excluded.brandname,
                barcode = excluded.barcode, datatype = excluded.datatype, sourceurl = excluded.sourceurl,
                servingsizeg = excluded.servingsizeg, calorieskcal = excluded.calorieskcal,
                proteing = excluded.proteing, carbohydrateg = excluded.carbohydrateg, fatg = excluded.fatg,
                fiberg = excluded.fiberg, sugarg = excluded.sugarg, sodiummg = excluded.sodiummg,
                isbranded = excluded.isbranded, importedatutc = dbo.sysutcdatetime();
            """, connection, transaction))
        {
            merge.CommandTimeout = 0;
            await merge.ExecuteNonQueryAsync(cancellationToken);
        }

        await transaction.CommitAsync(cancellationToken);
        accepted += batch.Count;
        batch.Clear();
    }

    public async ValueTask DisposeAsync() => await connection.DisposeAsync();

    private static Task WriteText(NpgsqlBinaryImporter import, string? value, CancellationToken cancellationToken) =>
        value is null
            ? import.WriteNullAsync(cancellationToken)
            : import.WriteAsync(value, NpgsqlDbType.Varchar, cancellationToken);

    private static string? Fit(string? value, int length) =>
        value is null || value.Length <= length ? value : value[..length];
}
