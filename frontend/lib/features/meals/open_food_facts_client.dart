import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Asks Open Food Facts for a scanned barcode straight from the device, so
/// every phone uses its own IP and OFF budget (OFF allows ~100 product reads
/// a minute per IP) instead of every user queueing behind the server's one.
/// Only called after the server's catalog missed; whatever it finds is posted
/// back so the server can check it and save it for everyone.
///
/// Held to [maxPerMinute] lookups in any rolling minute - no person scans
/// faster than that - and a short [timeout], so a slow OFF falls back to the
/// "add it yourself" form instead of leaving the camera hanging. Never throws:
/// null means "not found, or couldn't ask".
class OpenFoodFactsClient {
  static const maxPerMinute = 15;
  static const timeout = Duration(seconds: 5);

  static const _base = 'https://world.openfoodfacts.org/api/v2/product/';

  /// Only what the server's parser reads - keeps the response a few KB.
  static const _fields =
      'code,product_name,product_name_en,product_name_mk,brands,'
      'image_front_small_url,image_front_url,serving_quantity,nutriments';

  /// OFF asks apps to name themselves. Browsers don't allow setting it, so web
  /// sends none (OFF still answers).
  static const _userAgent = 'SilaFit/1.0 (+https://sila.fitness)';

  final http.Client _http;
  final DateTime Function() _now;

  /// Start times of recent lookups, oldest first. Shared by every instance:
  /// the limit is per device, not per screen.
  static final List<DateTime> _recent = [];

  /// Recent answers by barcode, so rescanning the same package (or a retry
  /// after a failed save) doesn't spend another call.
  static final Map<String, Map<String, dynamic>?> _answers = {};
  static const _maxAnswers = 50;

  /// The call in flight per barcode, so a double scan shares one request.
  static final Map<String, Future<Map<String, dynamic>?>> _inFlight = {};

  OpenFoodFactsClient({http.Client? httpClient, DateTime Function()? now})
      : _http = httpClient ?? http.Client(),
        _now = now ?? DateTime.now;

  /// The trimmed OFF v2 response (`{status, product}`) when OFF knows
  /// [barcode], ready to post to the server; null otherwise.
  Future<Map<String, dynamic>?> fetchProduct(String barcode) {
    if (_answers.containsKey(barcode)) {
      return Future.value(_answers[barcode]);
    }
    final pending = _inFlight[barcode];
    if (pending != null) return pending;
    if (!_takeSlot()) return Future.value(null);

    // Block body: whenComplete waits on a returned Future, and remove() would
    // return this very call - it would wait on itself forever.
    final call = _fetch(barcode).whenComplete(() {
      _inFlight.remove(barcode);
    });
    _inFlight[barcode] = call;
    return call;
  }

  /// Claims one of the [maxPerMinute] slots of the rolling minute.
  bool _takeSlot() {
    final now = _now();
    final cutoff = now.subtract(const Duration(minutes: 1));
    _recent.removeWhere((t) => !t.isAfter(cutoff));
    if (_recent.length >= maxPerMinute) return false;
    _recent.add(now);
    return true;
  }

  Future<Map<String, dynamic>?> _fetch(String barcode) async {
    final uri = Uri.parse('$_base${Uri.encodeComponent(barcode)}')
        .replace(queryParameters: {'fields': _fields});
    try {
      final response = await _http.get(uri, headers: {
        'Accept': 'application/json',
        if (!kIsWeb) 'User-Agent': _userAgent,
      }).timeout(timeout);

      // 404 / status 0 is a real "OFF doesn't know it" - worth remembering.
      // Anything else (429, 5xx) is a hiccup, so the next scan may try again.
      if (response.statusCode == 404) return _remember(barcode, null);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map<String, dynamic>) return null;
      final product = json['product'];
      if (json['status'] == 0 || product is! Map<String, dynamic>) {
        return _remember(barcode, null);
      }
      return _remember(barcode, {'status': 1, 'product': product});
    } catch (_) {
      // Offline, timed out, or a malformed body: the user adds it by hand.
      return null;
    }
  }

  static Map<String, dynamic>? _remember(
      String barcode, Map<String, dynamic>? answer) {
    if (_answers.length >= _maxAnswers) _answers.remove(_answers.keys.first);
    _answers[barcode] = answer;
    return answer;
  }

  /// Tests only.
  @visibleForTesting
  static void reset() {
    _recent.clear();
    _answers.clear();
    _inFlight.clear();
  }
}
