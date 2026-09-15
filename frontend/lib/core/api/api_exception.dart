/// The one error type every repository throws. [userMessage] is always safe
/// to show directly in the UI - it's either the backend's own `Message`
/// field or the global fallback, matching the backend's "one global message
/// when the error is not supported" rule.
class ApiException implements Exception {
  final int? statusCode;
  final String userMessage;

  const ApiException(this.userMessage, {this.statusCode});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;

  /// 422 - the request was well-formed but there isn't enough logged history yet to act on it
  /// (currently: AnalyticsController's monthly review before a month has real activity logged).
  bool get isInsufficientData => statusCode == 422;

  static const String genericMessage = 'Something went wrong';

  @override
  String toString() => 'ApiException($statusCode, $userMessage)';
}
