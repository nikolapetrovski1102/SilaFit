using System.Data;
using Microsoft.Data.SqlClient;

internal sealed class SqlFoodWriter : IAsyncDisposable
{
    private const int BatchSize = 5000;
    private readonly SqlConnection connection;
    private readonly DataTable batch = CreateTable();
    private long accepted;

    public SqlFoodWriter(string connectionString) => connection = new SqlConnection(connectionString);

    public long Accepted => accepted;

    public async Task OpenAsync(CancellationToken cancellationToken)
    {
        await connection.OpenAsync(cancellationToken);
        await using var command = connection.CreateCommand();
        command.CommandText = """
            IF OBJECT_ID(N'dbo.FoodNutrition', N'U') IS NULL
                THROW 51000, 'dbo.FoodNutrition is missing. Run database/scripts/deploy.sh first.', 1;
            """;
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task AddAsync(FoodNutritionRow row, CancellationToken cancellationToken)
    {
        row = row.Sanitize();
        if (!row.HasUsefulMacros || !row.IsCatalogQuality
            || string.IsNullOrWhiteSpace(row.Name) || string.IsNullOrWhiteSpace(row.SourceFoodId))
        {
            return;
        }

        batch.Rows.Add(
            Fit(row.Name, 500), Fit(row.NormalizedName, 500), Db(Fit(row.BrandName, 300)),
            Db(Fit(row.Barcode, 80)), Db(Fit(row.DataType, 50)), Fit(row.SourceName, 40),
            Fit(row.SourceFoodId, 120), Db(Fit(row.SourceUrl, 1000)), Db(row.ServingSizeG),
            Db(row.CaloriesKcal), Db(row.ProteinG), Db(row.CarbohydrateG), Db(row.FatG),
            Db(row.FiberG), Db(row.SugarG), Db(row.SodiumMg), row.IsBranded, row.ContentHash);

        if (batch.Rows.Count >= BatchSize)
        {
            await FlushAsync(cancellationToken);
        }
    }

    public async Task FlushAsync(CancellationToken cancellationToken)
    {
        if (batch.Rows.Count == 0) return;

        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(cancellationToken);
        await using var create = connection.CreateCommand();
        create.Transaction = transaction;
        create.CommandText = """
            DROP TABLE IF EXISTS #FoodNutritionImport;
            CREATE TABLE #FoodNutritionImport
            (
                Name NVARCHAR(500), NormalizedName NVARCHAR(500), BrandName NVARCHAR(300), Barcode NVARCHAR(80),
                DataType NVARCHAR(50), SourceName NVARCHAR(40), SourceFoodId NVARCHAR(120), SourceUrl NVARCHAR(1000),
                ServingSizeG DECIMAL(12,3), CaloriesKcal DECIMAL(12,3), ProteinG DECIMAL(12,3),
                CarbohydrateG DECIMAL(12,3), FatG DECIMAL(12,3), FiberG DECIMAL(12,3), SugarG DECIMAL(12,3),
                SodiumMg DECIMAL(12,3), IsBranded BIT, ContentHash BINARY(32)
            );
            """;
        await create.ExecuteNonQueryAsync(cancellationToken);

        using (var bulk = new SqlBulkCopy(connection, SqlBulkCopyOptions.TableLock, transaction))
        {
            bulk.DestinationTableName = "#FoodNutritionImport";
            bulk.BatchSize = batch.Rows.Count;
            foreach (DataColumn column in batch.Columns)
            {
                bulk.ColumnMappings.Add(column.ColumnName, column.ColumnName);
            }
            await bulk.WriteToServerAsync(batch, cancellationToken);
        }

        await using var merge = connection.CreateCommand();
        merge.Transaction = transaction;
        merge.CommandText = """
            MERGE dbo.FoodNutrition WITH (HOLDLOCK) AS target
            USING
            (
                SELECT *, ROW_NUMBER() OVER (PARTITION BY SourceName, SourceFoodId ORDER BY SourceFoodId) AS SourceRank,
                          ROW_NUMBER() OVER (PARTITION BY ContentHash ORDER BY SourceFoodId) AS HashRank
                FROM #FoodNutritionImport
            ) AS source
            ON target.SourceName = source.SourceName AND target.SourceFoodId = source.SourceFoodId
            WHEN MATCHED THEN UPDATE SET
                Name = source.Name, NormalizedName = source.NormalizedName, BrandName = source.BrandName,
                Barcode = source.Barcode, DataType = source.DataType, SourceUrl = source.SourceUrl,
                ServingSizeG = source.ServingSizeG, CaloriesKcal = source.CaloriesKcal,
                ProteinG = source.ProteinG, CarbohydrateG = source.CarbohydrateG, FatG = source.FatG,
                FiberG = source.FiberG, SugarG = source.SugarG, SodiumMg = source.SodiumMg,
                IsBranded = source.IsBranded, ImportedAtUtc = SYSUTCDATETIME()
            WHEN NOT MATCHED BY TARGET AND source.SourceRank = 1 AND source.HashRank = 1
                 AND NOT EXISTS (SELECT 1 FROM dbo.FoodNutrition existing WHERE existing.ContentHash = source.ContentHash)
            THEN INSERT
            (
                Name, NormalizedName, BrandName, Barcode, DataType, SourceName, SourceFoodId, SourceUrl,
                ServingSizeG, CaloriesKcal, ProteinG, CarbohydrateG, FatG, FiberG, SugarG, SodiumMg,
                IsBranded, ContentHash
            )
            VALUES
            (
                source.Name, source.NormalizedName, source.BrandName, source.Barcode, source.DataType,
                source.SourceName, source.SourceFoodId, source.SourceUrl, source.ServingSizeG,
                source.CaloriesKcal, source.ProteinG, source.CarbohydrateG, source.FatG,
                source.FiberG, source.SugarG, source.SodiumMg, source.IsBranded, source.ContentHash
            );
            """;
        await merge.ExecuteNonQueryAsync(cancellationToken);

        await using var cleanup = connection.CreateCommand();
        cleanup.Transaction = transaction;
        cleanup.CommandText = "DROP TABLE #FoodNutritionImport;";
        await cleanup.ExecuteNonQueryAsync(cancellationToken);
        await transaction.CommitAsync(cancellationToken);
        accepted += batch.Rows.Count;
        batch.Clear();
    }

    public async ValueTask DisposeAsync()
    {
        batch.Dispose();
        await connection.DisposeAsync();
    }

    private static object Db(object? value) => value ?? DBNull.Value;
    private static string? Fit(string? value, int length) =>
        value is null || value.Length <= length ? value : value[..length];

    private static DataTable CreateTable()
    {
        var table = new DataTable();
        table.Columns.Add("Name", typeof(string));
        table.Columns.Add("NormalizedName", typeof(string));
        table.Columns.Add("BrandName", typeof(string));
        table.Columns.Add("Barcode", typeof(string));
        table.Columns.Add("DataType", typeof(string));
        table.Columns.Add("SourceName", typeof(string));
        table.Columns.Add("SourceFoodId", typeof(string));
        table.Columns.Add("SourceUrl", typeof(string));
        foreach (var name in new[] { "ServingSizeG", "CaloriesKcal", "ProteinG", "CarbohydrateG", "FatG", "FiberG", "SugarG", "SodiumMg" })
            table.Columns.Add(name, typeof(decimal));
        table.Columns.Add("IsBranded", typeof(bool));
        table.Columns.Add("ContentHash", typeof(byte[]));
        return table;
    }
}
