import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../session/session_store.dart';
import 'api_config.dart';
import 'api_exception.dart';

/// How long a request waits for a response before giving up. Without this,
/// an unreachable host (wrong LAN IP, phone off the dev network, dropped
/// packets) leaves the request pending forever with no error and no way for
/// the UI to recover - it just spins.
const _requestTimeout = Duration(seconds: 15);

/// The single HTTP entry point for the whole app. Every feature repository
/// calls through this instead of touching `package:http` directly, so
/// header/auth/error handling never gets duplicated per-feature.
///
/// On a 401 it clears the stored session (the token is dead) so the next
/// screen read notices the user is logged out; callers still see the
/// exception and decide what to show.
class ApiClient {
  final SessionStore sessionStore;
  final http.Client _http;

  ApiClient({required this.sessionStore, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  Future<T> get<T>(String path, T Function(dynamic json) parse,
      {Map<String, String>? query}) {
    final uri =
        Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);
    return _send(path, () => _http.get(uri, headers: _headers()), parse);
  }

  Future<T> post<T>(String path, T Function(dynamic json) parse,
      {Object? body}) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    return _send(
        path,
        () =>
            _http.post(uri, headers: _headers(), body: jsonEncode(body ?? {})),
        parse);
  }

  Future<T> put<T>(String path, T Function(dynamic json) parse,
      {Object? body}) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    return _send(
        path,
        () =>
            _http.put(uri, headers: _headers(), body: jsonEncode(body ?? {})),
        parse);
  }

  Future<T> delete<T>(String path, T Function(dynamic json) parse,
      {Object? body}) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    return _send(
        path,
        () => _http.delete(uri,
            headers: _headers(), body: jsonEncode(body ?? {})),
        parse);
  }

  Map<String, String> _headers() {
    final headers = {'Content-Type': 'application/json'};
    final token = sessionStore.currentToken;
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Future<T> _send<T>(String path, Future<http.Response> Function() request,
      T Function(dynamic json) parse,
      {bool isRetry = false}) async {
    late final http.Response response;
    try {
      response = await request().timeout(_requestTimeout);
    } on TimeoutException {
      throw const ApiException(
          'The server took too long to respond. Check your connection and try again.');
    } catch (_) {
      throw const ApiException(
          'Cannot reach the server. Check your connection and try again.');
    }

    Map<String, dynamic>? envelope;
    try {
      if (response.body.isNotEmpty) {
        envelope = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      envelope = null;
    }

    final success = envelope?['success'] as bool? ??
        (response.statusCode >= 200 && response.statusCode < 300);

    if (!success) {
      if (response.statusCode == 401 && !path.startsWith('/auth/')) {
        // The access token expired. Re-run the idempotent device login and
        // retry once, so a short-lived token is invisible in normal use. A 401
        // from an /auth/ endpoint is a failed credential, not a dead session,
        // so it must not clear the guest session the way this used to.
        if (!isRetry && await _trySilentDeviceReauth()) {
          return _send(path, request, parse, isRetry: true);
        }
        await sessionStore.clear();
      }
      final message =
          envelope?['message'] as String? ?? ApiException.genericMessage;
      throw ApiException(message, statusCode: response.statusCode);
    }

    try {
      return parse(envelope?['data']);
    } catch (_) {
      throw const ApiException(ApiException.genericMessage);
    }
  }

  /// Best-effort re-auth for an expired token using the stored device id.
  /// Returns true only when the server re-issued a token for the *same* user,
  /// so this can never silently swap the account underneath the UI.
  Future<bool> _trySilentDeviceReauth() async {
    final current = sessionStore.current;
    if (current == null) return false;

    try {
      final deviceId = await sessionStore.deviceId();
      if (deviceId.isEmpty) return false;

      final response = await _http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/auth/device'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'deviceId': deviceId}),
          )
          .timeout(_requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) return false;

      final data =
          (jsonDecode(response.body) as Map<String, dynamic>)['data']
              as Map<String, dynamic>?;
      final token = data?['token'] as String?;
      final userId = data?['userId'] as String?;
      if (token == null || token.isEmpty || userId != current.userId) {
        return false;
      }

      await sessionStore.save(SilenSession(
        token: token,
        userId: current.userId,
        accountTier: (data?['accountTier'] as String?) ?? current.accountTier,
        email: data?['email'] as String?,
        displayName: data?['displayName'] as String?,
      ));
      return true;
    } catch (_) {
      return false;
    }
  }
}
