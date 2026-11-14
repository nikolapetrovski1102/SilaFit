import 'meal_models.dart';

/// Reads an Open Food Facts v2 product response on the device, so a scan the
/// catalog missed can be shown the moment OFF answers - the server save runs
/// behind it. Mirrors `OpenFoodFactsClient.Parse` and `FoodService.IsPlausible`
/// on the server: whatever the phone shows as found, the server would save.
class OpenFoodFactsProduct {
  OpenFoodFactsProduct._();

  static const sourceName = 'Open Food Facts';

  static const _maxNameLength = 200;
  static const _maxBrandLength = 120;
  static const _maxKcalPer100G = 900.0;
  static const _maxGramsPer100G = 100.0;
  static const _maxSodiumMgPer100G = 40000.0;
  static const _maxServingSizeG = 5000.0;

  /// A food ready to log, or null when OFF lacks a name or plausible
  /// nutrition. Its id is 0 (not in the catalog yet), so it logs with its
  /// nutrition inline - the same way photo-scanned foods do.
  static FoodItem? toFood(String barcode, Map<String, dynamic> response) {
    final product = _product(response);
    if (product == null) return null;
    final name = _name(product);
    final n = product['nutriments'];
    final nutriments =
        n is Map<String, dynamic> ? n : const <String, dynamic>{};

    final kcal = _number(nutriments['energy-kcal_100g']);
    final protein = _number(nutriments['proteins_100g']);
    final carbs = _number(nutriments['carbohydrates_100g']);
    final fat = _number(nutriments['fat_100g']);
    final fiber = _number(nutriments['fiber_100g']);
    final sugar = _number(nutriments['sugars_100g']);
    final sodiumG = _number(nutriments['sodium_100g']);
    final sodiumMg = sodiumG == null ? null : sodiumG * 1000;

    if (name == null ||
        kcal == null ||
        protein == null ||
        carbs == null ||
        fat == null) {
      return null;
    }
    if ([kcal, protein, carbs, fat, fiber, sugar, sodiumMg]
            .any((v) => v != null && v < 0) ||
        kcal > _maxKcalPer100G ||
        protein + carbs + fat > _maxGramsPer100G ||
        (sodiumMg ?? 0) > _maxSodiumMgPer100G) {
      return null;
    }
    // Energy has to roughly agree with the macros (catches kJ typed as kcal).
    final atwater = 4 * protein + 4 * carbs + 9 * fat;
    if ((atwater - kcal > 50 && kcal < 0.5 * atwater) || kcal - atwater > 300) {
      return null;
    }

    return FoodItem(
      foodNutritionId: 0,
      name: name,
      brandName: _brand(product),
      sourceName: sourceName,
      servingSizeG: _serving(product),
      caloriesKcal: kcal,
      proteinG: protein,
      carbohydrateG: carbs,
      fatG: fat,
      fiberG: fiber,
      sugarG: sugar,
      sodiumMg: sodiumMg,
      barcode: barcode,
      imageUrl: _image(product),
    );
  }

  /// What OFF knows when it can't be logged as is - prefills the "add it" form.
  static BarcodeProductHint? toHint(Map<String, dynamic> response) {
    final product = _product(response);
    if (product == null) return null;
    final hint = BarcodeProductHint(
      name: _name(product),
      brandName: _brand(product),
      imageUrl: _image(product),
      servingSizeG: _serving(product),
    );
    return hint.name == null && hint.brandName == null ? null : hint;
  }

  static Map<String, dynamic>? _product(Map<String, dynamic> response) {
    final product = response['product'];
    return response['status'] == 0 || product is! Map<String, dynamic>
        ? null
        : product;
  }

  static String? _name(Map<String, dynamic> p) {
    final name = _firstText(
        p, const ['product_name', 'product_name_en', 'product_name_mk']);
    return name == null || name.length <= _maxNameLength
        ? name
        : name.substring(0, _maxNameLength);
  }

  /// "Vitaminka, Swisslion" -> "Vitaminka": OFF lists the brand and its owners.
  static String? _brand(Map<String, dynamic> p) {
    final brand = _text(p['brands'])
        ?.split(',')
        .map((b) => b.trim())
        .firstWhere((b) => b.isNotEmpty, orElse: () => '');
    if (brand == null || brand.isEmpty) return null;
    return brand.length <= _maxBrandLength
        ? brand
        : brand.substring(0, _maxBrandLength);
  }

  static String? _image(Map<String, dynamic> p) =>
      _firstText(p, const ['image_front_small_url', 'image_front_url']);

  static double? _serving(Map<String, dynamic> p) {
    final serving = _number(p['serving_quantity']);
    return serving != null && serving > 0 && serving <= _maxServingSizeG
        ? serving
        : null;
  }

  static String? _firstText(Map<String, dynamic> p, List<String> keys) {
    for (final key in keys) {
      final value = _text(p[key]);
      if (value != null) return value;
    }
    return null;
  }

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// OFF sends numbers as JSON numbers or as strings, depending on the field.
  static double? _number(Object? value) => switch (value) {
        num n => n.toDouble(),
        String s => double.tryParse(s.trim()),
        _ => null,
      };
}
