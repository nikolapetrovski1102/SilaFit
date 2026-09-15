# Notification publish batch (see this project's Program.cs and deploy/README.md).
# Built once by deploy.sh and then invoked from a frequent system cron entry -
# it is a short batch, so a cron-triggered one-shot container fits better than a
# long-running worker. The same service can instead run inside the API by
# setting NotificationPublish__RunInApi=true.
#
# Build context is backend/ (same as ../../Dockerfile for Silen.Api), so paths
# below are relative to that.
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY src/Silen.Common/Silen.Common.csproj src/Silen.Common/
COPY src/Silen.Data/Silen.Data.csproj src/Silen.Data/
COPY src/Silen.Services/Silen.Services.csproj src/Silen.Services/
COPY src/Silen.Tools.NotificationPublish/Silen.Tools.NotificationPublish.csproj src/Silen.Tools.NotificationPublish/
RUN dotnet restore src/Silen.Tools.NotificationPublish/Silen.Tools.NotificationPublish.csproj

COPY src/Silen.Common/ src/Silen.Common/
COPY src/Silen.Data/ src/Silen.Data/
COPY src/Silen.Services/ src/Silen.Services/
COPY src/Silen.Tools.NotificationPublish/ src/Silen.Tools.NotificationPublish/
RUN dotnet publish src/Silen.Tools.NotificationPublish/Silen.Tools.NotificationPublish.csproj -c Release -o /app

# Console tool - no Kestrel, but Silen.Common carries a
# <FrameworkReference Include="Microsoft.AspNetCore.App" /> (see its .csproj),
# so anything referencing it needs the ASP.NET Core shared framework at
# runtime, not just dotnet/runtime - same base image as Silen.Api's own.
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .

ENTRYPOINT ["dotnet", "Silen.Tools.NotificationPublish.dll"]
