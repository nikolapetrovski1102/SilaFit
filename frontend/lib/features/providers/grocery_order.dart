import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/silen_button.dart';
import 'provider_logo.dart';
import 'supplement_provider_models.dart';
import 'supplement_providers_repository.dart';
import '../../l10n/l10n.dart';

/// "Order the ingredients on paket.mk": a button for a recipe or a shopping
/// list that opens [showGroceryOrderSheet]. Renders nothing until a grocery
/// partner is switched on in the console, so it can ship before the deal.
class OrderIngredientsButton extends StatefulWidget {
  final List<String> ingredients;

  const OrderIngredientsButton({super.key, required this.ingredients});

  @override
  State<OrderIngredientsButton> createState() => _OrderIngredientsButtonState();
}

class _OrderIngredientsButtonState extends State<OrderIngredientsButton> {
  SupplementProvider? _partner;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final partner =
        await context.read<SupplementProvidersRepository>().groceryPartner();
    if (mounted && partner != null) setState(() => _partner = partner);
  }

  @override
  Widget build(BuildContext context) {
    final partner = _partner;
    if (partner == null || widget.ingredients.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: SecondaryPillButton(
        label: tr('Order the ingredients on {name}', {'name': partner.name}),
        icon: Icons.shopping_basket_outlined,
        onPressed: () => showGroceryOrderSheet(context,
            partner: partner, ingredients: widget.ingredients),
      ),
    );
  }
}

/// The search text for an ingredient line: "200 g chicken breast (raw)" is
/// searched as "chicken breast" - the shop doesn't sell grams.
String groceryQuery(String ingredient) {
  var text = ingredient.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  text = text.split(RegExp(r'[,;]')).first;
  text = text.replaceFirst(
      RegExp(
          r'^\s*[\d.,/½¼¾⅓⅔\s-]*\s*(kg|g|gr|mg|ml|l|dl|tbsp|tsp|cups?|pcs?|pieces?|slices?|cloves?|handful|pinch|scoops?|x|г|кг|мл|л|парче|парчиња|лажица|лажици|лажичка|шолја)?\.?\s+(of\s+)?',
          caseSensitive: false),
      '');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.isEmpty ? ingredient.trim() : text;
}

/// The partner's code (copied, ready for checkout) and the ingredients, each
/// a tap away from the partner's search for it.
Future<void> showGroceryOrderSheet(
  BuildContext context, {
  required SupplementProvider partner,
  required List<String> ingredients,
}) {
  if (partner.promoCode != null) {
    Clipboard.setData(ClipboardData(text: partner.promoCode!));
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (sheetContext) =>
        _GroceryOrderSheet(partner: partner, ingredients: ingredients),
  );
}

class _GroceryOrderSheet extends StatelessWidget {
  final SupplementProvider partner;
  final List<String> ingredients;

  const _GroceryOrderSheet({required this.partner, required this.ingredients});

  bool get _searchable => partner.searchUrl != null;

  Future<void> _open(BuildContext context, String? url) async {
    if (url == null) return;
    if (partner.promoCode != null) {
      await Clipboard.setData(ClipboardData(text: partner.promoCode!));
    }
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr("Couldn't open the shop."))));
    }
  }

  Future<void> _copyList(BuildContext context) async {
    await Clipboard.setData(
        ClipboardData(text: ingredients.map((i) => '• $i').join('\n')));
    HapticFeedback.selectionClick();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('Shopping list copied.'))));
  }

  @override
  Widget build(BuildContext context) {
    final offer = [
      if (partner.discountLabel != null) partner.discountLabel!,
      if (partner.promoCode != null)
        tr('code {code}', {'code': partner.promoCode}),
    ].join(' · ');
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
              AppSpacing.lg, AppSpacing.marginMobile, AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ProviderLogo(provider: partner, size: 44),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Order on {name}', {'name': partner.name}),
                            style: AppTypography.headlineSm),
                        if (offer.isNotEmpty)
                          Text(offer,
                              style: AppTypography.labelSm
                                  .copyWith(color: AppColors.accent)),
                      ],
                    ),
                  ),
                ],
              ),
              if (partner.promoCode != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  tr('Your code {code} is copied. Paste it at checkout.',
                      {'code': partner.promoCode}),
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Text(
                  _searchable
                      ? tr('TAP AN INGREDIENT TO FIND IT')
                      : tr('INGREDIENTS'),
                  style: AppTypography.labelCaps),
              const SizedBox(height: AppSpacing.xs),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final ingredient in ingredients)
                      InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.inset),
                        onTap: _searchable
                            ? () => _open(context,
                                partner.searchUrlFor(groceryQuery(ingredient)))
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.circle_outlined,
                                  size: 16, color: AppColors.accent),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                  child: Text(ingredient,
                                      style: AppTypography.bodyMd)),
                              if (_searchable)
                                Icon(Icons.search_rounded,
                                    size: 20,
                                    color: AppColors.onSurfaceVariant),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryPillButton(
                label: tr('Open {name}', {'name': partner.name}),
                icon: Icons.open_in_new_rounded,
                onPressed: partner.shopUrl == null
                    ? null
                    : () => _open(context, partner.shopUrl),
              ),
              const SizedBox(height: AppSpacing.xs),
              SecondaryPillButton(
                label: tr('Copy the shopping list'),
                icon: Icons.copy_rounded,
                onPressed: () => _copyList(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// After a barcode scan in the meal tracker: one line offering the scanned
/// product on the grocery partner. Dismissed for the rest of the session.
class GroceryProductHint extends StatefulWidget {
  final String? productName;

  const GroceryProductHint({super.key, required this.productName});

  static bool _dismissed = false;

  @override
  State<GroceryProductHint> createState() => _GroceryProductHintState();
}

class _GroceryProductHintState extends State<GroceryProductHint> {
  SupplementProvider? _partner;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _maybeLoad();
  }

  @override
  void didUpdateWidget(covariant GroceryProductHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeLoad();
  }

  /// Only asks for the partner once a scanned product is actually in the meal.
  void _maybeLoad() {
    if (_requested || widget.productName == null) return;
    _requested = true;
    _load();
  }

  Future<void> _load() async {
    final partner =
        await context.read<SupplementProvidersRepository>().groceryPartner();
    if (mounted && partner != null) setState(() => _partner = partner);
  }

  @override
  Widget build(BuildContext context) {
    final partner = _partner;
    final name = widget.productName;
    final show = partner != null && name != null && !GroceryProductHint._dismissed;
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _chip(context, partner, name),
            ),
    );
  }

  Widget _chip(BuildContext context, SupplementProvider partner, String name) {
    return Material(
      color: AppColors.surfaceContainerHigh.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        canRequestFocus: false,
        onTap: () => showGroceryOrderSheet(context,
            partner: partner, ingredients: [name]),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 2, 6),
          child: Row(
            children: [
              ProviderLogo(provider: partner, size: 28),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  tr('Get {product} on {name}',
                      {'product': name, 'name': partner.name}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.onSurface),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('Hide'),
                icon: Icon(Icons.close_rounded,
                    size: 18, color: AppColors.onSurfaceVariant),
                onPressed: () =>
                    setState(() => GroceryProductHint._dismissed = true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
