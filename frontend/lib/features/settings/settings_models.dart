/// Mirrors `Silen.Common.Models.UserSettingsModel` /
/// `UpdateUserSettingsRequest` - one model serves both read and write since
/// the two DTOs carry identical fields on the backend.
class UserSettings {
  final int targetWaterMl;
  final bool notificationsEnabled;
  final String notificationLocalTime;

  /// True once the user picked [notificationLocalTime] - the gym reminder then
  /// fires at exactly that time. False is "auto": it follows when they train.
  final bool notificationTimeIsUserSet;

  /// Read-only, server-computed: the time the auto reminder fires at, learned
  /// from recent workouts. Null until there's enough history (the 18:00
  /// default in [notificationLocalTime] applies) or when the time is user-set.
  final String? detectedNotificationLocalTime;

  final String timeZoneId;
  final String weightUnit;
  final String distanceUnit;
  final bool restTimerSoundEnabled;
  final String appearanceMode;
  final String avatarChoice;

  /// Whether the user agreed to share their data with the third-party AI
  /// provider. Read-only here - it's changed only through
  /// `SettingsRepository.setAiDataConsent`, never by a settings save.
  final bool aiDataConsent;

  const UserSettings({
    required this.targetWaterMl,
    required this.notificationsEnabled,
    required this.notificationLocalTime,
    this.notificationTimeIsUserSet = false,
    this.detectedNotificationLocalTime,
    required this.timeZoneId,
    required this.weightUnit,
    required this.distanceUnit,
    required this.restTimerSoundEnabled,
    required this.appearanceMode,
    required this.avatarChoice,
    this.aiDataConsent = false,
  });

  factory UserSettings.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return UserSettings(
      targetWaterMl: map['targetWaterMl'] as int,
      notificationsEnabled: map['notificationsEnabled'] as bool,
      notificationLocalTime:
          map['notificationLocalTime'] as String? ?? '18:00:00',
      notificationTimeIsUserSet:
          map['notificationTimeIsUserSet'] as bool? ?? false,
      detectedNotificationLocalTime:
          map['detectedNotificationLocalTime'] as String?,
      timeZoneId: map['timeZoneId'] as String? ?? 'UTC',
      weightUnit: map['weightUnit'] as String? ?? 'kg',
      distanceUnit: map['distanceUnit'] as String? ?? 'km',
      restTimerSoundEnabled: map['restTimerSoundEnabled'] as bool,
      appearanceMode: map['appearanceMode'] as String? ?? 'Device',
      avatarChoice: map['avatarChoice'] as String? ?? 'Male',
      aiDataConsent: map['aiDataConsent'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toUpdateJson() => {
        'targetWaterMl': targetWaterMl,
        'notificationsEnabled': notificationsEnabled,
        'notificationLocalTime': notificationLocalTime,
        'notificationTimeIsUserSet': notificationTimeIsUserSet,
        'timeZoneId': timeZoneId,
        'weightUnit': weightUnit,
        'distanceUnit': distanceUnit,
        'restTimerSoundEnabled': restTimerSoundEnabled,
        'appearanceMode': appearanceMode,
        'avatarChoice': avatarChoice,
      };

  UserSettings copyWith({
    int? targetWaterMl,
    bool? notificationsEnabled,
    String? notificationLocalTime,
    bool? notificationTimeIsUserSet,
    String? timeZoneId,
    String? weightUnit,
    String? distanceUnit,
    bool? restTimerSoundEnabled,
    String? appearanceMode,
    String? avatarChoice,
    bool? aiDataConsent,
  }) {
    return UserSettings(
      targetWaterMl: targetWaterMl ?? this.targetWaterMl,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      notificationLocalTime:
          notificationLocalTime ?? this.notificationLocalTime,
      notificationTimeIsUserSet:
          notificationTimeIsUserSet ?? this.notificationTimeIsUserSet,
      detectedNotificationLocalTime: detectedNotificationLocalTime,
      timeZoneId: timeZoneId ?? this.timeZoneId,
      weightUnit: weightUnit ?? this.weightUnit,
      distanceUnit: distanceUnit ?? this.distanceUnit,
      restTimerSoundEnabled:
          restTimerSoundEnabled ?? this.restTimerSoundEnabled,
      appearanceMode: appearanceMode ?? this.appearanceMode,
      avatarChoice: avatarChoice ?? this.avatarChoice,
      aiDataConsent: aiDataConsent ?? this.aiDataConsent,
    );
  }
}
