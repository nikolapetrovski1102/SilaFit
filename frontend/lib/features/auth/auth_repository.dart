import '../../core/api/api_client.dart';
import 'auth_result.dart';
import 'email_verification_start.dart';

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

  /// Step 1 of email registration - stashes the pending registration and
  /// emails a 6-digit code. No account exists until [verifyEmailRegistration]
  /// confirms that code.
  Future<EmailVerificationStart> startEmailRegistration({
    required String email,
    required String password,
    String? displayName,
  }) =>
      _client.post(
        '/auth/register/email/start',
        EmailVerificationStart.fromJson,
        body: {
          'email': email,
          'password': password,
          if (displayName != null && displayName.isNotEmpty)
            'displayName': displayName,
        },
      );

  /// Step 2 - confirms the emailed code and only then creates the account.
  Future<AuthResult> verifyEmailRegistration({
    required String pendingId,
    required String code,
  }) =>
      _client.post(
        '/auth/register/email/verify',
        AuthResult.fromJson,
        body: {'pendingId': pendingId, 'code': code},
      );

  /// Re-sends a fresh code for an already-started pending registration.
  Future<EmailVerificationStart> resendEmailVerification(String pendingId) =>
      _client.post(
        '/auth/register/email/resend',
        EmailVerificationStart.fromJson,
        body: {'pendingId': pendingId},
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
          {required String identityToken,
          String? displayName,
          String? authorizationCode}) =>
      _client.post(
        '/auth/login/apple',
        AuthResult.fromJson,
        body: {
          'identityToken': identityToken,
          if (displayName != null && displayName.isNotEmpty)
            'displayName': displayName,
          // Exchanged server-side for a refresh token, so deleting the
          // account can revoke Sign in with Apple (App Review 5.1.1(v)).
          if (authorizationCode != null && authorizationCode.isNotEmpty)
            'authorizationCode': authorizationCode,
        },
      );
}
