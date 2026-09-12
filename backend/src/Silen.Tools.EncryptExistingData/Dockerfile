# One-shot backfill tool for the column-encryption rollout (see
# database/schema/024_ColumnEncryptionAdd.sql / 025_ColumnEncryptionCutover.sql
# and this project's Program.cs). Built + run via `docker compose --profile
# tools run --rm silen-encrypt-backfill` from deploy.sh - the VPS has no
# host-level .NET SDK, everything runs through Docker.
#
# Build context is backend/ (same as ../../Dockerfile for Silen.Api), so paths
# below are relative to that.
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY src/Silen.Common/Silen.Common.csproj src/Silen.Common/
COPY src/Silen.Tools.EncryptExistingData/Silen.Tools.EncryptExistingData.csproj src/Silen.Tools.EncryptExistingData/
RUN dotnet restore src/Silen.Tools.EncryptExistingData/Silen.Tools.EncryptExistingData.csproj

COPY src/Silen.Common/ src/Silen.Common/
COPY src/Silen.Tools.EncryptExistingData/ src/Silen.Tools.EncryptExistingData/
RUN dotnet publish src/Silen.Tools.EncryptExistingData/Silen.Tools.EncryptExistingData.csproj -c Release -o /app

# Console tool only - no ASP.NET Kestrel/hosting needed, unlike Silen.Api's runtime image.
FROM mcr.microsoft.com/dotnet/runtime:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .

ENTRYPOINT ["dotnet", "Silen.Tools.EncryptExistingData.dll"]
