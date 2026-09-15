# Monthly review batch (see this project's Program.cs and deploy/README.md).
# Built + run via `docker compose --profile tools run --rm --build
# silen-monthly-review` - deploy.sh also installs a cron entry that invokes it on
# the 1st of each month, so the VPS never needs a host-level .NET SDK.
#
# Build context is backend/ (same as ../../Dockerfile for Silen.Api), so paths
# below are relative to that.
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY src/Silen.Common/Silen.Common.csproj src/Silen.Common/
COPY src/Silen.Data/Silen.Data.csproj src/Silen.Data/
COPY src/Silen.Services/Silen.Services.csproj src/Silen.Services/
COPY src/Silen.Tools.MonthlyReview/Silen.Tools.MonthlyReview.csproj src/Silen.Tools.MonthlyReview/
RUN dotnet restore src/Silen.Tools.MonthlyReview/Silen.Tools.MonthlyReview.csproj

COPY src/Silen.Common/ src/Silen.Common/
COPY src/Silen.Data/ src/Silen.Data/
COPY src/Silen.Services/ src/Silen.Services/
COPY src/Silen.Tools.MonthlyReview/ src/Silen.Tools.MonthlyReview/
RUN dotnet publish src/Silen.Tools.MonthlyReview/Silen.Tools.MonthlyReview.csproj -c Release -o /app

# Console tool - no Kestrel, but Silen.Common carries a
# <FrameworkReference Include="Microsoft.AspNetCore.App" /> (see its .csproj),
# so anything referencing it needs the ASP.NET Core shared framework at
# runtime, not just dotnet/runtime - same base image as Silen.Api's own.
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .

ENTRYPOINT ["dotnet", "Silen.Tools.MonthlyReview.dll"]
