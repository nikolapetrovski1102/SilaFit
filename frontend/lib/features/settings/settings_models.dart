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
  final String avatarChoice;

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
    required this.avatarChoice,
  });

  factory UserSettings.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return UserSettings(
      targetWaterMl: map['targetWaterMl'] as int,
      notificationsEnabled: map['notificationsEnabled'] as bool,
      notificationLocalTime:
          map['notificationLocalTime'] as String? ?? '08:00:00',
      timeZoneId: map['timeZoneId'] as String? ?? 'UTC',
      weightUnit: map['weightUnit'] as String? ?? 'kg',
      distanceUnit: map['distanceUnit'] as String? ?? 'km',
      restTimerSoundEnabled: map['restTimerSoundEnabled'] as bool,
      barbellStandardKg: (map['barbellStandardKg'] as num).toDouble(),
      appearanceMode: map['appearanceMode'] as String? ?? 'Device',
      avatarChoice: map['avatarChoice'] as String? ?? 'Male',
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
        'avatarChoice': avatarChoice,
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
    String? avatarChoice,
  }) {
    return UserSettings(
      targetWaterMl: targetWaterMl ?? this.targetWaterMl,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notificationLocalTime:
          notificationLocalTime ?? this.notificationLocalTime,
      timeZoneId: timeZoneId ?? this.timeZoneId,
      weightUnit: weightUnit ?? this.weightUnit,
      distanceUnit: distanceUnit ?? this.distanceUnit,
      restTimerSoundEnabled:
          restTimerSoundEnabled ?? this.restTimerSoundEnabled,
      barbellStandardKg: barbellStandardKg ?? this.barbellStandardKg,
      appearanceMode: appearanceMode ?? this.appearanceMode,
      avatarChoice: avatarChoice ?? this.avatarChoice,
    );
  }
}

/// The fixed set of barbell standards the picker offers - a static client
/// map, not a duplicated DB column, per the plan's Phase 9 note.
const kBarbellStandardOptionsKg = [20.0, 15.0, 10.0];
