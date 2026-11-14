import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silafit/features/meals/open_food_facts_client.dart';

void main() {
  setUp(OpenFoodFactsClient.reset);

  http.Response product(String code) => http.Response(
      jsonEncode({
        'code': code,
        'status': 1,
        'product': {'product_name': 'Ajvar'}
      }),
      200);

  test('returns the trimmed product and asks only for the parsed fields',
      () async {
    Uri? asked;
    final client = OpenFoodFactsClient(httpClient: MockClient((r) async {
      asked = r.url;
      return product('5310000000017');
    }));

    final result = await client.fetchProduct('5310000000017');

    expect(result, {
      'status': 1,
      'product': {'product_name': 'Ajvar'}
    });
    expect(asked!.path, '/api/v2/product/5310000000017');
    expect(asked!.queryParameters['fields'], contains('nutriments'));
  });

  test('holds itself to 15 calls in a rolling minute', () async {
    var calls = 0;
    var now = DateTime(2026, 11, 12, 12);
    final client = OpenFoodFactsClient(
        now: () => now,
        httpClient: MockClient((r) async {
          calls++;
          return product(r.url.pathSegments.last);
        }));

    for (var i = 0; i < 15; i++) {
      expect(
          await client
              .fetchProduct('53100000000${i.toString().padLeft(2, '0')}'),
          isNotNull);
    }
    expect(await client.fetchProduct('5310000000999'), isNull);
    expect(calls, 15);

    now = now.add(const Duration(minutes: 1, seconds: 1));
    expect(await client.fetchProduct('5310000000999'), isNotNull);
    expect(calls, 16);
  });

  test('a rescan and a double scan share one call', () async {
    var calls = 0;
    final client = OpenFoodFactsClient(httpClient: MockClient((r) async {
      calls++;
      return product('5310000000017');
    }));

    await Future.wait([
      client.fetchProduct('5310000000017'),
      client.fetchProduct('5310000000017'),
    ]);
    await client.fetchProduct('5310000000017');

    expect(calls, 1);
  });

  test('unknown barcodes are remembered, server errors are not', () async {
    var calls = 0;
    var status = 404;
    final client = OpenFoodFactsClient(httpClient: MockClient((r) async {
      calls++;
      return http.Response('{"status":0}', status);
    }));

    expect(await client.fetchProduct('5310000000017'), isNull);
    expect(await client.fetchProduct('5310000000017'), isNull);
    expect(calls, 1);

    status = 503;
    expect(await client.fetchProduct('5310000000024'), isNull);
    expect(await client.fetchProduct('5310000000024'), isNull);
    expect(calls, 3);
  });

  test('never throws when the network fails', () async {
    final client = OpenFoodFactsClient(
        httpClient:
            MockClient((r) async => throw http.ClientException('offline')));

    expect(await client.fetchProduct('5310000000017'), isNull);
  });
}
