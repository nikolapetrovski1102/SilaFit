import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/section_eyebrow.dart';
import '../../core/widgets/silen_button.dart';
import 'exercise_focus.dart';
import 'exercises_models.dart';
import 'exercises_repository.dart';

/// Equipment a custom exercise can use - the catalogue's own values plus Band
/// and Other. Must match `ExercisesService.EquipmentTypes` on the server.
const List<String> kExerciseEquipmentTypes = [
  'Barbell',
  'Dumbbell',
  'Machine',
  'Cable',
  'Bodyweight',
  'Kettlebell',
  'Band',
  'Other',
];

/// Opens the "new exercise" form, for when the picker's search and its "did
/// you mean" picks both miss. Every detail is required - name, the muscle
/// group it trains, its equipment and whether it's compound - since those
/// drive the split builder's grouping, the suggestion scorer and progress.
/// Returns the created exercise (or the existing one with that name), or null
/// if dismissed.
Future<ExerciseSummary?> showCreateExerciseSheet(BuildContext context,
    {String initialName = ''}) {
  return showModalBottomSheet<ExerciseSummary>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceContainer,
    shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.92,
      child: Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: _CreateExerciseForm(initialName: initialName),
      ),
    ),
  );
}

class _CreateExerciseForm extends StatefulWidget {
  final String initialName;

  const _CreateExerciseForm({required this.initialName});

  @override
  State<_CreateExerciseForm> createState() => _CreateExerciseFormState();
}

class _CreateExerciseFormState extends State<_CreateExerciseForm> {
  late final _nameController =
      TextEditingController(text: _titleCase(widget.initialName.trim()));
  String? _muscleGroup;
  String? _equipment;
  bool? _isCompound;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // A head start from the typed name ("cable crunch" -> core); still shown
    // as a normal selection the user can change.
    final groups = muscleGroupsInText(widget.initialName);
    if (groups.isNotEmpty) _muscleGroup = groups.first;
    _equipment = _equipmentInText(widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final String? missing = name.length < 2
        ? 'Give the exercise a name.'
        : _muscleGroup == null
            ? 'Pick the muscle group it trains.'
            : _equipment == null
                ? 'Pick the equipment it uses.'
                : _isCompound == null
                    ? 'Say whether it\'s compound or isolation.'
                    : null;
    if (missing != null) {
      setState(() => _error = missing);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final exercise = await context.read<ExercisesRepository>().createCustom(
            name: name,
            muscleGroup: _muscleGroup!,
            equipmentType: _equipment!,
            isCompound: _isCompound!,
          );
      if (!mounted) return;
      Navigator.of(context).pop(exercise);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    } catch (_) {
      if (mounted) setState(() => _error = ApiException.genericMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
                AppSpacing.md, AppSpacing.marginMobile, AppSpacing.md),
            children: [
              Text('NEW EXERCISE',
                  style: AppTypography.labelCaps
                      .copyWith(color: AppColors.accent)),
              const SizedBox(height: 4),
              Text('Add it to your library', style: AppTypography.headlineSm),
              const SizedBox(height: 2),
              Text('Only you will see it. Fill in every detail so it slots '
                  'into your splits and progress like any other exercise.',
                  style: AppTypography.labelSm
                      .copyWith(color: AppColors.onSurfaceVariant)),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                maxLength: 150,
                style: AppTypography.bodyMd,
                decoration: const InputDecoration(
                    labelText: 'Exercise name', counterText: ''),
              ),
              const SizedBox(height: AppSpacing.lg),
              _ChoiceGroup(
                label: 'Muscle group',
                options: kExerciseMuscleGroups,
                selected: _muscleGroup,
                onSelected: (v) => setState(() => _muscleGroup = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              _ChoiceGroup(
                label: 'Equipment',
                options: kExerciseEquipmentTypes,
                selected: _equipment,
                onSelected: (v) => setState(() => _equipment = v),
              ),
              const SizedBox(height: AppSpacing.lg),
              _ChoiceGroup(
                label: 'Movement type',
                hint: 'Compound works several joints (squat, row); '
                    'isolation works one (curl, raise).',
                options: const ['Compound', 'Isolation'],
                selected: switch (_isCompound) {
                  true => 'Compound',
                  false => 'Isolation',
                  null => null,
                },
                onSelected: (v) =>
                    setState(() => _isCompound = v == 'Compound'),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(_error!,
                    style:
                        AppTypography.bodySm.copyWith(color: AppColors.error)),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.marginMobile,
              AppSpacing.sm, AppSpacing.marginMobile, AppSpacing.md),
          child: PrimaryPillButton(
            label: 'Save exercise',
            icon: Icons.check_rounded,
            isLoading: _saving,
            onPressed: _save,
          ),
        ),
      ],
    );
  }
}

/// A required single choice shown as a row of pills under a caps label.
class _ChoiceGroup extends StatelessWidget {
  final String label;
  final String? hint;
  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  const _ChoiceGroup({
    required this.label,
    this.hint,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionEyebrow(label),
        if (hint != null) ...[
          const SizedBox(height: 2),
          Text(hint!,
              style: AppTypography.labelSm
                  .copyWith(color: AppColors.onSurfaceVariant)),
        ],
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final option in options)
              PillChip(
                label: option,
                selected: option == selected,
                onTap: () => onSelected(option),
              ),
          ],
        ),
      ],
    );
  }
}

/// The equipment named in [text], if any ("db curl" -> Dumbbell).
String? _equipmentInText(String text) {
  final words = text.toLowerCase().split(RegExp(r'[^a-z]+'));
  const aliases = {
    'barbell': 'Barbell',
    'bb': 'Barbell',
    'dumbbell': 'Dumbbell',
    'dumbbells': 'Dumbbell',
    'db': 'Dumbbell',
    'machine': 'Machine',
    'cable': 'Cable',
    'cables': 'Cable',
    'bodyweight': 'Bodyweight',
    'kettlebell': 'Kettlebell',
    'kb': 'Kettlebell',
    'band': 'Band',
    'banded': 'Band',
  };
  for (final word in words) {
    final match = aliases[word];
    if (match != null) return match;
  }
  return null;
}

/// "cable crunch" -> "Cable Crunch", leaving words the user already cased.
String _titleCase(String text) => text
    .split(' ')
    .map((w) => w.isEmpty || w != w.toLowerCase()
        ? w
        : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');
