FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY src/Silen.Tools.ImportFoodNutrition/Silen.Tools.ImportFoodNutrition.csproj src/Silen.Tools.ImportFoodNutrition/
RUN dotnet restore src/Silen.Tools.ImportFoodNutrition/Silen.Tools.ImportFoodNutrition.csproj

COPY src/Silen.Tools.ImportFoodNutrition/ src/Silen.Tools.ImportFoodNutrition/
RUN dotnet publish src/Silen.Tools.ImportFoodNutrition/Silen.Tools.ImportFoodNutrition.csproj -c Release -o /app

FROM mcr.microsoft.com/dotnet/runtime:8.0 AS runtime
WORKDIR /app
COPY --from=build /app .

ENTRYPOINT ["dotnet", "Silen.Tools.ImportFoodNutrition.dll"]
