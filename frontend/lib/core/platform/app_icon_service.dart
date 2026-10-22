import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// The home-screen icon the user picked in Settings. [dark] is the default
/// every install starts on; [light] is the alternate.
enum AppIconChoice {
  dark('Dark', 'Dark', 'assets/branding/app_icon_dark.png'),
  light('Light', 'Light', 'assets/branding/app_icon_light.png');

  /// Wire value on the native channel.
  final String value;
  final String label;

  /// Full-size artwork the picker previews.
  final String previewAsset;

  const AppIconChoice(this.value, this.label, this.previewAsset);

  static AppIconChoice fromValue(String? value) =>
      value == light.value ? light : dark;
}

/// Switches the launcher icon through the `com.nikolapetrovski.silafit/app_icon`
/// channel - ios/SilaFit/AppIconPlugin.swift (alternate icon sets) and
/// android/.../AppIconSwitcher.kt (launcher activity-aliases). The OS keeps
/// the choice itself, so nothing is stored on this side.
class AppIconService {
  static const _channel = MethodChannel('com.nikolapetrovski.silafit/app_icon');

  const AppIconService();

  /// Only the phone builds ship an alternate icon.
  bool get isSupported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  /// The icon currently on the home screen, or null when unsupported or the
  /// native side can't say.
  Future<AppIconChoice?> current() async {
    if (!isSupported) return null;
    try {
      return AppIconChoice.fromValue(
          await _channel.invokeMethod<String>('current'));
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Applies [choice]; resolves to whether the OS accepted it.
  Future<bool> set(AppIconChoice choice) async {
    if (!isSupported) return false;
    try {
      return await _channel
              .invokeMethod<bool>('set', {'icon': choice.value}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
