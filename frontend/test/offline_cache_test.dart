import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/api/api_exception.dart';
import 'package:silafit/core/api/response_cache.dart';
import 'package:silafit/core/session/session_store.dart';

/// A [SessionStore] stand-in that never touches platform storage.
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
  late bool online;
  late int status;

  ApiClient client() => ApiClient(
        sessionStore: _FakeSession(),
        cache: cache,
        httpClient: MockClient((request) async {
          if (!online) throw const SocketException('no route to host');
          if (status != 200) return http.Response('', status);
          return _ok({'value': request.url.queryParameters['n'] ?? 'fresh'});
        }),
      );

  String parse(dynamic json) => (json as Map<String, dynamic>)['value'];

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('silen_cache_test');
    cache = ResponseCache(directory: () async => dir);
    online = true;
    status = 200;
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a cached GET answers from the saved copy when offline', () async {
    final api = client();
    expect(await api.get('/settings', parse, cache: true), 'fresh');
    // Let the fire-and-forget write land.
    await Future<void>.delayed(Duration.zero);

    online = false;
    expect(await api.get('/settings', parse, cache: true), 'fresh');
    expect(api.isOffline.value, isTrue);
  });

  test('the saved copy survives an app restart (new cache instance)',
      () async {
    await client().get('/settings', parse, cache: true);
    // The disk write is fire-and-forget - wait for the file itself.
    final file =
        File('${dir.path}/${ResponseCache.keyFor('user-1', '/settings')}.json');
    for (var i = 0; i < 100 && !await file.exists(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    cache = ResponseCache(directory: () async => dir);
    online = false;
    expect(await client().get('/settings', parse, cache: true), 'fresh');
  });

  test('a 5xx falls back to the saved copy too', () async {
    final api = client();
    await api.get('/splits', parse, cache: true);
    await Future<void>.delayed(Duration.zero);

    status = 503;
    expect(await api.get('/splits', parse, cache: true), 'fresh');
    // Saved data on screen - the pill has to say so.
    expect(api.isOffline.value, isTrue);

    status = 200;
    await api.get('/splits', parse, cache: true);
    expect(api.isOffline.value, isFalse);
  });

  test('a 5xx with no saved copy leaves the pill as it was', () async {
    final api = client();
    status = 500;
    await expectLater(api.get('/foods/search', parse), throwsA(anything));
    expect(api.isOffline.value, isFalse);
  });

  test('an uncached GET still fails offline', () async {
    final api = client();
    await api.get('/foods/search', parse);
    online = false;
    expect(() => api.get('/foods/search', parse),
        throwsA(isA<ApiException>()));
  });

  test('query parameters get their own entry', () async {
    final api = client();
    await api.get('/meals/day', parse, query: {'n': 'a'}, cache: true);
    await Future<void>.delayed(Duration.zero);

    online = false;
    expect(
        () => api.get('/meals/day', parse, query: {'n': 'b'}, cache: true),
        throwsA(isA<ApiException>()));
    expect(await api.get('/meals/day', parse, query: {'n': 'a'}, cache: true),
        'a');
  });

  test('sameDayOnly ignores a copy saved on an earlier day', () async {
    final key = ResponseCache.keyFor('user-1', '/today');
    await File('${dir.path}/$key.json').writeAsString(jsonEncode({
      'savedAtUtc':
          DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String(),
      'data': {'value': 'yesterday'},
    }));

    online = false;
    final api = client();
    expect(await api.cached('/today', parse, sameDayOnly: true), isNull);
    expect(() => api.get('/today', parse, cache: true, sameDayOnly: true),
        throwsA(isA<ApiException>()));
    expect((await api.cached('/today', parse))?.value, 'yesterday');
  });

  test('entries are scoped per user and wiped by clearCache', () async {
    final api = client();
    await api.get('/settings', parse, cache: true);
    await Future<void>.delayed(Duration.zero);

    expect(await cache.read(ResponseCache.keyFor('user-2', '/settings')),
        isNull);

    await api.clearCache();
    online = false;
    expect(() => api.get('/settings', parse, cache: true),
        throwsA(isA<ApiException>()));
  });

  test('isOffline clears once a request gets through', () async {
    final api = client();
    online = false;
    await expectLater(api.get('/settings', parse), throwsA(anything));
    expect(api.isOffline.value, isTrue);

    online = true;
    await api.get('/settings', parse);
    expect(api.isOffline.value, isFalse);
  });
}
