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
    return _send(() => _http.get(uri, headers: _headers()), parse);
  }

  Future<T> post<T>(String path, T Function(dynamic json) parse,
      {Object? body}) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    return _send(
        () =>
            _http.post(uri, headers: _headers(), body: jsonEncode(body ?? {})),
        parse);
  }

  Future<T> put<T>(String path, T Function(dynamic json) parse,
      {Object? body}) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    return _send(
        () =>
            _http.put(uri, headers: _headers(), body: jsonEncode(body ?? {})),
        parse);
  }

  Future<T> delete<T>(String path, T Function(dynamic json) parse) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    return _send(() => _http.delete(uri, headers: _headers()), parse);
  }

  Map<String, String> _headers() {
    final headers = {'Content-Type': 'application/json'};
    final token = sessionStore.currentToken;
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  Future<T> _send<T>(Future<http.Response> Function() request,
      T Function(dynamic json) parse) async {
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
      if (response.statusCode == 401) {
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
}
