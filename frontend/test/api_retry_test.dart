import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/api/api_exception.dart';
import 'package:silafit/core/api/response_cache.dart';
import 'package:silafit/core/session/session_store.dart';

class _FakeSession implements SessionStore {
  @override
  final SilenSession? current = const SilenSession(
      token: 't', userId: 'user-1', accountTier: AccountTier.registered);

  @override
  String? get currentToken => current?.token;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'success': true, 'data': data}), 200);

void main() {
  late Directory dir;
  late ResponseCache cache;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('silen_retry_test');
    cache = ResponseCache(directory: () async => dir);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ApiClient client(Future<http.Response> Function(int attempt) respond) {
    var attempt = 0;
    return ApiClient(
      sessionStore: _FakeSession(),
      cache: cache,
      httpClient: MockClient((_) => respond(++attempt)),
    );
  }

  String parse(dynamic json) => json as String;

  test('a GET survives one dropped connection', () async {
    var calls = 0;
    final api = client((attempt) async {
      calls = attempt;
      if (attempt == 1) throw const SocketException('connection reset');
      return _ok('fresh');
    });
    expect(await api.get('/x', parse), 'fresh');
    expect(calls, 2);
    expect(api.isOffline.value, isFalse);
  });

  test('a GET retries once on a 503 from the proxy', () async {
    var calls = 0;
    final api = client((attempt) async {
      calls = attempt;
      return attempt == 1 ? http.Response('', 503) : _ok('fresh');
    });
    expect(await api.get('/x', parse), 'fresh');
    expect(calls, 2);
  });

  test('a non-idempotent POST is not retried', () async {
    var calls = 0;
    final api = client((attempt) async {
      calls = attempt;
      return http.Response('', 503);
    });
    await expectLater(api.post('/x', parse), throwsA(isA<ApiException>()));
    expect(calls, 1);
  });

  test('an idempotent POST is retried', () async {
    var calls = 0;
    final api = client((attempt) async {
      calls = attempt;
      if (attempt == 1) throw const SocketException('connection reset');
      return _ok('done');
    });
    expect(await api.post('/x', parse, idempotent: true), 'done');
    expect(calls, 2);
  });
}
