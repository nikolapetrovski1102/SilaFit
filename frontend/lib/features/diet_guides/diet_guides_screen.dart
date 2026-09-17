import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/mascot/mascot_empty_state.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import 'diet_guide_controller.dart';
import 'diet_guide_detail_screen.dart';
import 'diet_guide_models.dart';
import 'diet_guide_repository.dart';

/// Browse view for the imported long-form diet guides (Clean Eating, Keto,
/// IIFYM, ...). Separate from `DietPlansScreen`, which lists the assignable
/// day-by-day meal plans.
class DietGuidesScreen extends StatefulWidget {
  const DietGuidesScreen({super.key});

  @override
  State<DietGuidesScreen> createState() => _DietGuidesScreenState();
}

class _DietGuidesScreenState extends State<DietGuidesScreen> {
  late final DietGuidesController _controller;

  @override
  void initState() {
    super.initState();
    _controller = context.read<DietGuidesController>();
    Future.microtask(_controller.load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Diet Guides', style: AppTypography.headlineSm),
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                AppSpacing.sm, AppSpacing.marginMobile, AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionEyebrow('Nutrition Library', color: AppColors.accent),
                const SizedBox(height: 4),
                Text('Diet Guides', style: AppTypography.headlineLg),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  'Reference guides on how each approach works, what it allows '
                  'and what the science says.',
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.md),
                ResourceBuilder<List<DietGuide>>(
                  state: _controller.state,
                  onRetry: _controller.load,
                  builder: (context, guides) => _buildContent(guides),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(List<DietGuide> guides) {
    if (guides.isEmpty) {
      return const MascotEmptyState(
        title: 'No diet guides yet',
        message: 'Diet guides will show up here once they are available.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final guide in guides) ...[
          _DietGuideCard(
            guide: guide,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DietGuideDetailScreen(
                controller: DietGuideDetailController(
                  context.read<DietGuideRepository>(),
                  guide.dietGuideId,
                ),
                fallbackTitle: guide.title,
              ),
            )),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _DietGuideCard extends StatelessWidget {
  final DietGuide guide;
  final VoidCallback onTap;

  const _DietGuideCard({required this.guide, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = guide.imageUrl;
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppRadius.card)),
                  child: AspectRatio(
                    aspectRatio: 16 / 7,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.surfaceContainerHigh,
                        alignment: Alignment.center,
                        child: Icon(Icons.restaurant_menu_rounded,
                            color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(guide.title, style: AppTypography.headlineSm),
                    if (guide.summary != null && guide.summary!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        guide.summary!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySm
                            .copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        if (guide.sectionCount > 0)
                          PillChip(
                            label: '${guide.sectionCount} sections',
                            icon: Icons.menu_book_rounded,
                          ),
                        const Spacer(),
                        Icon(Icons.arrow_forward_rounded,
                            size: 18, color: AppColors.onSurfaceVariant),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
