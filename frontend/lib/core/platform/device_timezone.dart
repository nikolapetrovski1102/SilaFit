import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Best-effort device timezone identifier with no extra native dependency.
///
/// Dart exposes only an abbreviation via `DateTime.timeZoneName` (e.g. "CEST")
/// and an offset via `DateTime.timeZoneOffset` - not an IANA id - so this sends
/// a fixed UTC offset ("+02:00", "-05:00"). The backend accepts offsets and IANA
/// ids interchangeably (see `UserTimeZoneResolver`), which is enough to schedule
/// reminders on the user's own clock. The value is refreshed on every app open
/// and opt-in, so a DST transition corrects itself the next time the app runs.
String deviceTimeZoneId() {
  final offset = DateTime.now().timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absolute = offset.abs();
  final hours = absolute.inHours.toString().padLeft(2, '0');
  final minutes = (absolute.inMinutes % 60).toString().padLeft(2, '0');
  return '$sign$hours:$minutes';
}

/// The platform token registered alongside the FCM device token, so the server
/// can tell phone from tablet when fanning a notification out to several.
String devicePlatform() {
  if (kIsWeb) return 'web';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return 'unknown';
}
