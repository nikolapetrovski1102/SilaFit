import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/silen_ambient_backdrop.dart';
import 'provider_actions.dart';
import 'provider_logo.dart';
import 'supplement_provider_models.dart';
import 'supplement_providers_repository.dart';

/// Settings -> Partner discounts: every partner shop with its code.
class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({super.key});

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  ResourceState<List<SupplementProvider>> _state =
      const ResourceState.loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (!refresh) setState(() => _state = const ResourceState.loading());
    try {
      final list = await context
          .read<SupplementProvidersRepository>()
          .getAll(refresh: true);
      if (mounted) setState(() => _state = ResourceState.data(list));
    } on ApiException catch (e) {
      if (mounted) setState(() => _state = ResourceState.error(e.userMessage));
    } catch (_) {
      if (mounted) {
        setState(() => _state =
            const ResourceState.error("Couldn't load partner discounts."));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: SilenAmbientBackdrop()),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xs, AppSpacing.xs, AppSpacing.marginMobile, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(Icons.arrow_back_rounded,
                            color: AppColors.onSurface),
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text('Partner discounts',
                            style: AppTypography.bodyMd
                                .copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _load(refresh: true),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.marginMobile,
                          vertical: AppSpacing.lg),
                      child: ResourceBuilder<List<SupplementProvider>>(
                        state: _state,
                        onRetry: _load,
                        builder: (context, list) => _body(list),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(List<SupplementProvider> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Codes from shops we work with. Tap a code to copy it.',
          style:
              AppTypography.bodySm.copyWith(color: AppColors.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        if (list.isEmpty)
          SectionCard(
            child: Text('No partner discounts right now. Check back soon.',
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ),
        for (final p in list) ...[
          _ProviderCard(provider: p),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final SupplementProvider provider;

  const _ProviderCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final code = provider.promoCode;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProviderLogo(provider: provider, size: 44),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.name,
                        style: AppTypography.bodyMd
                            .copyWith(fontWeight: FontWeight.w600)),
                    if (provider.tagline != null)
                      Text(provider.tagline!,
                          style: AppTypography.bodySm
                              .copyWith(color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              if (provider.discountLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text(provider.discountLabel!,
                      style: AppTypography.labelSm
                          .copyWith(color: AppColors.accent)),
                ),
            ],
          ),
          if (code != null || provider.shopUrl != null)
            const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (code != null)
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.inset),
                    onTap: () => copyProviderCode(context, provider),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.inset),
                        border: Border.all(
                            color: AppColors.accent.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(code,
                                style: AppTypography.bodyMd.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2)),
                          ),
                          Icon(Icons.copy_rounded,
                              size: 18, color: AppColors.accent),
                        ],
                      ),
                    ),
                  ),
                ),
              if (code != null && provider.shopUrl != null)
                const SizedBox(width: AppSpacing.sm),
              if (provider.shopUrl != null)
                TextButton.icon(
                  onPressed: () => openProviderShop(context, provider),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Shop'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
