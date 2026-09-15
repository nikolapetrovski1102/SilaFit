# Mock-data seeder (see this project's Program.cs and deploy/README.md).
# Fills one existing user's workouts/meals/hydration/bodyweight with a generated
# month of history, or creates/reuses the demo Guest device accounts. Profile-gated
# like the other tools, so a plain `docker compose up` never starts it:
#
#   docker compose --profile tools run --rm --build silen-seed-mock-data -- --email=you@example.com
#
# Build context is backend/ (same as ../../Dockerfile for Silen.Api), so paths
# below are relative to that.
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY src/Silen.Common/Silen.Common.csproj src/Silen.Common/
COPY src/Silen.Data/Silen.Data.csproj src/Silen.Data/
COPY src/Silen.Tools.SeedMockData/Silen.Tools.SeedMockData.csproj src/Silen.Tools.SeedMockData/
RUN dotnet restore src/Silen.Tools.SeedMockData/Silen.Tools.SeedMockData.csproj

COPY src/Silen.Common/ src/Silen.Common/
COPY src/Silen.Data/ src/Silen.Data/
COPY src/Silen.Tools.SeedMockData/ src/Silen.Tools.SeedMockData/
RUN dotnet publish src/Silen.Tools.SeedMockData/Silen.Tools.SeedMockData.csproj -c Release -o /app

# Console tool - no Kestrel, but Silen.Common carries a
# <FrameworkReference Include="Microsoft.AspNetCore.App" /> (see its .csproj),
# so anything referencing it needs the ASP.NET Core shared framework at
# runtime, not just dotnet/runtime - same base image as Silen.Api's own.
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .

ENTRYPOINT ["dotnet", "Silen.Tools.SeedMockData.dll"]
