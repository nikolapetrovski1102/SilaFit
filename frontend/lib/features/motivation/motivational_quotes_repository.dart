import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';

/// One motivational line for the splash screen.
class MotivationalQuote {
  final String text;
  final String? author;

  const MotivationalQuote(this.text, [this.author]);

  factory MotivationalQuote.fromJson(Map<String, dynamic> json) =>
      MotivationalQuote(
        (json['text'] as String? ?? '').trim(),
        (json['author'] as String?)?.trim(),
      );

  Map<String, dynamic> toJson() => {'text': text, 'author': author};

  static List<MotivationalQuote> listFromJson(dynamic json) => [
        for (final item in (json as List? ?? const []))
          if (item is Map<String, dynamic>) MotivationalQuote.fromJson(item),
      ].where((q) => q.text.isNotEmpty).toList();
}

/// The splash screen's motivational lines, from `GET /motivation/quotes`.
///
/// The splash can't wait on the network, so it always paints from the copy
/// saved on the device and refreshes that copy in the background for the
/// next launch. The copy lives in SharedPreferences rather than ApiClient's
/// response cache on purpose: that cache is keyed per user and wiped on
/// sign-out, while these lines are the same for everyone and are needed
/// before sign-in has even finished. A device that has never reached the
/// server (first launch, offline) falls back to [_bundled].
class MotivationalQuotesRepository {
  static const _prefsKey = 'splash_motivational_quotes_v1';

  /// Mirrors the seed in database/migrations/0018_motivational_quotes.sql.
  static const _bundled = [
    MotivationalQuote('Small steps every day add up to big results.'),
    MotivationalQuote("You don't have to be extreme, just consistent."),
    MotivationalQuote("The only bad workout is the one that didn't happen."),
    MotivationalQuote(
        'Discipline is choosing what you want most over what you want now.'),
    MotivationalQuote('Strong is built one rep at a time.'),
    MotivationalQuote('Show up today. Your future self is watching.'),
    MotivationalQuote('Progress, not perfection.'),
    MotivationalQuote(
        "Fuel your body like it's on your side - because it is."),
    MotivationalQuote('Rest is part of the plan, not a break from it.'),
    MotivationalQuote('Keep the streak alive. Keep the fire burning.'),
    MotivationalQuote('It never gets easier. You just get stronger.'),
    MotivationalQuote('Motivation gets you started. Habit keeps you going.'),
  ];

  final ApiClient _client;

  MotivationalQuotesRepository(this._client);

  /// The last set saved on the device, or the bundled set. Never throws and
  /// never touches the network.
  Future<List<MotivationalQuote>> cached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final saved = MotivationalQuote.listFromJson(jsonDecode(raw));
        if (saved.isNotEmpty) return saved;
      }
    } catch (_) {
      // A corrupt or unreadable copy just means the bundled lines this time.
    }
    return _bundled;
  }

  /// Fetches the current set and saves it for the next launch. Returns null
  /// when offline or the server has none active, leaving the saved copy as is.
  Future<List<MotivationalQuote>?> refresh() async {
    try {
      final fresh =
          await _client.get('/motivation/quotes', MotivationalQuote.listFromJson);
      if (fresh.isEmpty) return null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode([for (final q in fresh) q.toJson()]));
      return fresh;
    } catch (_) {
      return null;
    }
  }
}
