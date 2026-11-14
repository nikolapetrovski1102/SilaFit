/// A partner shop with a discount code for SilaFit users:
/// `GET api/providers`. Managed in the admin console under Providers.
class SupplementProvider {
  final String providerId;
  final String name;
  final String? tagline;
  final String? logoUrl;
  final String? promoCode;
  final String? discountLabel;
  final String? shopUrl;
  final String category;
  final int sortOrder;

  /// The grocery partner (paket.mk): recipes, the diet plan shopping list and
  /// a barcode scan offer to order their ingredients here.
  final bool ordersIngredients;

  /// Product search with `{query}` where the search text goes; null opens
  /// [shopUrl] instead.
  final String? searchUrl;

  const SupplementProvider({
    required this.providerId,
    required this.name,
    this.tagline,
    this.logoUrl,
    this.promoCode,
    this.discountLabel,
    this.shopUrl,
    this.category = 'Protein',
    this.sortOrder = 0,
    this.ordersIngredients = false,
    this.searchUrl,
  });

  bool get sellsProtein => category.toLowerCase() == 'protein';

  /// The page to open for one ingredient: the partner's search for it, or
  /// the shop's front page without a search link.
  String? searchUrlFor(String query) {
    final template = searchUrl;
    if (template == null || !template.contains('{query}')) return shopUrl;
    return template.replaceAll('{query}', Uri.encodeQueryComponent(query));
  }

  factory SupplementProvider.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    String? text(String key) {
      final value = (map[key] as String?)?.trim();
      return value == null || value.isEmpty ? null : value;
    }

    return SupplementProvider(
      providerId: map['providerId'] as String,
      name: map['name'] as String? ?? '',
      tagline: text('tagline'),
      logoUrl: text('logoUrl'),
      promoCode: text('promoCode'),
      discountLabel: text('discountLabel'),
      shopUrl: text('shopUrl'),
      category: text('category') ?? 'Protein',
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      ordersIngredients: map['ordersIngredients'] as bool? ?? false,
      searchUrl: text('searchUrl'),
    );
  }

  static List<SupplementProvider> listFromJson(dynamic json) =>
      (json as List<dynamic>? ?? const [])
          .map(SupplementProvider.fromJson)
          .toList();
}
