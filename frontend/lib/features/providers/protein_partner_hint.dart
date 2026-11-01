import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'provider_actions.dart';
import 'provider_logo.dart';
import 'supplement_provider_models.dart';
import 'supplement_providers_repository.dart';

/// A one-line partner nudge shown above "Save meal" while a meal being logged
/// is protein-heavy: the partner's logo, the discount, and a tap that copies
/// the code and opens the shop. Dismissing it hides it for a week.
class ProteinPartnerHint extends StatefulWidget {
  final double proteinG;
  final double caloriesKcal;

  const ProteinPartnerHint(
      {super.key, required this.proteinG, required this.caloriesKcal});

  /// Protein-heavy: at least 25 g, or protein is 30%+ of the meal's calories.
  static bool isProteinHeavy(double proteinG, double caloriesKcal) =>
      proteinG >= 25 ||
      (caloriesKcal >= 100 && proteinG * 4 / caloriesKcal >= 0.30);

  @override
  State<ProteinPartnerHint> createState() => _ProteinPartnerHintState();
}

class _ProteinPartnerHintState extends State<ProteinPartnerHint> {
  static const _snoozeKey = 'protein_partner_hint_snoozed_until';
  static const _snooze = Duration(days: 7);

  SupplementProvider? _partner;
  bool _hidden = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getInt(_snoozeKey);
      if (until != null && DateTime.now().millisecondsSinceEpoch < until) {
        return;
      }
    } catch (_) {
      // Preferences unavailable: still show the hint.
    }
    if (!mounted) return;
    final partner =
        await context.read<SupplementProvidersRepository>().proteinPartner();
    if (!mounted || partner == null) return;
    setState(() {
      _partner = partner;
      _hidden = false;
    });
  }

  Future<void> _dismiss() async {
    setState(() => _hidden = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _snoozeKey, DateTime.now().add(_snooze).millisecondsSinceEpoch);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final partner = _partner;
    final show = !_hidden &&
        partner != null &&
        ProteinPartnerHint.isProteinHeavy(widget.proteinG, widget.caloriesKcal);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _chip(partner),
            ),
    );
  }

  Widget _chip(SupplementProvider partner) {
    final offer = [
      if (partner.discountLabel != null) partner.discountLabel!,
      if (partner.promoCode != null) 'code ${partner.promoCode}',
    ].join(' · ');
    return Material(
      color: AppColors.surfaceContainerHigh.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        canRequestFocus: false,
        onTap: () => partner.shopUrl != null
            ? openProviderShop(context, partner)
            : copyProviderCode(context, partner),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 2, 6),
          child: Row(
            children: [
              ProviderLogo(provider: partner, size: 28),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: 'Protein from ${partner.name}',
                        style: AppTypography.labelSm.copyWith(
                            color: AppColors.onSurface,
                            fontWeight: FontWeight.w600)),
                    if (offer.isNotEmpty)
                      TextSpan(
                          text: '  $offer',
                          style: AppTypography.labelSm
                              .copyWith(color: AppColors.accent)),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Hide for a week',
                icon: Icon(Icons.close_rounded,
                    size: 16, color: AppColors.onSurfaceVariant),
                onPressed: _dismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
