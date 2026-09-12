import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/api/api_config.dart';
import '../../core/api/api_exception.dart';
import '../../core/session/session_store.dart';
import 'auth_repository.dart';
import 'auth_result.dart';
import 'email_verification_start.dart';

/// App-wide auth state. Holds the current [SilenSession] (via [SessionStore])
/// and is the one place every login/register/link flow goes through, so the
/// "device-id first, account only when a gated feature needs it" rule lives
/// in exactly one spot.
class AuthController extends ChangeNotifier {
  final AuthRepository _repository;
  final SessionStore _sessionStore;
  // `serverClientId` (the Web OAuth client) is what actually makes
  // `account.authentication.idToken` populate - without it Google only
  // returns an accessToken, never an idToken, on every platform. `clientId`
  // is iOS-only and ignored elsewhere. Both are placeholders until real
  // Google Cloud credentials are created - see frontend/env/README.md.
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    clientId: ApiConfig.googleIosClientId,
    serverClientId: ApiConfig.googleWebClientId,
  );

  bool _isBootstrapping = true;
  bool _isBusy = false;
  String? _lastError;
  EmailVerificationStart? _pendingVerification;

  AuthController(this._repository, this._sessionStore);

  SilenSession? get session => _sessionStore.current;
  bool get isRegistered => _sessionStore.isRegistered;
  bool get isBootstrapping => _isBootstrapping;
  bool get isBusy => _isBusy;
  String? get lastError => _lastError;

  /// Set once [startEmailRegistration] (or [resendEmailVerification])
  /// succeeds; the register wizard's verify step reads it for the code's
  /// expiry countdown and clears it (via [cancelEmailVerification]) if the
  /// user backs out of the flow.
  EmailVerificationStart? get pendingVerification => _pendingVerification;

  /// Called once at app startup: restores any saved session, or - per the
  /// spec's "most important" requirement - silently logs in with the
  /// device id so the user lands straight on Today with zero friction.
  Future<void> bootstrap() async {
    await _sessionStore.restore();
    if (_sessionStore.current == null) {
      await _bootstrapDeviceLogin();
    }
    _isBootstrapping = false;
    notifyListeners();
  }

  /// The device-login call every session depends on - without it every
  /// `[Authorize]`'d endpoint (splits activation included) 401s for the
  /// rest of the app's life, with nothing surfacing why since the app has
  /// already moved on to the shell. A single transient failure right at
  /// cold start (network still settling, backend mid-restart) used to be
  /// enough to strand a device unauthenticated silently; retry a few times
  /// with backoff before actually giving up.
  Future<void> _bootstrapDeviceLogin() async {
    final deviceId = await _sessionStore.deviceId();
    for (var attempt = 0; attempt < 3; attempt++) {
      final ok = await _run(() async {
        final result = await _repository.loginWithDevice(deviceId);
        await _applySession(result);
      });
      if (ok) return;
      if (attempt < 2) {
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }
  }

  /// Step 1 of email registration: emails a 6-digit code and stashes the
  /// result so the verify step knows what it's waiting on. No session is
  /// created yet.
  Future<bool> startEmailRegistration(
          {required String email,
          required String password,
          String? displayName}) =>
      _run(() async {
        final result = await _repository.startEmailRegistration(
            email: email, password: password, displayName: displayName);
        _pendingVerification = result;
      });

  /// Step 2: confirms the emailed code, creating the account and session.
  Future<bool> verifyEmailRegistration(String code) => _run(() async {
        final pending = _pendingVerification;
        if (pending == null) {
          throw const ApiException('No pending email verification to confirm.');
        }
        final result = await _repository.verifyEmailRegistration(
            pendingId: pending.pendingId, code: code);
        await _applySession(result);
        _pendingVerification = null;
      });

  /// Re-sends a fresh code for the in-progress pending registration.
  Future<bool> resendEmailVerification() => _run(() async {
        final pending = _pendingVerification;
        if (pending == null) {
          throw const ApiException('No pending email verification to resend.');
        }
        final result =
            await _repository.resendEmailVerification(pending.pendingId);
        _pendingVerification = result;
      });

  /// Discards an in-progress registration - called when the wizard's back
  /// button leaves the verify step, so a later retry starts clean.
  void cancelEmailVerification() {
    _pendingVerification = null;
    notifyListeners();
  }

  Future<bool> loginEmail({required String email, required String password}) =>
      _run(() async {
        final result =
            await _repository.loginEmail(email: email, password: password);
        await _applySession(result);
      });

  Future<bool> loginWithGoogle() => _run(() async {
        final account = await _googleSignIn.signIn();
        if (account == null)
          throw const ApiException('Google sign-in was cancelled.');
        final auth = await account.authentication;
        final idToken = auth.idToken;
        if (idToken == null)
          throw const ApiException('Google did not return an identity token.');
        final result = await _repository.loginGoogle(idToken);
        await _applySession(result);
      });

  Future<bool> loginWithApple() => _run(() async {
        final credential = await SignInWithApple.getAppleIDCredential(
          scopes: [
            AppleIDAuthorizationScopes.email,
            AppleIDAuthorizationScopes.fullName
          ],
        );
        final displayName = [credential.givenName, credential.familyName]
            .where((part) => part != null && part.isNotEmpty)
            .join(' ');
        final result = await _repository.loginApple(
          identityToken: credential.identityToken ?? '',
          displayName: displayName.isEmpty ? null : displayName,
        );
        await _applySession(result);
      });

  Future<void> logout() async {
    await _googleSignIn.signOut();
    await _sessionStore.clear();
    notifyListeners();
    await bootstrap();
  }

  Future<void> _applySession(AuthResult result) =>
      _sessionStore.save(result.toSession());

  /// Runs an auth action, tracking busy/error state uniformly so no screen
  /// re-implements its own try/catch/setState dance.
  Future<bool> _run(Future<void> Function() action) async {
    _isBusy = true;
    _lastError = null;
    notifyListeners();
    try {
      await action();
      _isBusy = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _isBusy = false;
      _lastError = e.userMessage;
      notifyListeners();
      return false;
    } catch (_) {
      _isBusy = false;
      _lastError = ApiException.genericMessage;
      notifyListeners();
      return false;
    }
  }
}
