FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY src/Silen.Tools.MigrateToPostgres/Silen.Tools.MigrateToPostgres.csproj src/Silen.Tools.MigrateToPostgres/
RUN dotnet restore src/Silen.Tools.MigrateToPostgres/Silen.Tools.MigrateToPostgres.csproj

COPY src/Silen.Tools.MigrateToPostgres/ src/Silen.Tools.MigrateToPostgres/
RUN dotnet publish src/Silen.Tools.MigrateToPostgres/Silen.Tools.MigrateToPostgres.csproj -c Release -o /app

FROM mcr.microsoft.com/dotnet/runtime:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .

ENTRYPOINT ["dotnet", "Silen.Tools.MigrateToPostgres.dll"]
