SET NOCOUNT ON;
SELECT s.name AS SchemaName, t.name AS TableName, SUM(p.row_count) AS [RowCount]
FROM sys.dm_db_partition_stats p
JOIN sys.tables t ON t.object_id=p.object_id
JOIN sys.schemas s ON s.schema_id=t.schema_id
WHERE p.index_id IN (0,1)
GROUP BY s.name,t.name ORDER BY s.name,t.name;
SELECT d.name, d.state_desc, e.encryption_state
FROM sys.databases d LEFT JOIN sys.dm_database_encryption_keys e ON e.database_id=d.database_id
WHERE d.name='SilenDb';
DBCC CHECKDB (SilenDb) WITH NO_INFOMSGS;
