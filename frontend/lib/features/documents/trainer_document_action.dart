import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import 'secure_document_screen.dart';
import 'trainer_document_models.dart';
import 'trainer_documents_repository.dart';

/// App-bar action on a split / diet plan: a document icon when the trainer has
/// handed this user a PDF for it, nothing otherwise. One document opens
/// straight away; several open a short picker first.
class TrainerDocumentAction extends StatefulWidget {
  final TrainerDocumentKind kind;
  final String targetId;

  const TrainerDocumentAction(
      {super.key, required this.kind, required this.targetId});

  @override
  State<TrainerDocumentAction> createState() => _TrainerDocumentActionState();
}

class _TrainerDocumentActionState extends State<TrainerDocumentAction> {
  List<TrainerDocument> _documents = const [];
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TrainerDocumentAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetId != widget.targetId) _load();
  }

  Future<void> _load() async {
    try {
      final documents = await context
          .read<TrainerDocumentsRepository>()
          .getFor(widget.kind, widget.targetId);
      if (mounted) setState(() => _documents = documents);
    } catch (_) {
      // No icon is the right failure mode: offline, or nothing shared.
      if (mounted) setState(() => _documents = const []);
    }
  }

  Future<void> _onPressed() async {
    if (_documents.length == 1) return _open(_documents.first);
    final picked = await showModalBottomSheet<TrainerDocument>(
      context: context,
      backgroundColor: AppColors.surfaceContainer,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile, 0,
                  AppSpacing.marginMobile, AppSpacing.xs),
              child: Text('From your trainer', style: AppTypography.headlineSm),
            ),
            for (final document in _documents)
              ListTile(
                leading:
                    Icon(Icons.description_outlined, color: AppColors.accent),
                title: Text(document.title, style: AppTypography.bodyMd),
                subtitle: document.trainerUsername == null
                    ? null
                    : Text(document.trainerUsername!,
                        style: AppTypography.labelSm
                            .copyWith(color: AppColors.onSurfaceVariant)),
                onTap: () => Navigator.of(sheetContext).pop(document),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (picked != null) await _open(picked);
  }

  Future<void> _open(TrainerDocument document) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final url = await context
          .read<TrainerDocumentsRepository>()
          .open(document.grantId);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SecureDocumentScreen(
          title: document.title,
          viewerUrl: url,
          trainerName: document.trainerUsername,
        ),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.userMessage)));
      // A revoked document drops out of the list.
      if (e.statusCode == 404) _load();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_documents.isEmpty) return const SizedBox.shrink();
    return IconButton(
      tooltip: _documents.length == 1
          ? _documents.first.title
          : 'Documents from your trainer',
      onPressed: _opening ? null : _onPressed,
      icon: _opening
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Badge(
              isLabelVisible: _documents.length > 1,
              label: Text('${_documents.length}'),
              child: const Icon(Icons.description_outlined),
            ),
    );
  }
}
