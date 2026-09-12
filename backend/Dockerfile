FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY Silen.slnx .
COPY src/Silen.Common/Silen.Common.csproj src/Silen.Common/
COPY src/Silen.Data/Silen.Data.csproj src/Silen.Data/
COPY src/Silen.Services/Silen.Services.csproj src/Silen.Services/
COPY src/Silen.Api/Silen.Api.csproj src/Silen.Api/
RUN dotnet restore src/Silen.Api/Silen.Api.csproj

COPY src/ src/
RUN dotnet publish src/Silen.Api/Silen.Api.csproj -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "Silen.Api.dll"]
