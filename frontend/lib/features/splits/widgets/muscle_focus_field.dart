import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import 'ink_field.dart';

/// Muscles a day can target. Finer than the catalogue's six groups on
/// purpose - `muscleGroupsInText` folds each of these back onto one of
/// them for exercise suggestions.
const kMuscleTargets = [
  'Chest',
  'Back',
  'Lats',
  'Traps',
  'Shoulders',
  'Biceps',
  'Triceps',
  'Forearms',
  'Quads',
  'Hamstrings',
  'Glutes',
  'Calves',
  'Core',
  'Obliques',
];

const kMaxMuscleTargets = 4;

/// "Chest", "Chest & Triceps", "Chest, Shoulders & Triceps".
String formatMuscleTargets(List<String> targets) {
  if (targets.length <= 1) return targets.join();
  return '${targets.sublist(0, targets.length - 1).join(', ')} & ${targets.last}';
}

/// The reverse of [formatMuscleTargets], for a stored focus label. Anything
/// that isn't a known muscle is kept as typed.
List<String> parseMuscleTargets(String? label) {
  if (label == null || label.trim().isEmpty) return [];
  final targets = <String>[];
  for (final raw in label.split(RegExp(r'\s*(?:,|&|\+|/|\band\b)\s*'))) {
    final token = raw.trim();
    if (token.isEmpty) continue;
    final known = kMuscleTargets
        .where((m) => m.toLowerCase() == token.toLowerCase())
        .firstOrNull;
    final target = known ?? _titleCase(token);
    if (!targets.contains(target)) targets.add(target);
  }
  return targets.take(kMaxMuscleTargets).toList();
}

String _titleCase(String text) => text
    .split(RegExp(r'\s+'))
    .map((w) =>
        w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

/// A borderless "focus" field: the chosen muscles sit in it as chips, and
/// while it has focus a dropdown under it lists muscles to add (up to
/// [kMaxMuscleTargets]) - filtered by whatever is typed.
class MuscleFocusField extends StatefulWidget {
  final List<String> targets;
  final ValueChanged<List<String>> onChanged;
  final FocusNode focusNode;

  const MuscleFocusField({
    super.key,
    required this.targets,
    required this.onChanged,
    required this.focusNode,
  });

  @override
  State<MuscleFocusField> createState() => _MuscleFocusFieldState();
}

class _MuscleFocusFieldState extends State<MuscleFocusField>
    with SingleTickerProviderStateMixin {
  final _query = TextEditingController();
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  late final AnimationController _underline = AnimationController(
    vsync: this,
    duration: kInkMorph,
    value: widget.focusNode.hasFocus ? 1 : 0,
  );
  double _width = 0;

  bool get _full => widget.targets.length >= kMaxMuscleTargets;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
    _query.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    _query.dispose();
    _underline.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  void _onFocusChanged() {
    if (widget.focusNode.hasFocus) {
      _underline.forward();
      _portal.show();
    } else {
      _underline.reverse();
      _portal.hide();
      _query.clear();
    }
    setState(() {});
  }

  List<String> get _options {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return kMuscleTargets;
    return kMuscleTargets.where((m) => m.toLowerCase().contains(q)).toList();
  }

  /// Typed text that isn't a listed muscle, offered as its own target.
  String? get _custom {
    final q = _query.text.trim();
    if (q.isEmpty) return null;
    final lower = q.toLowerCase();
    if (kMuscleTargets.any((m) => m.toLowerCase() == lower)) return null;
    if (widget.targets.any((t) => t.toLowerCase() == lower)) return null;
    return _titleCase(q);
  }

  void _toggle(String target) {
    final next = [...widget.targets];
    if (next.contains(target)) {
      next.remove(target);
    } else {
      if (_full) {
        HapticFeedback.heavyImpact();
        return;
      }
      next.add(target);
    }
    HapticFeedback.selectionClick();
    _query.clear();
    widget.onChanged(next);
  }

  void _submit() {
    final custom = _custom;
    final options = _options.where((m) => !widget.targets.contains(m)).toList();
    if (_query.text.trim().isEmpty) {
      widget.focusNode.unfocus();
    } else if (options.isNotEmpty) {
      _toggle(options.first);
    } else if (custom != null) {
      _toggle(custom);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.bodyLg;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: _buildDropdown,
        child: LayoutBuilder(builder: (context, constraints) {
          _width = constraints.maxWidth;
          // The chips count as part of the field too, so removing one while
          // typing doesn't blur it.
          return TextFieldTapRegion(
              child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.focusNode.requestFocus,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final target in widget.targets)
                      _TargetChip(
                        key: ValueKey(target),
                        label: target,
                        onRemove: () => _toggle(target),
                      ),
                    // Always mounted (even when full) so the focus node - and
                    // with it the dropdown - stays reachable.
                    IntrinsicWidth(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: _full ? 8 : 96),
                        child: TextField(
                          controller: _query,
                          focusNode: widget.focusNode,
                          style: style,
                          readOnly: _full,
                          showCursor: !_full,
                          cursorColor: AppColors.accent,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          decoration: inkDecoration(
                            widget.targets.isEmpty
                                ? 'Muscle focus'
                                : _full
                                    ? ''
                                    : 'Add',
                            style,
                          ),
                          onSubmitted: (_) => _submit(),
                          onEditingComplete: () {},
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                FocusUnderline(animation: _underline),
              ],
            ),
          ));
        }),
      ),
    );
  }

  Widget _buildDropdown(BuildContext context) {
    final options = _options;
    final custom = _custom;
    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, AppSpacing.xs),
      child: Align(
        alignment: Alignment.topLeft,
        // Taps in here count as inside the field, so they never blur it.
        child: TextFieldTapRegion(
          child: SizedBox(
            width: _width,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: kInkQuick,
              curve: Curves.easeOutCubic,
              builder: (_, t, child) => Opacity(
                opacity: t,
                child: Transform.translate(
                    offset: Offset(0, -8 * (1 - t)), child: child),
              ),
              child: Material(
                color: AppColors.surfaceContainerHigh,
                elevation: 12,
                shadowColor: Colors.black54,
                borderRadius: BorderRadius.circular(18),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 264),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          _full
                              ? 'THAT\'S $kMaxMuscleTargets - TAP ONE TO DROP IT'
                              : 'PICK UP TO $kMaxMuscleTargets  ·  ${widget.targets.length}/$kMaxMuscleTargets',
                          style: AppTypography.labelCaps
                              .copyWith(color: AppColors.onSurfaceVariant),
                        ),
                      ),
                      Flexible(
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 6),
                          // The overlay inherits the page's context - don't share its
                          // primary scroll controller.
                          primary: false,
                          shrinkWrap: true,
                          children: [
                            if (custom != null)
                              _OptionRow(
                                label: 'Add "$custom"',
                                selected: false,
                                enabled: !_full,
                                onTap: () => _toggle(custom),
                              ),
                            for (final muscle in options)
                              _OptionRow(
                                label: muscle,
                                selected: widget.targets.contains(muscle),
                                enabled:
                                    !_full || widget.targets.contains(muscle),
                                onTap: () => _toggle(muscle),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _OptionRow({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      canRequestFocus: false,
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        opacity: enabled ? 1 : 0.35,
        duration: kInkQuick,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: AppTypography.bodyMd.copyWith(
                        color: AppColors.highEmphasis,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400)),
              ),
              AnimatedScale(
                scale: selected ? 1 : 0,
                duration: kInkQuick,
                curve: Curves.easeOutBack,
                child: Icon(Icons.check_rounded,
                    size: 18, color: AppColors.accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const _TargetChip({super.key, required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1),
      duration: kInkQuick,
      curve: Curves.easeOutBack,
      builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: AppTypography.bodySm.copyWith(
                    color: AppColors.accent, fontWeight: FontWeight.w600)),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child:
                  Icon(Icons.close_rounded, size: 15, color: AppColors.accent),
            ),
          ],
        ),
      ),
    );
  }
}
