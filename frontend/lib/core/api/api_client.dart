import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../session/session_store.dart';
import 'api_config.dart';
import 'api_exception.dart';
import 'response_cache.dart';

/// How long a request waits for a response before giving up. Without this,
/// an unreachable host (wrong LAN IP, phone off the dev network, dropped
/// packets) leaves the request pending forever with no error and no way for
/// the UI to recover - it just spins.
const _requestTimeout = Duration(seconds: 15);

/// Cached GETs give up sooner: on patchy gym Wi-Fi, a saved copy after a few
/// seconds beats a skeleton for fifteen.
const _cachedReadTimeout = Duration(seconds: 8);

/// For a write the offline queue catches when it fails (finishing a
/// workout, bodyweight, meals): on gym Wi-Fi that's connected but not
/// passing traffic, handing it to the queue after a few seconds beats a
/// spinner for fifteen. The queue's own replay uses the normal timeout, and
/// every such write is safe to send twice, so giving up early loses nothing.
const queuedWriteTimeout = Duration(seconds: 6);

/// Pause before the one automatic retry of a request that's safe to repeat.
/// Long enough for a restarting API container to come back behind nginx,
/// short enough that the user just sees a slightly slower load.
const _retryDelay = Duration(milliseconds: 700);

/// A value served from [ResponseCache] rather than the network.
class CachedValue<T> {
  final T value;
  final DateTime savedAtUtc;

  const CachedValue(this.value, this.savedAtUtc);
}

/// The single HTTP entry point for the whole app. Every feature repository
/// calls through this instead of touching `package:http` directly, so
/// header/auth/error handling never gets duplicated per-feature.
///
/// On a 401 it renews the access token with the stored refresh token and
/// retries once. It clears the stored session only when the server definitely
/// refuses to renew it - never because the renewal couldn't get through.
///
/// A GET made with `cache: true` keeps its last successful payload in
/// [ResponseCache] and answers from it when the server can't be reached (no
/// connection, timeout, or a 5xx), so screens keep working offline without
/// each feature reinventing that.
class ApiClient {
  final SessionStore sessionStore;
  final http.Client _http;
  final ResponseCache _cache;

  /// The access-token renewal in flight, shared by every request that hit a
  /// 401 meanwhile. See [_renewSession].
  Future<_Renewal>? _renewing;

  /// True once a request has failed to reach the server - or reached it
  /// while it was broken (a 5xx) and was answered from the saved copy - and
  /// false again as soon as a non-5xx response arrives. Drives the app-wide
  /// offline pill, so saved data never passes for fresh.
  final ValueNotifier<bool> isOffline = ValueNotifier(false);

  ApiClient(
      {required this.sessionStore,
      http.Client? httpClient,
      ResponseCache? cache})
      : _http = httpClient ?? http.Client(),
        _cache = cache ?? ResponseCache();

  /// [cache] opts this read into the offline fallback described on the class.
  /// [sameDayOnly] limits that fallback to a copy saved on the current local
  /// day - for endpoints like `/today` whose answer is implicitly "today".
  Future<T> get<T>(String path, T Function(dynamic json) parse,
      {Map<String, String>? query,
      bool cache = false,
      bool sameDayOnly = false}) {
    final uri =
        Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);
    return _send(path, () => _http.get(uri, headers: _headers()), parse,
        cacheKey: cache ? _cacheKey(path, query) : null,
        sameDayOnly: sameDayOnly,
        canRetry: true,
        timeout: cache ? _cachedReadTimeout : _requestTimeout);
  }

  /// The saved copy of a `cache: true` GET without touching the network, so a
  /// screen can paint last-known data instantly and refresh behind it. Null
  /// when nothing usable is saved.
  Future<CachedValue<T>?> cached<T>(String path, T Function(dynamic json) parse,
      {Map<String, String>? query, bool sameDayOnly = false}) =>
      _fromCache(_cacheKey(path, query), parse, sameDayOnly);

  /// Forgets every saved response - part of sign-out's local wipe.
  Future<void> clearCache() => _cache.clear();

  /// Overwrites the saved copy of a `cache: true` GET with [data] the app
  /// already knows is newer (say, the subscription a purchase just granted),
  /// so an offline fallback can't resurrect the old answer.
  Future<void> updateCached(String path, dynamic data,
          {Map<String, String>? query}) =>
      _cache.write(_cacheKey(path, query), data);

  /// [idempotent] marks a POST the server treats as safe to repeat (an
  /// upsert), so it gets the same one automatic retry as a GET. [timeout]
  /// overrides the default for endpoints that wait on a third party.
  Future<T> post<T>(String path, T Function(dynamic json) parse,
      {Object? body, bool idempotent = false, Duration? timeout}) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    return _send(
        path,
        () =>
            _http.post(uri, headers: _headers(), body: jsonEncode(body ?? {})),
        parse,
        canRetry: idempotent,
        timeout: timeout ?? _requestTimeout);
  }

  Future<T> put<T>(String path, T Function(dynamic json) parse,
      {Object? body, Duration? timeout}) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    return _send(
        path,
        () => _http.put(uri, headers: _headers(), body: jsonEncode(body ?? {})),
        parse,
        timeout: timeout ?? _requestTimeout);
  }

  Future<T> delete<T>(String path, T Function(dynamic json) parse,
      {Object? body, Duration? timeout}) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    return _send(
        path,
        () => _http.delete(uri,
            headers: _headers(), body: jsonEncode(body ?? {})),
        parse,
        timeout: timeout ?? _requestTimeout);
  }

  /// Uploads [bytes] as the multipart file field [fileField] alongside plain
  /// text [fields]. The request is rebuilt on every attempt (a sent
  /// `MultipartRequest` can't be re-sent), so the silent re-auth retry works.
  /// [timeout] is longer than normal requests' because the server may be
  /// waiting on an AI model before it answers.
  Future<T> postMultipart<T>(
    String path,
    T Function(dynamic json) parse, {
    required String fileField,
    required List<int> bytes,
    required String filename,
    required MediaType contentType,
    Map<String, String> fields = const {},
    Duration timeout = const Duration(seconds: 90),
  }) {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    Future<http.Response> request() async {
      final multipart = http.MultipartRequest('POST', uri)
        ..fields.addAll(fields)
        ..files.add(http.MultipartFile.fromBytes(fileField, bytes,
            filename: filename, contentType: contentType));
      // No JSON content type here - MultipartRequest sets its own boundary.
      final token = sessionStore.currentToken;
      if (token != null) multipart.headers['Authorization'] = 'Bearer $token';
      return http.Response.fromStream(await _http.send(multipart));
    }

    return _send(path, request, parse, timeout: timeout);
  }

  Map<String, String> _headers() {
    final headers = {'Content-Type': 'application/json'};
    final token = sessionStore.currentToken;
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  String _cacheKey(String path, Map<String, String>? query) =>
      ResponseCache.keyFor(
          sessionStore.current?.userId ?? 'anonymous', path, query);

  static bool _savedToday(CachedPayload payload) {
    final saved = payload.savedAtUtc.toLocal();
    final now = DateTime.now();
    return saved.year == now.year &&
        saved.month == now.month &&
        saved.day == now.day;
  }

  /// The saved copy for [cacheKey], parsed, or null when there's no usable
  /// one. Wrapped so a legitimately-null parsed value still counts as a hit.
  Future<CachedValue<T>?> _fromCache<T>(String? cacheKey,
      T Function(dynamic json) parse, bool sameDayOnly) async {
    if (cacheKey == null) return null;
    final payload = await _cache.read(cacheKey);
    if (payload == null || (sameDayOnly && !_savedToday(payload))) return null;
    try {
      return CachedValue(parse(payload.data), payload.savedAtUtc);
    } catch (_) {
      return null;
    }
  }

  /// [canRetry] gives a request that's safe to repeat one more attempt when
  /// the first never got a usable answer. Most intermittent "took too long"
  /// / "cannot reach" errors are a dead pooled connection (the phone switched
  /// networks or slept) or the API restarting behind nginx; a fresh attempt
  /// a moment later almost always lands.
  Future<T> _send<T>(String path, Future<http.Response> Function() request,
      T Function(dynamic json) parse,
      {bool isRetry = false,
      bool canRetry = false,
      Duration timeout = _requestTimeout,
      String? cacheKey,
      bool sameDayOnly = false}) async {
    Future<T> retry() async {
      await Future<void>.delayed(_retryDelay);
      return _send(path, request, parse,
          isRetry: isRetry,
          timeout: timeout,
          cacheKey: cacheKey,
          sameDayOnly: sameDayOnly);
    }

    final sentToken = sessionStore.currentToken;
    late final http.Response response;
    try {
      response = await request().timeout(timeout);
    } catch (e) {
      // A connection error fails fast, so retrying costs little. A timeout
      // already cost the full wait - answer from the saved copy if there is
      // one rather than make the user sit through a second.
      if (canRetry && e is! TimeoutException) return retry();
      final hit = await _fromCache(cacheKey, parse, sameDayOnly);
      if (hit != null) {
        isOffline.value = true;
        return hit.value;
      }
      if (canRetry) return retry();
      isOffline.value = true;
      if (e is TimeoutException) {
        throw const ApiException(
            'The server took too long to respond. Check your connection and try again.',
            isNetworkError: true);
      }
      throw const ApiException(
          'Cannot reach the server. Check your connection and try again.',
          isNetworkError: true);
    }
    // A 5xx isn't the server back to normal - leave the pill as it was.
    if (response.statusCode < 500) isOffline.value = false;

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
      if (response.statusCode == 401 && !path.startsWith('/auth/') && !isRetry) {
        // The access token expired. Trade the refresh token for a new one and
        // retry once, so a short-lived token is invisible in normal use. A 401
        // from an /auth/ endpoint is a failed credential, not a dead session.
        // If another request already renewed while this one was in flight,
        // just retry with the token it got.
        final outcome =
            sessionStore.current != null && sessionStore.currentToken != sentToken
                ? _Renewal.renewed
                : await _renewSession();
        switch (outcome) {
          case _Renewal.renewed:
            return _send(path, request, parse,
                isRetry: true,
                canRetry: canRetry,
                timeout: timeout,
                cacheKey: cacheKey,
                sameDayOnly: sameDayOnly);
          case _Renewal.rejected:
            // The server definitely won't take this session back.
            await sessionStore.clear();
          case _Renewal.unavailable:
            // Couldn't reach the server to renew - keep the session and treat
            // it like being offline, so the next request tries again.
            final hit = await _fromCache(cacheKey, parse, sameDayOnly);
            if (hit != null) {
              isOffline.value = true;
              return hit.value;
            }
            throw const ApiException(
                'Cannot reach the server. Check your connection and try again.',
                isNetworkError: true);
        }
      }
      // nginx answers 502/503/504 while the API container restarts or is
      // briefly saturated - not a real verdict on the request.
      if (canRetry && const {502, 503, 504}.contains(response.statusCode)) {
        return retry();
      }
      // The server is up but broken right now - for a read, the saved copy
      // is still a better answer than an error card.
      if (response.statusCode >= 500) {
        final hit = await _fromCache(cacheKey, parse, sameDayOnly);
        if (hit != null) {
          isOffline.value = true;
          return hit.value;
        }
      }
      final message =
          envelope?['message'] as String? ?? ApiException.genericMessage;
      throw ApiException(message, statusCode: response.statusCode);
    }

    final T parsed;
    try {
      parsed = parse(envelope?['data']);
    } catch (_) {
      throw const ApiException(ApiException.genericMessage);
    }
    // Only after it parsed - never save a payload this build can't read back.
    if (cacheKey != null) unawaited(_cache.write(cacheKey, envelope?['data']));
    return parsed;
  }

  /// Renews the access token after a 401. Every request that hits a 401
  /// while a renewal is in flight shares that one renewal, so a screen firing
  /// ten requests at once with an expired token makes one `/auth/refresh`
  /// call, not ten that trip the server's rate limit.
  Future<_Renewal> _renewSession() =>
      _renewing ??= _doRenewSession().whenComplete(() => _renewing = null);

  Future<_Renewal> _doRenewSession() async {
    final current = sessionStore.current;
    if (current == null) return _Renewal.rejected;

    final refreshToken = current.refreshToken;
    if (refreshToken != null && refreshToken.isNotEmpty) {
      final outcome = await _postSessionRenewal(
          '/auth/refresh', {'refreshToken': refreshToken}, current);
      // Refresh token refused (revoked, expired, account gone) - the device
      // login below is the last chance before the session really ends.
      if (outcome != _Renewal.rejected) return outcome;
    }

    // Sessions from before refresh tokens, or whose refresh token was
    // refused: device login still restores the account when this device
    // owns it (or was linked to it at sign-in).
    final deviceId = await sessionStore.deviceId();
    if (deviceId.isEmpty) return _Renewal.rejected;
    return _postSessionRenewal('/auth/device', {'deviceId': deviceId}, current);
  }

  /// One renewal call. Only a definite "no" - a 401/403, or an answer for a
  /// *different* user - counts as [_Renewal.rejected]; no connection, a
  /// timeout, a 429 or a 5xx is [_Renewal.unavailable], which must never end
  /// the session (that used to sign people out on bad gym Wi-Fi).
  Future<_Renewal> _postSessionRenewal(
      String path, Map<String, String> body, SilenSession current,
      {String? bearer}) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('${ApiConfig.baseUrl}$path'),
            headers: {
              'Content-Type': 'application/json',
              if (bearer != null) 'Authorization': 'Bearer $bearer',
            },
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);
    } catch (_) {
      return _Renewal.unavailable;
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      return _Renewal.rejected;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return _Renewal.unavailable;
    }

    try {
      final data = (jsonDecode(response.body) as Map<String, dynamic>)['data']
          as Map<String, dynamic>?;
      final token = data?['token'] as String?;
      final userId = data?['userId'] as String?;
      if (token == null || token.isEmpty) return _Renewal.unavailable;
      // Never silently swap the account underneath the UI.
      if (userId != current.userId) return _Renewal.rejected;

      await sessionStore.save(SilenSession(
        token: token,
        refreshToken: (data?['refreshToken'] as String?) ?? current.refreshToken,
        userId: current.userId,
        accountTier: (data?['accountTier'] as String?) ?? current.accountTier,
        email: data?['email'] as String?,
        displayName: data?['displayName'] as String?,
      ));
      return _Renewal.renewed;
    } catch (_) {
      return _Renewal.unavailable;
    }
  }

  /// Gives a session saved by an app version from before refresh tokens its
  /// first one, while its access token is still valid. Best-effort: if the
  /// access token has already expired, the 401 path falls back to device
  /// login as before.
  Future<void> ensureRefreshToken() async {
    final current = sessionStore.current;
    if (current == null || current.refreshToken != null) return;
    await _postSessionRenewal('/auth/refresh', const {}, current,
        bearer: current.token);
  }

  /// Sign-out: tells the server to forget this session's refresh token.
  /// Best-effort with a short timeout - signing out locally never waits on it.
  Future<void> revokeRefreshToken() async {
    final refreshToken = sessionStore.current?.refreshToken;
    if (refreshToken == null) return;
    try {
      await _http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/auth/logout'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
  }
}

enum _Renewal { renewed, rejected, unavailable }
