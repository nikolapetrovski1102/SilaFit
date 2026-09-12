import '../../core/api/api_client.dart';
import 'auth_result.dart';

/// Talks to `api/auth/*`. Every method returns an [AuthResult] the caller
/// hands to `AuthController.applySession`.
class AuthRepository {
  final ApiClient _client;

  AuthRepository(this._client);

  Future<AuthResult> loginWithDevice(String deviceId) => _client.post(
        '/auth/device',
        AuthResult.fromJson,
        body: {'deviceId': deviceId},
      );

  Future<AuthResult> registerEmail({
    required String email,
    required String password,
    String? displayName,
  }) =>
      _client.post(
        '/auth/register/email',
        AuthResult.fromJson,
        body: {
          'email': email,
          'password': password,
          if (displayName != null && displayName.isNotEmpty)
            'displayName': displayName,
        },
      );

  Future<AuthResult> loginEmail(
          {required String email, required String password}) =>
      _client.post(
        '/auth/login/email',
        AuthResult.fromJson,
        body: {'email': email, 'password': password},
      );

  Future<AuthResult> loginGoogle(String idToken) => _client.post(
        '/auth/login/google',
        AuthResult.fromJson,
        body: {'idToken': idToken},
      );

  Future<AuthResult> loginApple(
          {required String identityToken, String? displayName}) =>
      _client.post(
        '/auth/login/apple',
        AuthResult.fromJson,
        body: {
          'identityToken': identityToken,
          if (displayName != null && displayName.isNotEmpty)
            'displayName': displayName,
        },
      );
}
