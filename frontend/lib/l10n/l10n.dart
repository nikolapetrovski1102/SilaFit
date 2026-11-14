import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mk.dart';

/// The app's UI language.
///
/// Strings are looked up by their English source text ("gettext style"):
/// `tr('Save')` returns the Macedonian entry from [mkStrings] when the app
/// runs in Macedonian, and the English text itself otherwise - so a string
/// that has no translation yet still shows, in English, rather than a key.
///
/// Content that comes from the server (exercise names, meals, foods, split
/// and plan names the user or a trainer typed) deliberately stays as sent
/// and is never passed through [tr].
///
/// Changing the language marks every element dirty (see the [locale]
/// listener in `main.dart`), which re-runs every `build` and so every [tr]
/// call - widgets don't need to listen for it. State is kept, so strings
/// cached in a `State` field outside `build` won't update until rebuilt.
class L10n {
  L10n._();

  static const english = 'en';
  static const macedonian = 'mk';

  /// The stored choice: [english], [macedonian], or this for "follow the
  /// phone's language".
  static const system = 'system';

  static const supportedLocales = [Locale(english), Locale(macedonian)];

  static const _prefsKey = 'silen.language';

  /// The resolved language the UI is drawn in.
  static final ValueNotifier<Locale> locale =
      ValueNotifier(const Locale(english));

  static String _preference = system;

  /// What the user picked in Settings ([system], [english] or [macedonian]).
  static String get preference => _preference;

  static bool get isMacedonian => locale.value.languageCode == macedonian;

  /// The language code sent to the API as `Accept-Language`.
  static String get languageCode => locale.value.languageCode;

  /// Reads the saved preference and resolves it before the first frame, so
  /// a Macedonian user never sees an English flash on cold start.
  static Future<void> init() async {
    await initializeDateFormatting(english);
    await initializeDateFormatting(macedonian);
    try {
      final prefs = await SharedPreferences.getInstance();
      _preference = prefs.getString(_prefsKey) ?? system;
    } catch (_) {
      _preference = system;
    }
    _apply();
  }

  /// Saves and applies a new preference ([system], [english], [macedonian]).
  static Future<void> setPreference(String value) async {
    _preference = value;
    _apply();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, value);
  }

  /// Re-resolves [system] when the phone's language changes while the app
  /// is running.
  static void onDeviceLocalesChanged() {
    if (_preference == system) _apply();
  }

  static void _apply() {
    final code = switch (_preference) {
      english => english,
      macedonian => macedonian,
      _ => _deviceLanguage(),
    };
    Intl.defaultLocale = code;
    if (locale.value.languageCode != code) locale.value = Locale(code);
  }

  static String _deviceLanguage() {
    final device = PlatformDispatcher.instance.locales;
    for (final l in device) {
      if (l.languageCode == macedonian) return macedonian;
      if (l.languageCode == english) return english;
    }
    return english;
  }

  static Map<String, String> get _table =>
      isMacedonian ? mkStrings : const {};

  /// Plural category for [n] in the current language: Macedonian uses the
  /// singular form for 1, 21, 31... (but not 11); English only for 1.
  static bool _isOne(num n) {
    if (n != n.truncate()) return false;
    final i = n.toInt().abs();
    if (isMacedonian) return i % 10 == 1 && i % 100 != 11;
    return i == 1;
  }
}

/// Translates [en] into the current UI language. `{name}` placeholders are
/// filled from [args].
String tr(String en, [Map<String, Object?> args = const {}]) {
  var s = L10n._table[en] ?? en;
  if (args.isNotEmpty) {
    args.forEach((k, v) => s = s.replaceAll('{$k}', '${v ?? ''}'));
  }
  return s;
}

/// Picks [one] or [other] for the count [n] and translates it; `{n}` in
/// either form is replaced with [n] (plus any other [args]).
String trPlural(num n, String one, String other,
    [Map<String, Object?> args = const {}]) {
  return tr(L10n._isOne(n) ? one : other, {'n': n, ...args});
}
