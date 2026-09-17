import 'package:flutter/material.dart';

import '../../core/state/resource_state.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_card.dart';
import '../../core/widgets/section_eyebrow.dart';
import 'diet_guide_controller.dart';
import 'diet_guide_models.dart';

/// Read-only view of one imported diet guide: its header plus every ordered
/// section, with source lists and tables preserved.
class DietGuideDetailScreen extends StatefulWidget {
  final DietGuideDetailController controller;

  /// Shown in the app bar while the detail loads, so the header isn't blank.
  final String fallbackTitle;

  const DietGuideDetailScreen({
    super.key,
    required this.controller,
    required this.fallbackTitle,
  });

  @override
  State<DietGuideDetailScreen> createState() => _DietGuideDetailScreenState();
}

class _DietGuideDetailScreenState extends State<DietGuideDetailScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(widget.controller.load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.fallbackTitle,
            style: AppTypography.headlineSm, overflow: TextOverflow.ellipsis),
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          return ResourceBuilder<DietGuideDetail>(
            state: widget.controller.state,
            onRetry: widget.controller.load,
            builder: (context, detail) => _buildDetail(detail),
          );
        },
      ),
    );
  }

  Widget _buildDetail(DietGuideDetail detail) {
    final guide = detail.guide;
    final imageUrl = guide.imageUrl;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile, AppSpacing.sm,
          AppSpacing.marginMobile, AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (imageUrl != null && imageUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: AspectRatio(
                aspectRatio: 16 / 8,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          SectionEyebrow('Diet Guide', color: AppColors.accent),
          const SizedBox(height: 4),
          Text(guide.title, style: AppTypography.headlineLg),
          if (guide.summary != null && guide.summary!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(guide.summary!,
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ],
          if (guide.sourceAuthor != null && guide.sourceAuthor!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(guide.sourceAuthor!,
                style: AppTypography.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ],
          const SizedBox(height: AppSpacing.lg),
          for (final section in detail.sections) ...[
            _SectionBlock(section: section),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _SectionBlock extends StatelessWidget {
  final DietGuideSection section;

  const _SectionBlock({required this.section});

  @override
  Widget build(BuildContext context) {
    final heading = section.heading;
    final body = section.bodyText;
    final hasBody = body != null && body.isNotEmpty;
    if ((heading == null || heading.isEmpty) &&
        !hasBody &&
        section.lists.isEmpty &&
        section.tables.isEmpty) {
      return const SizedBox.shrink();
    }

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading != null && heading.isNotEmpty) ...[
            Text(heading, style: AppTypography.headlineSm),
            const SizedBox(height: AppSpacing.xs),
          ],
          if (hasBody) ...[
            Text(body,
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.xs),
          ],
          for (final list in section.lists) ...[
            for (final item in list)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6, right: 8),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(item,
                          style: AppTypography.bodySm.copyWith(
                              color: AppColors.onSurfaceVariant)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
          ],
          for (final table in section.tables) ...[
            _GuideTable(rows: table),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

/// Renders one source table. Column order comes from the first row's keys,
/// which is the order the backend serialized them in.
class _GuideTable extends StatelessWidget {
  final List<Map<String, String>> rows;

  const _GuideTable({required this.rows});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final headers = rows.first.keys.toList();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingTextStyle:
            AppTypography.labelCaps.copyWith(color: AppColors.onSurface),
        dataTextStyle: AppTypography.bodySm
            .copyWith(color: AppColors.onSurfaceVariant),
        columns: [
          for (final header in headers)
            DataColumn(label: Text(header.toUpperCase())),
        ],
        rows: [
          for (final row in rows)
            DataRow(
              cells: [
                for (final header in headers)
                  DataCell(Text(row[header] ?? '')),
              ],
            ),
        ],
      ),
    );
  }
}
