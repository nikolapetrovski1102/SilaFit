import '../../core/api/api_client.dart';
import 'onboarding_models.dart';

/// Talks to `api/profile` - the onboarding-collected gender/age/height/
/// weight/goal row, one per user (guest or registered).
class OnboardingRepository {
  final ApiClient _client;

  OnboardingRepository(this._client);

  Future<UserProfile> getProfile() => _client.get('/profile', UserProfile.fromJson);

  Future<UserProfile> upsertProfile({
    required String gender,
    required int ageYears,
    required double heightCm,
    required double weightKg,
    required String goal,
  }) =>
      _client.put(
        '/profile',
        UserProfile.fromJson,
        body: {
          'gender': gender,
          'ageYears': ageYears,
          'heightCm': heightCm,
          'weightKg': weightKg,
          'goal': goal,
        },
      );
}
