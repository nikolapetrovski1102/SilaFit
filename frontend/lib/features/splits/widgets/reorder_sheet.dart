import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/silen_button.dart';

/// Generic drag-and-drop reorder sheet shared by the split builder's day
/// list ([SplitBuilderScreen]) and a day's exercise list
/// ([SplitDayEditorScreen]) - press and drag a row's trailing handle to
/// move it, "Done" to confirm. Operates on a local copy of [items] so
/// nothing changes until confirmed; returns the reordered list, or null if
/// the sheet was dismissed without confirming.
Future<List<T>?> showReorderSheet<T>(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<T> items,
  required String Function(T item) idOf,
  required String Function(T item) titleOf,
  String? Function(T item)? subtitleOf,
}) {
  return showModalBottomSheet<List<T>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (_) => _ReorderSheet<T>(
      title: title,
      subtitle: subtitle,
      items: items,
      idOf: idOf,
      titleOf: titleOf,
      subtitleOf: subtitleOf,
    ),
  );
}

class _ReorderSheet<T> extends StatefulWidget {
  final String title;
  final String subtitle;
  final List<T> items;
  final String Function(T item) idOf;
  final String Function(T item) titleOf;
  final String? Function(T item)? subtitleOf;

  const _ReorderSheet({
    required this.title,
    required this.subtitle,
    required this.items,
    required this.idOf,
    required this.titleOf,
    this.subtitleOf,
  });

  @override
  State<_ReorderSheet<T>> createState() => _ReorderSheetState<T>();
}

class _ReorderSheetState<T> extends State<_ReorderSheet<T>> {
  late final List<T> _order = List<T>.from(widget.items);

  void _onReorder(int oldIndex, int newIndex) {
    setState(() => _order.insert(newIndex, _order.removeAt(oldIndex)));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            left: AppSpacing.marginMobile,
            right: AppSpacing.marginMobile,
            top: AppSpacing.marginMobile,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: AppTypography.headlineMd),
            const SizedBox(height: AppSpacing.xxs),
            Text(widget.subtitle,
                style: AppTypography.bodyMd
                    .copyWith(color: AppColors.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _order.length,
                onReorderItem: _onReorder,
                itemBuilder: (context, index) {
                  final item = _order[index];
                  return _ReorderTile(
                    key: ValueKey(widget.idOf(item)),
                    index: index,
                    title: widget.titleOf(item),
                    subtitle: widget.subtitleOf?.call(item),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            PrimaryPillButton(
              label: 'Done',
              onPressed: () => Navigator.of(context).pop(_order),
            ),
          ],
        ),
      ),
    );
  }
}

/// One draggable row: position number, title/subtitle, and a trailing drag
/// handle that's the only part of the row wired to start a drag - so
/// nothing fires on an accidental tap elsewhere on the tile.
class _ReorderTile extends StatelessWidget {
  final int index;
  final String title;
  final String? subtitle;

  const _ReorderTile({
    super.key,
    required this.index,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xxs),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.inset),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('${index + 1}',
                style: AppTypography.labelCaps
                    .copyWith(color: AppColors.onSurfaceVariant)),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: subtitle == null
                ? Text(title, style: AppTypography.bodyMd)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.bodyMd),
                      Text(subtitle!,
                          style: AppTypography.labelSm
                              .copyWith(color: AppColors.onSurfaceVariant)),
                    ],
                  ),
          ),
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxs),
              child: Icon(Icons.drag_handle_rounded,
                  color: AppColors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
