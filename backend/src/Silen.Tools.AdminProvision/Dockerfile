# Admin console enrollment / credential rotation (see this project's Program.cs
# and deploy/README.md). Built + run via `docker compose --profile tools run --rm
# silen-admin-provision` - the VPS has no host-level .NET SDK, everything runs
# through Docker.
#
# Runs interactively by default (masked password prompt); set SILEN_ADMIN_USERNAME
# / SILEN_ADMIN_PASSWORD -e to run it non-interactively.
#
# Build context is backend/ (same as ../../Dockerfile for Silen.Api), so paths
# below are relative to that.
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY src/Silen.Common/Silen.Common.csproj src/Silen.Common/
COPY src/Silen.Tools.AdminProvision/Silen.Tools.AdminProvision.csproj src/Silen.Tools.AdminProvision/
RUN dotnet restore src/Silen.Tools.AdminProvision/Silen.Tools.AdminProvision.csproj

COPY src/Silen.Common/ src/Silen.Common/
COPY src/Silen.Tools.AdminProvision/ src/Silen.Tools.AdminProvision/
RUN dotnet publish src/Silen.Tools.AdminProvision/Silen.Tools.AdminProvision.csproj -c Release -o /app

# Console tool only - no ASP.NET Kestrel/hosting needed, unlike Silen.Api's runtime image.
FROM mcr.microsoft.com/dotnet/runtime:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .

ENTRYPOINT ["dotnet", "Silen.Tools.AdminProvision.dll"]
