import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_exception.dart';
import '../../core/platform/device_timezone.dart';
import '../notifications/notifications_repository.dart';
import '../notifications/push_messaging_service.dart';
import 'onboarding_repository.dart';
import 'onboarding_models.dart';

/// How long a tap on an answer row waits before auto-advancing to the next
/// step - long enough to see the row's own selected-state animation land,
/// short enough that it still reads as "one tap, not two".
const _autoAdvanceDelay = Duration(milliseconds: 260);

/// The screens of the flow in display order. `intro1`/`intro2` are the
/// carousel slides; nine profile questions precede the closing notification
/// prompt.
enum OnboardingStep {
  intro1,
  intro2,
  gender,
  age,
  height,
  weight,
  goal,
  trainingDays,
  trainingExperience,
  equipmentAccess,
  dailyActivity,
  notifications,
}

const _questionSteps = [
  OnboardingStep.gender,
  OnboardingStep.age,
  OnboardingStep.height,
  OnboardingStep.weight,
  OnboardingStep.goal,
  OnboardingStep.trainingDays,
  OnboardingStep.trainingExperience,
  OnboardingStep.equipmentAccess,
  OnboardingStep.dailyActivity,
  OnboardingStep.notifications,
];

/// Holds the in-progress answers locally for the whole flow and only ever
/// makes one `PUT api/profile` call, at the very end - not individual
/// per-step calls.
class OnboardingController extends ChangeNotifier {
  final OnboardingRepository _repository;
  final NotificationsRepository _notificationsRepository;
  final PushMessagingService? _pushMessaging;

  final bool autoAdvanceEnabled;
  OnboardingController(this._repository, this._notificationsRepository,
      {this.autoAdvanceEnabled = true,
      UserProfile? initialProfile,
      PushMessagingService? pushMessaging})
      : _pushMessaging = pushMessaging {
    if (initialProfile != null) {
      gender = initialProfile.gender;
      ageYears = initialProfile.ageYears ?? ageYears;
      heightCm = initialProfile.heightCm?.round() ?? heightCm;
      weightKg = initialProfile.weightKg?.round() ?? weightKg;
      goal = initialProfile.goal;
      trainingDaysPerWeek = initialProfile.trainingDaysPerWeek;
      sessionDurationMinutes =
          initialProfile.sessionDurationMinutes ?? sessionDurationMinutes;
      trainingExperience = initialProfile.trainingExperience;
      equipmentAccess = initialProfile.equipmentAccess;
      dailyActivityLevel = initialProfile.dailyActivityLevel;
    }
  }

  int _stepIndex = 0;
  OnboardingStep get step => OnboardingStep.values[_stepIndex];
  int get stepIndex => _stepIndex;
  static int get stepCount => OnboardingStep.values.length;

  bool _disposed = false;

  // 1 when the last step change was forward (Continue/auto-advance), -1
  // when it was backward (the back arrow) - the step transition's slide
  // direction reads this to push in from the right or the left accordingly.
  int _lastDirection = 1;
  int get lastDirection => _lastDirection;

  /// 1-based position within the question/notification steps, used by the
  /// compact assessment count badge - null on the two intro slides.
  int? get questionProgressStep {
    final index = _questionSteps.indexOf(step);
    return index == -1 ? null : index + 1;
  }

  int get questionStepCount => _questionSteps.length;

  String? gender;
  int ageYears = 18;
  int heightCm = 178;
  String heightUnit = 'cm'; // 'cm' | 'ft' - display only, storage stays cm.
  int weightKg = 76;
  String weightUnit = 'kg'; // 'kg' | 'lb' - display only, storage stays kg.
  String? goal;
  int? trainingDaysPerWeek;
  // Session duration still improves recommendations, but it is too granular
  // for first-run onboarding. Use a neutral default and let users tune it
  // later without spending an entire assessment screen on it.
  int? sessionDurationMinutes = 45;
  String? trainingExperience;
  String? equipmentAccess;
  String? dailyActivityLevel;

  bool _isSubmitting = false;
  String? _lastError;
  bool get isSubmitting => _isSubmitting;
  String? get lastError => _lastError;

  bool get canContinue {
    switch (step) {
      case OnboardingStep.gender:
        return gender != null;
      case OnboardingStep.goal:
        return goal != null;
      case OnboardingStep.trainingDays:
        return trainingDaysPerWeek != null;
      case OnboardingStep.trainingExperience:
        return trainingExperience != null;
      case OnboardingStep.equipmentAccess:
        return equipmentAccess != null;
      case OnboardingStep.dailyActivity:
        return dailyActivityLevel != null;
      default:
        return true;
    }
  }

  void goNext() {
    if (_stepIndex < OnboardingStep.values.length - 1) {
      _stepIndex++;
      _lastDirection = 1;
      HapticFeedback.lightImpact();
      notifyListeners();
    }
  }

  void goBack() {
    if (_stepIndex > 0) {
      _stepIndex--;
      _lastDirection = -1;
      HapticFeedback.selectionClick();
      notifyListeners();
    }
  }

  void setTrainingDaysPerWeek(int value) {
    trainingDaysPerWeek = value;
    notifyListeners();
    _autoAdvance();
  }

  void setSessionDurationMinutes(int value) {
    sessionDurationMinutes = value;
    notifyListeners();
    _autoAdvance();
  }

  /// [autoAdvance] is false for the drag-to-adjust arc slider: a drag
  /// gesture already implies deliberate intent, so (unlike the tappable
  /// answer rows) it waits for an explicit Continue tap instead of
  /// advancing itself the moment a drag settles.
  void setTrainingExperience(String value, {bool autoAdvance = true}) {
    trainingExperience = value;
    notifyListeners();
    if (autoAdvance) _autoAdvance();
  }

  void setEquipmentAccess(String value) {
    equipmentAccess = value;
    notifyListeners();
    _autoAdvance();
  }

  void setDailyActivityLevel(String value) {
    dailyActivityLevel = value;
    notifyListeners();
    _autoAdvance();
  }

  void selectGender(String value) {
    gender = value;
    notifyListeners();
    _autoAdvance();
  }

  void selectGoal(String value) {
    goal = value;
    notifyListeners();
    _autoAdvance();
  }

  /// Answer rows (gender/goal) advance on their own shortly after a tap,
  /// instead of making the user also hit Continue - the Continue button
  /// stays as a fallback/no-op-safe affordance rather than the only way
  /// forward. Guards against the step having already moved on by the time
  /// the delay elapses (a manual Continue tap mid-delay, or the answer
  /// changing again) by only advancing if we're still on the step this
  /// particular selection was made on.
  void _autoAdvance() {
    if (!autoAdvanceEnabled) return;
    final steppedFrom = _stepIndex;
    Future.delayed(_autoAdvanceDelay, () {
      if (_disposed || _stepIndex != steppedFrom || !canContinue) return;
      goNext();
    });
  }

  void setAge(int value) {
    ageYears = value;
    notifyListeners();
  }

  void setHeightCm(int value) {
    heightCm = value;
    notifyListeners();
  }

  void setHeightUnit(String unit) {
    heightUnit = unit;
    notifyListeners();
  }

  void setWeightKg(int value) {
    weightKg = value;
    notifyListeners();
  }

  void setWeightUnit(String unit) {
    weightUnit = unit;
    notifyListeners();
  }

  /// Persists the collected answers. Returns true on success; the caller
  /// proceeds into the app only after the profile has been saved.
  Future<bool> submit() async {
    if (gender == null ||
        goal == null ||
        trainingDaysPerWeek == null ||
        sessionDurationMinutes == null ||
        trainingExperience == null ||
        equipmentAccess == null ||
        dailyActivityLevel == null) {
      return false;
    }
    _isSubmitting = true;
    _lastError = null;
    notifyListeners();
    try {
      await _repository.upsertProfile(
        gender: gender!,
        ageYears: ageYears,
        heightCm: heightCm.toDouble(),
        weightKg: weightKg.toDouble(),
        goal: goal!,
        trainingDaysPerWeek: trainingDaysPerWeek,
        sessionDurationMinutes: sessionDurationMinutes,
        trainingExperience: trainingExperience,
        equipmentAccess: equipmentAccess,
        dailyActivityLevel: dailyActivityLevel,
      );
      _isSubmitting = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _isSubmitting = false;
      _lastError = e.userMessage;
      notifyListeners();
      return false;
    } catch (_) {
      _isSubmitting = false;
      _lastError = ApiException.genericMessage;
      notifyListeners();
      return false;
    }
  }

  /// Persists the notification choice made on the closing screen together with
  /// the device's timezone, so reminders are scheduled on the user's clock from
  /// day one rather than the server's. When the user allowed notifications this
  /// also fetches the FCM registration token and stores it, so the server has a
  /// delivery address; denial (or an unconfigured Firebase app) simply stores
  /// the timezone/opt-in with no token, exactly as before.
  ///
  /// Best-effort: onboarding entry must never depend on any of this succeeding.
  Future<void> submitNotificationOptIn(bool enabled) async {
    try {
      final token = enabled ? await _pushMessaging?.requestToken() : null;
      await _notificationsRepository.registerDeviceToken(
        token: token,
        platform: devicePlatform(),
        timeZoneId: deviceTimeZoneId(),
        notificationsEnabled: enabled,
      );
    } catch (_) {
      // Intentionally swallowed - see the doc comment above.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
