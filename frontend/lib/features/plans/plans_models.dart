/// Mirrors `Silen.Common.Models.PlanModels` / `Silen.Common.Dtos.PlansDtos`.
class SubscriptionPlan {
  final String planId;
  final String code;
  final String name;
  final String? tagline;
  final double monthlyPrice;
  final double yearlyPrice;
  final bool isFeatured;

  // Store product IDs the catalogue is sold under - null for the free tier.
  // The billing-cycle toggle picks which one a purchase targets; the server
  // derives the granted plan from whichever of these the store confirms was
  // actually bought, never from the client's planId.
  final String? appStoreMonthlyProductId;
  final String? appStoreYearlyProductId;
  final String? playStoreMonthlyProductId;
  final String? playStoreYearlyProductId;

  const SubscriptionPlan({
    required this.planId,
    required this.code,
    required this.name,
    this.tagline,
    required this.monthlyPrice,
    required this.yearlyPrice,
    required this.isFeatured,
    this.appStoreMonthlyProductId,
    this.appStoreYearlyProductId,
    this.playStoreMonthlyProductId,
    this.playStoreYearlyProductId,
  });

  factory SubscriptionPlan.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return SubscriptionPlan(
      planId: map['planId'] as String,
      code: map['code'] as String? ?? '',
      name: map['name'] as String? ?? '',
      tagline: map['tagline'] as String?,
      monthlyPrice: (map['monthlyPrice'] as num?)?.toDouble() ?? 0,
      yearlyPrice: (map['yearlyPrice'] as num?)?.toDouble() ?? 0,
      isFeatured: map['isFeatured'] as bool? ?? false,
      appStoreMonthlyProductId: map['appStoreMonthlyProductId'] as String?,
      appStoreYearlyProductId: map['appStoreYearlyProductId'] as String?,
      playStoreMonthlyProductId: map['playStoreMonthlyProductId'] as String?,
      playStoreYearlyProductId: map['playStoreYearlyProductId'] as String?,
    );
  }
}

class PlanFeature {
  final String featureText;
  final bool isHighlighted;

  const PlanFeature({required this.featureText, required this.isHighlighted});

  factory PlanFeature.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return PlanFeature(
      featureText: map['featureText'] as String? ?? '',
      isHighlighted: map['isHighlighted'] as bool? ?? false,
    );
  }
}

class PlanCatalogEntry {
  final SubscriptionPlan plan;
  final List<PlanFeature> features;

  const PlanCatalogEntry({required this.plan, required this.features});

  factory PlanCatalogEntry.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return PlanCatalogEntry(
      plan: SubscriptionPlan.fromJson(map['plan']),
      features: (map['features'] as List<dynamic>? ?? [])
          .map((e) => PlanFeature.fromJson(e))
          .toList(),
    );
  }
}

/// The caller's current plan, mirroring `Silen.Common.Models.UserSubscriptionModel`
/// as `/plans/current` returns it. The server already substitutes a FREE row
/// when nothing active is on file; [CurrentSubscription.fromJson] re-applies
/// the same active/unexpired check so a row that lapsed since is FREE too.
class CurrentSubscription {
  final String planCode;
  final String planName;
  final String? billingCycle;
  final DateTime? expiresAtUtc;
  final bool autoRenewing;

  const CurrentSubscription({
    required this.planCode,
    required this.planName,
    this.billingCycle,
    this.expiresAtUtc,
    this.autoRenewing = false,
  });

  static const free = CurrentSubscription(planCode: 'FREE', planName: 'Free');

  bool get isPaid => planCode != 'FREE';

  factory CurrentSubscription.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    if (map['status'] != 'Active') return free;
    final expiry = DateTime.tryParse(map['expiresAtUtc'] as String? ?? '');
    if (expiry != null && !expiry.toUtc().isAfter(DateTime.now().toUtc())) {
      return free;
    }
    final code = (map['planCode'] as String? ?? 'FREE').toUpperCase();
    if (code == 'FREE') return free;
    final name = map['planName'] as String?;
    return CurrentSubscription(
      planCode: code,
      planName: name == null || name.isEmpty ? code : name,
      billingCycle: map['billingCycle'] as String?,
      expiresAtUtc: expiry,
      autoRenewing: map['autoRenewing'] as bool? ?? false,
    );
  }
}
