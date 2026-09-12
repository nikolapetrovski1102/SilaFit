import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_exception.dart';
import 'onboarding_repository.dart';

/// How long a tap on an answer row waits before auto-advancing to the next
/// step - long enough to see the row's own selected-state animation land,
/// short enough that it still reads as "one tap, not two".
const _autoAdvanceDelay = Duration(milliseconds: 260);

/// The 8 screens of the flow in display order. `intro1`/`intro2` are the
/// carousel slides; `gender` through `goal` are the 5 answer questions
/// (progress bar steps 1-5 of 6); `notifications` is the closing OS-prompt
/// screen (progress step 6 of 6).
enum OnboardingStep {
  intro1,
  intro2,
  gender,
  age,
  height,
  weight,
  goal,
  notifications,
}

const _questionSteps = [
  OnboardingStep.gender,
  OnboardingStep.age,
  OnboardingStep.height,
  OnboardingStep.weight,
  OnboardingStep.goal,
  OnboardingStep.notifications,
];

/// Holds the in-progress answers locally for the whole flow and only ever
/// makes one `PUT api/profile` call, at the very end - not five chatty
/// per-step calls.
class OnboardingController extends ChangeNotifier {
  final OnboardingRepository _repository;

  OnboardingController(this._repository);

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

  /// 1-based position within the 6 question/notification steps, for the
  /// thin progress-fill bar - null on the two intro slides.
  int? get questionProgressStep {
    final index = _questionSteps.indexOf(step);
    return index == -1 ? null : index + 1;
  }

  int get questionStepCount => _questionSteps.length;

  String? gender;
  int ageYears = 27;
  int heightCm = 178;
  String heightUnit = 'cm'; // 'cm' | 'ft' - display only, storage stays cm.
  int weightKg = 76;
  String weightUnit = 'kg'; // 'kg' | 'lb' - display only, storage stays kg.
  String? goal;

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
  /// (the notification-permission screen's CTA/skip) proceeds into the app
  /// either way after this resolves - onboarding never blocks entry on the
  /// network call succeeding.
  Future<bool> submit() async {
    if (gender == null || goal == null) return false;
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

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
