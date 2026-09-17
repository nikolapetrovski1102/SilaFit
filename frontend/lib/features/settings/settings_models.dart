/// Mirrors `Silen.Common.Models.UserSettingsModel` /
/// `UpdateUserSettingsRequest` - one model serves both read and write since
/// the two DTOs carry identical fields on the backend.
class UserSettings {
  final int targetWaterMl;
  final bool notificationsEnabled;
  final String notificationLocalTime;
  final String timeZoneId;
  final String weightUnit;
  final String distanceUnit;
  final bool restTimerSoundEnabled;
  final double barbellStandardKg;
  final String appearanceMode;

  /// Whether the Sunday batch job considers this user for an AI-generated
  /// weekly split + diet plan at all (still gated server-side on an active
  /// Advanced subscription + minimum logged activity).
  final bool receiveWeeklyAiPlans;

  /// Whether each newly generated split/diet plan becomes this user's active
  /// one automatically, or just lands in "My Splits"/"My Diet Plans" for them
  /// to activate themselves.
  final bool autoActivateAiPlans;

  const UserSettings({
    required this.targetWaterMl,
    required this.notificationsEnabled,
    required this.notificationLocalTime,
    required this.timeZoneId,
    required this.weightUnit,
    required this.distanceUnit,
    required this.restTimerSoundEnabled,
    required this.barbellStandardKg,
    required this.appearanceMode,
    required this.receiveWeeklyAiPlans,
    required this.autoActivateAiPlans,
  });

  factory UserSettings.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return UserSettings(
      targetWaterMl: map['targetWaterMl'] as int,
      notificationsEnabled: map['notificationsEnabled'] as bool,
      notificationLocalTime: map['notificationLocalTime'] as String? ?? '08:00:00',
      timeZoneId: map['timeZoneId'] as String? ?? 'UTC',
      weightUnit: map['weightUnit'] as String? ?? 'kg',
      distanceUnit: map['distanceUnit'] as String? ?? 'km',
      restTimerSoundEnabled: map['restTimerSoundEnabled'] as bool,
      barbellStandardKg: (map['barbellStandardKg'] as num).toDouble(),
      appearanceMode: map['appearanceMode'] as String? ?? 'Device',
      receiveWeeklyAiPlans: map['receiveWeeklyAiPlans'] as bool? ?? false,
      autoActivateAiPlans: map['autoActivateAiPlans'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toUpdateJson() => {
        'targetWaterMl': targetWaterMl,
        'notificationsEnabled': notificationsEnabled,
        'notificationLocalTime': notificationLocalTime,
        'timeZoneId': timeZoneId,
        'weightUnit': weightUnit,
        'distanceUnit': distanceUnit,
        'restTimerSoundEnabled': restTimerSoundEnabled,
        'barbellStandardKg': barbellStandardKg,
        'appearanceMode': appearanceMode,
        'receiveWeeklyAiPlans': receiveWeeklyAiPlans,
        'autoActivateAiPlans': autoActivateAiPlans,
      };

  UserSettings copyWith({
    int? targetWaterMl,
    bool? notificationsEnabled,
    String? notificationLocalTime,
    String? timeZoneId,
    String? weightUnit,
    String? distanceUnit,
    bool? restTimerSoundEnabled,
    double? barbellStandardKg,
    String? appearanceMode,
    bool? receiveWeeklyAiPlans,
    bool? autoActivateAiPlans,
  }) {
    return UserSettings(
      targetWaterMl: targetWaterMl ?? this.targetWaterMl,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notificationLocalTime: notificationLocalTime ?? this.notificationLocalTime,
      timeZoneId: timeZoneId ?? this.timeZoneId,
      weightUnit: weightUnit ?? this.weightUnit,
      distanceUnit: distanceUnit ?? this.distanceUnit,
      restTimerSoundEnabled: restTimerSoundEnabled ?? this.restTimerSoundEnabled,
      barbellStandardKg: barbellStandardKg ?? this.barbellStandardKg,
      appearanceMode: appearanceMode ?? this.appearanceMode,
      receiveWeeklyAiPlans: receiveWeeklyAiPlans ?? this.receiveWeeklyAiPlans,
      autoActivateAiPlans: autoActivateAiPlans ?? this.autoActivateAiPlans,
    );
  }
}

/// The fixed set of barbell standards the picker offers - a static client
/// map, not a duplicated DB column, per the plan's Phase 9 note.
const kBarbellStandardOptionsKg = [20.0, 15.0, 10.0];
