-- Creates the Silen database. Safe to re-run.
IF DB_ID(N'SilenDb') IS NULL
BEGIN
    CREATE DATABASE SilenDb;
END
GO
