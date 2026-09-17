/// Mirrors `Silen.Common.Models.SplitModels.ExerciseModel`. Backs both the
/// split builder's exercise picker and the live-workout swap/add sheet.
class ExerciseSummary {
  final String exerciseId;
  final String name;
  final String muscleGroup;
  final String? equipmentType;
  final bool isCompound;
  final String? demoVideoUrl;

  /// Only set by the suggestion read (`/exercises/suggestions`): a higher score
  /// means a better fit for this user's equipment and experience. Null on plain
  /// search results, which is how the picker tells the two apart.
  final int? matchScore;

  /// Short justification shown beside a suggested exercise.
  final String? matchReason;

  const ExerciseSummary({
    required this.exerciseId,
    required this.name,
    required this.muscleGroup,
    this.equipmentType,
    required this.isCompound,
    this.demoVideoUrl,
    this.matchScore,
    this.matchReason,
  });

  factory ExerciseSummary.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return ExerciseSummary(
      exerciseId: map['exerciseId'] as String,
      name: map['name'] as String? ?? '',
      muscleGroup: map['muscleGroup'] as String? ?? '',
      equipmentType: map['equipmentType'] as String?,
      isCompound: map['isCompound'] as bool? ?? false,
      demoVideoUrl: map['demoVideoUrl'] as String?,
      matchScore: (map['matchScore'] as num?)?.toInt(),
      matchReason: map['matchReason'] as String?,
    );
  }
}
