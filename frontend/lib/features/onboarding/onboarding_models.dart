/// Mirrors `Silen.Common.Models.UserProfileModel` - the row `GET api/profile`
/// returns once onboarding (or registration) has written one.
class UserProfile {
  final String? gender;
  final int? ageYears;
  final double? heightCm;
  final double? weightKg;
  final String? goal;
  final int? trainingDaysPerWeek;
  final int? sessionDurationMinutes;
  final String? trainingExperience;
  final String? equipmentAccess;
  final String? dailyActivityLevel;

  const UserProfile(
      {this.gender,
      this.ageYears,
      this.heightCm,
      this.weightKg,
      this.goal,
      this.trainingDaysPerWeek,
      this.sessionDurationMinutes,
      this.trainingExperience,
      this.equipmentAccess,
      this.dailyActivityLevel});

  factory UserProfile.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return UserProfile(
      gender: map['gender'] as String?,
      ageYears: map['ageYears'] as int?,
      heightCm: (map['heightCm'] as num?)?.toDouble(),
      weightKg: (map['weightKg'] as num?)?.toDouble(),
      goal: map['goal'] as String?,
      trainingDaysPerWeek: map['trainingDaysPerWeek'] as int?,
      sessionDurationMinutes: map['sessionDurationMinutes'] as int?,
      trainingExperience: map['trainingExperience'] as String?,
      equipmentAccess: map['equipmentAccess'] as String?,
      dailyActivityLevel: map['dailyActivityLevel'] as String?,
    );
  }

  /// True once every onboarding question has an answer on file - used to
  /// let `register_screen.dart` skip re-asking them.
  bool get isComplete =>
      gender != null &&
      ageYears != null &&
      heightCm != null &&
      weightKg != null &&
      goal != null &&
      trainingDaysPerWeek != null &&
      sessionDurationMinutes != null &&
      trainingExperience != null &&
      equipmentAccess != null &&
      dailyActivityLevel != null;
}
