import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// The account tier the backend hands back on every auth response. Kept as
/// a string enum mirroring `Silen.Common.Enums.AccountTier` exactly.
class AccountTier {
  static const guest = 'Guest';
  static const registered = 'Registered';
}

/// A logged-in session snapshot, mirroring `AuthResultDto`.
class SilenSession {
  final String token;
  final String userId;
  final String accountTier;
  final String? email;
  final String? displayName;

  const SilenSession({
    required this.token,
    required this.userId,
    required this.accountTier,
    this.email,
    this.displayName,
  });

  bool get isRegistered => accountTier == AccountTier.registered;
}

/// Single source of truth for the device id and the current auth session.
/// Every feature reads/writes through this instead of touching
/// SharedPreferences/secure storage directly - that's the "shared method, no
/// duplicates" rule applied to persistence.
///
/// The token, device id, email, and display name are the sensitive half of
/// this state, so they live in [FlutterSecureStorage] (iOS Keychain /
/// Android Keystore-backed EncryptedSharedPreferences) instead of plain
/// SharedPreferences - readable off a rooted/jailbroken device or an
/// unencrypted backup otherwise. The onboarding flag and cached appearance
/// mode aren't sensitive and stay in plain SharedPreferences.
class SessionStore {
  static const _deviceIdKey = 'silen.device_id';
  static const _tokenKey = 'silen.token';
  static const _userIdKey = 'silen.user_id';
  static const _tierKey = 'silen.tier';
  static const _emailKey = 'silen.email';
  static const _displayNameKey = 'silen.display_name';
  static const _onboardingCompleteKey = 'silen.onboarding_complete';
  static const _appearanceModeKey = 'silen.appearance_mode';
  static const _featureTourCompleteKey = 'silen.feature_tour_complete';

  // encryptedSharedPreferences wraps the Android prefs file with a
  // Keystore-backed AES key (requires API 23+, see android/app/build.gradle.kts).
  // iOS defaults to a Keychain item that is not iCloud-synchronized, so it
  // never leaves the device via iCloud Keychain.
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  SilenSession? _session;
  String? _deviceId;
  bool _hasCompletedOnboarding = false;
  String? _cachedAppearanceMode;
  bool _hasCompletedFeatureTour = false;

  SilenSession? get current => _session;
  String? get currentToken => _session?.token;
  bool get isRegistered => _session?.isRegistered ?? false;

  /// Whether the first-launch onboarding flow (intro slides through the
  /// notification-permission screen) has already run on this device.
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;

  /// The last-known `UserSettings.appearanceMode` ('Dark'/'Light'/'Device'), read
  /// synchronously from the in-memory cache. Lets the app paint the right
  /// theme on cold start before `SettingsController.load()`'s network call
  /// has a chance to resolve - null only on a genuinely first-ever launch.
  String? get cachedAppearanceMode => _cachedAppearanceMode;

  /// Whether the post-onboarding feature tour has already been shown.
  bool get hasCompletedFeatureTour => _hasCompletedFeatureTour;

  /// Loads the persisted device id (creating one on first launch) and any
  /// saved session. Call once at app startup before reading [current].
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();

    _deviceId = await _secureStorage.read(key: _deviceIdKey);
    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await _secureStorage.write(key: _deviceIdKey, value: _deviceId!);
    }

    _hasCompletedOnboarding = prefs.getBool(_onboardingCompleteKey) ?? false;
    _cachedAppearanceMode = prefs.getString(_appearanceModeKey);
    _hasCompletedFeatureTour =
        prefs.getBool(_featureTourCompleteKey) ?? false;

    final token = await _secureStorage.read(key: _tokenKey);
    final userId = await _secureStorage.read(key: _userIdKey);
    final tier = await _secureStorage.read(key: _tierKey);
    if (token != null && userId != null && tier != null) {
      _session = SilenSession(
        token: token,
        userId: userId,
        accountTier: tier,
        email: await _secureStorage.read(key: _emailKey),
        displayName: await _secureStorage.read(key: _displayNameKey),
      );
    }
  }

  Future<String> deviceId() async {
    if (_deviceId != null) return _deviceId!;
    await restore();
    return _deviceId!;
  }

  Future<void> save(SilenSession session) async {
    _session = session;
    await _secureStorage.write(key: _tokenKey, value: session.token);
    await _secureStorage.write(key: _userIdKey, value: session.userId);
    await _secureStorage.write(key: _tierKey, value: session.accountTier);
    if (session.email != null) {
      await _secureStorage.write(key: _emailKey, value: session.email!);
    } else {
      await _secureStorage.delete(key: _emailKey);
    }
    if (session.displayName != null) {
      await _secureStorage.write(
          key: _displayNameKey, value: session.displayName!);
    } else {
      await _secureStorage.delete(key: _displayNameKey);
    }
  }

  /// Marks the onboarding flow as done so it never shows again on this
  /// device, regardless of which exit path (finish, skip, or log in
  /// mid-flow) the user took.
  Future<void> markOnboardingComplete() => setOnboardingComplete(true);

  /// Sets the onboarding-complete flag directly. Used by
  /// [markOnboardingComplete] and by Settings' debug-only "replay
  /// onboarding" toggle, which flips it back to `false`.
  Future<void> setOnboardingComplete(bool value) async {
    _hasCompletedOnboarding = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompleteKey, value);
  }

  /// Persists the resolved appearance mode so the next cold start can read
  /// [cachedAppearanceMode] before any network call resolves.
  Future<void> cacheAppearanceMode(String mode) async {
    _cachedAppearanceMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_appearanceModeKey, mode);
  }

  /// Marks the feature tour as completed so it never shows again.
  /// Marks the feature tour as completed so it never shows again.
  Future<void> markFeatureTourComplete() => setFeatureTourComplete(true);

  /// Sets the feature-tour-complete flag directly.
  Future<void> setFeatureTourComplete(bool value) async {
    _hasCompletedFeatureTour = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_featureTourCompleteKey, value);
  }

  /// Resets both profile onboarding and feature tour flags for testing.
  Future<void> resetAllOnboarding() async {
    await setOnboardingComplete(false);
    await setFeatureTourComplete(false);
  }

  /// Clears the saved auth session only. Used by [ApiClient] when a request
  /// proves the token is dead; it deliberately leaves [deviceId] alone so a
  /// transient 401 can never cost the device its identity.
  Future<void> clear() async {
    _session = null;
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _userIdKey);
    await _secureStorage.delete(key: _tierKey);
    await _secureStorage.delete(key: _emailKey);
    await _secureStorage.delete(key: _displayNameKey);
  }

  /// Full sign-out: clears the session *and* rotates the device identity,
  /// plus the cached appearance preference that came from the outgoing
  /// account's settings.
  ///
  /// Deleting the token alone is not enough to sign anyone out. Device login
  /// (`POST /auth/device`) looks the device id up server-side and returns
  /// whichever account owns it, and linking email/Google/Apple upgrades that
  /// same row in place - so without rotating the device id,
  /// `AuthController.logout()` would silently sign the same user straight
  /// back in on the very next bootstrap. Dropping the id here means the next
  /// [restore]/bootstrap mints a brand-new guest instead.
  ///
  /// Distinct from [clear] on purpose: the API client's dead-token path must
  /// not rotate the device.
  Future<void> signOut() async {
    await clear();
    _deviceId = null;
    await _secureStorage.delete(key: _deviceIdKey);
    _cachedAppearanceMode = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_appearanceModeKey);
  }
}
