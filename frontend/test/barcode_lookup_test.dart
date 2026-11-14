import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/api/response_cache.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/features/meals/meal_repository.dart';
import 'package:silafit/features/meals/open_food_facts_client.dart';
import 'package:silafit/features/meals/open_food_facts_product.dart';

class _FakeSession implements SessionStore {
  @override
  final SilenSession? current = const SilenSession(
      token: 't', userId: 'user-1', accountTier: AccountTier.registered);

  @override
  String? get currentToken => current?.token;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _code = '5310000000017';

Map<String, dynamic> _off({Object kcal = 90, String name = 'Ajvar blagi'}) => {
      'status': 1,
      'product': {
        'product_name': name,
        'brands': 'Vitaminka, Swisslion',
        'serving_quantity': '30',
        'image_front_small_url': 'https://images.openfoodfacts.org/a.jpg',
        'nutriments': {
          'energy-kcal_100g': kcal,
          'proteins_100g': 1.5,
          'carbohydrates_100g': '9',
          'fat_100g': 5,
          'sodium_100g': 0.4,
        },
      },
    };

void main() {
  group('OpenFoodFactsProduct', () {
    test('reads a loggable food the way the server does', () {
      final food = OpenFoodFactsProduct.toFood(_code, _off())!;

      expect(food.foodNutritionId, 0);
      expect(food.name, 'Ajvar blagi');
      expect(food.brandName, 'Vitaminka');
      expect(food.carbohydrateG, 9);
      expect(food.sodiumMg, 400);
      expect(food.servingSizeG, 30);
      expect(food.barcode, _code);
      expect(food.sourceName, 'Open Food Facts');
    });

    test('implausible nutrition is a hint, not a food', () {
      // kJ typed as kcal.
      final response = _off(kcal: 2500);

      expect(OpenFoodFactsProduct.toFood(_code, response), isNull);
      expect(OpenFoodFactsProduct.toHint(response)!.name, 'Ajvar blagi');
    });

    test('missing macros is a hint, not a food', () {
      final response = _off();
      (response['product'] as Map)['nutriments'] = {'energy-kcal_100g': 90};

      expect(OpenFoodFactsProduct.toFood(_code, response), isNull);
      expect(OpenFoodFactsProduct.toHint(response)!.brandName, 'Vitaminka');
    });
  });

  group('MealRepository.lookupBarcode', () {
    late Directory dir;

    setUp(() async {
      OpenFoodFactsClient.reset();
      dir = await Directory.systemTemp.createTemp('silen_barcode_test');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    MealRepository repo(
        {required Future<http.Response> Function(http.Request) server,
        required Future<http.Response> Function(http.Request) off}) {
      final api = ApiClient(
        sessionStore: _FakeSession(),
        cache: ResponseCache(directory: () async => dir),
        httpClient: MockClient(server),
      );
      return MealRepository(api,
          openFoodFacts: OpenFoodFactsClient(httpClient: MockClient(off)));
    }

    http.Response miss() => http.Response(
        jsonEncode({
          'success': true,
          'data': {'barcode': _code, 'checkOpenFoodFacts': true}
        }),
        200);

    test('shows the OFF product without waiting for the catalog save',
        () async {
      final saveStarted = Completer<String>();
      final saveAnswer = Completer<http.Response>(); // never answered here
      final r = repo(
        server: (req) {
          if (req.method == 'GET') {
            expect(req.url.queryParameters['offOnDevice'], 'true');
            return Future.value(miss());
          }
          saveStarted.complete(req.url.path);
          return saveAnswer.future;
        },
        off: (_) async => http.Response(jsonEncode(_off()), 200),
      );

      final result = await r.lookupBarcode(_code);

      expect(result.food!.name, 'Ajvar blagi');
      expect(await saveStarted.future,
          endsWith('/foods/barcode/$_code/open-food-facts'));
    });

    test('a failed save never reaches the user', () async {
      final r = repo(
        server: (req) async => req.method == 'GET'
            ? miss()
            : throw const SocketException('offline'),
        off: (_) async => http.Response(jsonEncode(_off()), 200),
      );

      final result = await r.lookupBarcode(_code);
      await pumpEventQueue();

      expect(result.food, isNotNull);
    });

    test('an implausible OFF product prefills the form and is not saved',
        () async {
      var posts = 0;
      final r = repo(
        server: (req) async {
          if (req.method == 'POST') posts++;
          return miss();
        },
        off: (_) async => http.Response(jsonEncode(_off(kcal: 2500)), 200),
      );

      final result = await r.lookupBarcode(_code);
      await pumpEventQueue();

      expect(result.found, isFalse);
      expect(result.hint!.name, 'Ajvar blagi');
      expect(posts, 0);
    });
  });
}
