import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/services.dart';

/// Locks the screen against capture, through the
/// `com.nikolapetrovski.silafit/screen_security` channel. The whole app is
/// locked from the first frame ([lockApp], called from main.dart); trainer
/// documents also take their own hold so they stay locked regardless.
///
///
/// * Android sets `FLAG_SECURE` on the activity window (MainActivity.kt), so
///   screenshots and recordings come out black and the app switcher shows a
///   blank card.
/// * iOS (ios/SilaFit/ScreenSecurityPlugin.swift) renders the window inside a
///   secure text-entry layer, which the system leaves out of screenshots and
///   recordings, blacks the app out while the screen is being recorded or
///   mirrored, and reports any screenshot back here as `screenshotTaken`.
///
/// Calls nest: the lock stays on until every [enable] has been matched by a
/// [disable].
class ScreenSecurity {
  ScreenSecurity._();

  static const _channel =
      MethodChannel('com.nikolapetrovski.silafit/screen_security');

  static int _holders = 0;
  static final _screenshots = StreamController<void>.broadcast();
  static bool _listening = false;

  static bool get _supported =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// Fires when the user takes a screenshot while the lock is on (iOS reports
  /// it after the fact; Android blocks the capture outright).
  static Stream<void> get screenshots {
    _listen();
    return _screenshots.stream;
  }

  static void _listen() {
    if (_listening || !_supported) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'screenshotTaken') _screenshots.add(null);
    });
  }

  static bool _appLocked = false;

  /// Keeps the lock on for the rest of the run: screenshots, recordings and
  /// the app-switcher preview are blocked on every screen. Call once the first
  /// frame is up - iOS needs the key window to install its secure layer.
  /// Android also sets the flag natively in MainActivity.onCreate, so the
  /// splash and app-switcher card are covered before Dart runs.
  static Future<void> lockApp() async {
    if (_appLocked) return;
    _appLocked = true;
    await enable();
  }

  static bool? _dark;

  /// Keeps the capture shield (what screenshots and recordings show instead
  /// of the app, iOS only) in the app's current theme. Cheap to call on every
  /// build: it only crosses the channel when the brightness changes.
  static void setDarkAppearance(bool dark) {
    if (!_supported || !Platform.isIOS || _dark == dark) return;
    _dark = dark;
    _channel
        .invokeMethod<void>('appearance', {'dark': dark})
        .catchError((Object _) {});
  }

  static Future<void> enable() async {
    _holders++;
    if (_holders == 1) await _set(true);
  }

  static Future<void> disable() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) await _set(false);
  }

  static Future<void> _set(bool enabled) async {
    if (!_supported) return;
    _listen();
    try {
      final info =
          await _channel.invokeMethod<Object?>('secure', {'enabled': enabled});
      if (kDebugMode && info != null) debugPrint('ScreenSecurity: $info');
    } on PlatformException {
      // Best effort: the watermark still names whose copy it is.
    } on MissingPluginException {
      // Hot-restart before the native side is registered.
    }
  }
}
