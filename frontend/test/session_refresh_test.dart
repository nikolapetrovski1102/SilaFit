import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/api/api_exception.dart';
import 'package:silafit/core/session/session_store.dart';

/// In-memory session store - no secure storage.
class _MemorySession extends SessionStore {
  SilenSession? _current;
  int clearCalls = 0;

  _MemorySession(this._current);

  @override
  SilenSession? get current => _current;

  @override
  String? get currentToken => _current?.token;

  @override
  Future<void> save(SilenSession session) async => _current = session;

  @override
  Future<void> clear() async {
    clearCalls++;
    _current = null;
  }

  @override
  Future<String> deviceId() async => 'device-1';
}

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'success': true, 'data': data}), 200);

http.Response _fail(int status) =>
    http.Response(jsonEncode({'success': false, 'message': 'no'}), status);

Map<String, dynamic> _auth(String token, {String userId = 'user-1'}) => {
      'token': token,
      'refreshToken': 'refresh-1',
      'userId': userId,
      'accountTier': 'Registered',
    };

const _expired = SilenSession(
    token: 'expired',
    refreshToken: 'refresh-1',
    userId: 'user-1',
    accountTier: AccountTier.registered);

String _parse(dynamic json) => json as String;

void main() {
  test('an expired token is renewed with the refresh token and retried',
      () async {
    final store = _MemorySession(_expired);
    final api = ApiClient(
      sessionStore: store,
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          expect(jsonDecode(req.body)['refreshToken'], 'refresh-1');
          return _ok(_auth('fresh'));
        }
        return req.headers['Authorization'] == 'Bearer fresh'
            ? _ok('data')
            : _fail(401);
      }),
    );

    expect(await api.get('/x', _parse), 'data');
    expect(store.current!.token, 'fresh');
    expect(store.current!.refreshToken, 'refresh-1');
    expect(store.clearCalls, 0);
  });

  test('parallel 401s share a single refresh call', () async {
    final store = _MemorySession(_expired);
    var refreshCalls = 0;
    final api = ApiClient(
      sessionStore: store,
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/auth/refresh')) {
          refreshCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return _ok(_auth('fresh'));
        }
        return req.headers['Authorization'] == 'Bearer fresh'
            ? _ok('data')
            : _fail(401);
      }),
    );

    final results =
        await Future.wait(List.generate(8, (i) => api.get('/x$i', _parse)));

    expect(results, everyElement('data'));
    expect(refreshCalls, 1);
  });

  for (final failure in <String, Future<http.Response> Function()>{
    'no connection': () async =>
        throw const SocketException('network unreachable'),
    'a rate limit': () async => _fail(429),
    'a server error': () async => _fail(503),
  }.entries) {
    test('${failure.key} during renewal keeps the session', () async {
      final store = _MemorySession(_expired);
      final api = ApiClient(
        sessionStore: store,
        httpClient: MockClient((req) async {
          if (req.url.path.contains('/auth/')) {
            return failure.value();
          }
          return _fail(401);
        }),
      );

      await expectLater(
          api.get('/x', _parse),
          throwsA(isA<ApiException>()
              .having((e) => e.isNetworkError, 'isNetworkError', isTrue)));
      expect(store.clearCalls, 0);
      expect(store.current, isNotNull);
    });
  }

  test('a refused refresh token falls back to device login for the same user',
      () async {
    final store = _MemorySession(_expired);
    final api = ApiClient(
      sessionStore: store,
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/auth/refresh')) return _fail(401);
        if (req.url.path.endsWith('/auth/device')) {
          return _ok(_auth('from-device'));
        }
        return req.headers['Authorization'] == 'Bearer from-device'
            ? _ok('data')
            : _fail(401);
      }),
    );

    expect(await api.get('/x', _parse), 'data');
    expect(store.clearCalls, 0);
  });

  test('the session ends only when the server definitely refuses it',
      () async {
    final store = _MemorySession(_expired);
    final api = ApiClient(
      sessionStore: store,
      httpClient: MockClient((req) async {
        if (req.url.path.endsWith('/auth/refresh')) return _fail(401);
        // Device login now answers with a different (guest) account.
        if (req.url.path.endsWith('/auth/device')) {
          return _ok(_auth('guest', userId: 'someone-else'));
        }
        return _fail(401);
      }),
    );

    await expectLater(
        api.get('/x', _parse),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)));
    expect(store.clearCalls, 1);
    expect(store.current, isNull);
  });

  test('a pre-refresh-token session picks one up with its access token',
      () async {
    final store = _MemorySession(const SilenSession(
        token: 'still-valid',
        userId: 'user-1',
        accountTier: AccountTier.registered));
    final api = ApiClient(
      sessionStore: store,
      httpClient: MockClient((req) async {
        expect(req.url.path, endsWith('/auth/refresh'));
        expect(req.headers['Authorization'], 'Bearer still-valid');
        return _ok(_auth('fresh'));
      }),
    );

    await api.ensureRefreshToken();

    expect(store.current!.refreshToken, 'refresh-1');
    expect(store.current!.token, 'fresh');
  });
}
