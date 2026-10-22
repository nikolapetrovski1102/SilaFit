/// Backend base URL. Supplied at build/run time via one of the checked-in
/// env files in `frontend/env/` - see that directory's README for which
/// file to pick per platform/target:
///   flutter run --dart-define-from-file=env/dev.json
///   flutter build ios --dart-define-from-file=env/prod.json
///
/// No default here on purpose: running without --dart-define-from-file
/// should fail loudly (a clear "cannot reach the server" from ApiClient)
/// rather than silently hitting some guessed address that only works on
/// one platform, per the flutter run gotcha in docs/starting-the-stack.md.
class ApiConfig {
  ApiConfig._();

  static const String baseUrl = String.fromEnvironment('API_BASE_URL');

  /// Google OAuth "Web application" client - this is the audience Google
  /// issues the ID token for (what the backend's `GoogleAuth:ClientIds`
  /// validates against) and what `GoogleSignIn.serverClientId` must be set
  /// to for `account.authentication.idToken` to actually populate on any
  /// platform, iOS included. See `frontend/env/README.md` for how it was
  /// created.
  static const String googleWebClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');

  /// Google OAuth "iOS" client - only consumed on iOS (`GoogleSignIn.clientId`),
  /// harmless to pass on other platforms. See `frontend/env/README.md`.
  static const String googleIosClientId =
      String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');

  /// Appodeal App Keys (Appodeal dashboard -> the app -> App Key), one per
  /// store app. Left empty, ads stay off entirely - see AdsService.
  static const String appodealIosKey =
      String.fromEnvironment('APPODEAL_IOS_KEY');
  static const String appodealAndroidKey =
      String.fromEnvironment('APPODEAL_ANDROID_KEY');

  /// Unity LevelPlay App Keys and ad unit ids (Unity dashboard -> LevelPlay
  /// -> the app), one set per store app. An empty App Key leaves LevelPlay
  /// off and Appodeal serves alone; an empty unit id turns off that format.
  static const String levelPlayIosAppKey =
      String.fromEnvironment('LEVELPLAY_IOS_APP_KEY');
  static const String levelPlayAndroidAppKey =
      String.fromEnvironment('LEVELPLAY_ANDROID_APP_KEY');
  static const String levelPlayIosInterstitialUnit =
      String.fromEnvironment('LEVELPLAY_IOS_INTERSTITIAL_UNIT');
  static const String levelPlayAndroidInterstitialUnit =
      String.fromEnvironment('LEVELPLAY_ANDROID_INTERSTITIAL_UNIT');
  static const String levelPlayIosRewardedUnit =
      String.fromEnvironment('LEVELPLAY_IOS_REWARDED_UNIT');
  static const String levelPlayAndroidRewardedUnit =
      String.fromEnvironment('LEVELPLAY_ANDROID_REWARDED_UNIT');
}
