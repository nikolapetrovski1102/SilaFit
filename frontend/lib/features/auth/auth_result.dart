import '../../core/session/session_store.dart';

/// Mirrors `Silen.Common.Dtos.AuthResultDto`.
class AuthResult {
  final String token;
  final String userId;
  final String accountTier;
  final String? email;
  final String? displayName;

  const AuthResult({
    required this.token,
    required this.userId,
    required this.accountTier,
    this.email,
    this.displayName,
  });

  factory AuthResult.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return AuthResult(
      token: map['token'] as String,
      userId: map['userId'] as String,
      accountTier: map['accountTier'] as String,
      email: map['email'] as String?,
      displayName: map['displayName'] as String?,
    );
  }

  SilenSession toSession() => SilenSession(
        token: token,
        userId: userId,
        accountTier: accountTier,
        email: email,
        displayName: displayName,
      );
}
