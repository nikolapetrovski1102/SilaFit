/// Mirrors `Silen.Common.Dtos.EmailVerificationStartResultDto` - returned by
/// both `register/email/start` and `register/email/resend`. The screen holds
/// onto [pendingId] and sends it back with the code the user types.
class EmailVerificationStart {
  final String pendingId;
  final int expiresInSeconds;

  const EmailVerificationStart({
    required this.pendingId,
    required this.expiresInSeconds,
  });

  factory EmailVerificationStart.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    return EmailVerificationStart(
      pendingId: map['pendingId'] as String,
      expiresInSeconds: map['expiresInSeconds'] as int,
    );
  }
}
