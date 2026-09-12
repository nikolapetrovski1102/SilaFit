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
/// SharedPreferences directly - that's the "shared method, no duplicates"
/// rule applied to persistence.
class SessionStore {
  static const _deviceIdKey = 'silen.device_id';
  static const _tokenKey = 'silen.token';
  static const _userIdKey = 'silen.user_id';
  static const _tierKey = 'silen.tier';
  static const _emailKey = 'silen.email';
  static const _displayNameKey = 'silen.display_name';
  static const _onboardingCompleteKey = 'silen.onboarding_complete';
  static const _appearanceModeKey = 'silen.appearance_mode';

  SilenSession? _session;
  String? _deviceId;
  bool _hasCompletedOnboarding = false;
  String? _cachedAppearanceMode;

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

  /// Loads the persisted device id (creating one on first launch) and any
  /// saved session. Call once at app startup before reading [current].
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();

    _deviceId = prefs.getString(_deviceIdKey);
    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString(_deviceIdKey, _deviceId!);
    }

    _hasCompletedOnboarding = prefs.getBool(_onboardingCompleteKey) ?? false;
    _cachedAppearanceMode = prefs.getString(_appearanceModeKey);

    final token = prefs.getString(_tokenKey);
    final userId = prefs.getString(_userIdKey);
    final tier = prefs.getString(_tierKey);
    if (token != null && userId != null && tier != null) {
      _session = SilenSession(
        token: token,
        userId: userId,
        accountTier: tier,
        email: prefs.getString(_emailKey),
        displayName: prefs.getString(_displayNameKey),
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.token);
    await prefs.setString(_userIdKey, session.userId);
    await prefs.setString(_tierKey, session.accountTier);
    if (session.email != null) {
      await prefs.setString(_emailKey, session.email!);
    } else {
      await prefs.remove(_emailKey);
    }
    if (session.displayName != null) {
      await prefs.setString(_displayNameKey, session.displayName!);
    } else {
      await prefs.remove(_displayNameKey);
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

  Future<void> clear() async {
    _session = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_tierKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_displayNameKey);
  }
}
