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

  static const String genericMessage = 'Something went wrong';

  @override
  String toString() => 'ApiException($statusCode, $userMessage)';
}
