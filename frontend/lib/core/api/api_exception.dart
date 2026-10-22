/// The one error type every repository throws. [userMessage] is always safe
/// to show directly in the UI - it's either the backend's own `Message`
/// field or the global fallback, matching the backend's "one global message
/// when the error is not supported" rule.
class ApiException implements Exception {
  final int? statusCode;
  final String userMessage;

  /// True when the request never got an answer - no connection, or it timed
  /// out. The server may or may not have acted on it.
  final bool isNetworkError;

  const ApiException(this.userMessage,
      {this.statusCode, this.isNetworkError = false});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;

  /// 422 - the request was well-formed but there isn't enough logged history yet to act on it
  /// (currently: AnalyticsController's monthly review before a month has real activity logged).
  bool get isInsufficientData => statusCode == 422;

  /// 428 - an AI feature needs the user's consent to share their data with
  /// the third-party AI provider first (see `AiConsentGate`).
  bool get isAiConsentRequired => statusCode == 428;

  /// 429 - a daily allowance is spent (currently: AI meal-photo scans).
  bool get isTooManyRequests => statusCode == 429;

  /// Worth trying again later rather than reporting as a failure: the
  /// server was unreachable or broke (5xx), not a refusal of the request.
  bool get isRetryable =>
      isNetworkError || (statusCode != null && statusCode! >= 500);

  static const String genericMessage = 'Something went wrong';

  @override
  String toString() => 'ApiException($statusCode, $userMessage)';
}
