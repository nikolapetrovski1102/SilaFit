import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/features/auth/auth_controller.dart';
import 'package:silafit/features/auth/auth_repository.dart';
import 'package:silafit/features/today/active_workout_draft_store.dart';
import 'package:silafit/features/today/exercise_memory_store.dart';

/// Records the logout plumbing without touching secure storage. `signOut` is
/// the fix under test - `logout` must go through it (not the session-only
/// `clear`) or device login signs the same account straight back in.
class RecordingSessionStore extends SessionStore {
  int signOutCalls = 0;

  @override
  Future<void> signOut() async {
    signOutCalls++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('signOut drops the session and rotates the device id', () async {
    FlutterSecureStorage.setMockInitialValues({
      'silen.device_id': 'device-old',
      'silen.token': 'token-1',
      'silen.user_id': 'user-1',
      'silen.tier': 'Registered',
      'silen.email': 'ada@example.com',
      'silen.display_name': 'Ada',
    });
    SharedPreferences.setMockInitialValues({'silen.appearance_mode': 'Dark'});

    final store = SessionStore();
    await store.restore();
    expect(store.current, isNotNull);
    expect(store.isRegistered, isTrue);
    expect(store.cachedAppearanceMode, 'Dark');
    expect(await store.deviceId(), 'device-old');

    await store.signOut();

    expect(store.current, isNull);
    expect(store.isRegistered, isFalse);
    expect(store.cachedAppearanceMode, isNull);

    // A brand-new device id means the next bootstrap device login cannot
    // resolve back to the account that owned the old one.
    final newDeviceId = await store.deviceId();
    expect(newDeviceId, isNot('device-old'));
    expect(newDeviceId, isNotEmpty);
  });

  test('clear only drops the session and keeps the device identity', () async {
    FlutterSecureStorage.setMockInitialValues({
      'silen.device_id': 'device-old',
      'silen.token': 'token-1',
      'silen.user_id': 'user-1',
      'silen.tier': 'Registered',
    });

    final store = SessionStore();
    await store.restore();
    await store.clear();

    expect(store.current, isNull);
    // The API client's dead-token path must not rotate the device.
    expect(await store.deviceId(), 'device-old');
  });

  test('logout signs out through the session store before reloading',
      () async {
    final sessionStore = RecordingSessionStore();
    var reloadCount = 0;
    final controller = AuthController(
      AuthRepository(ApiClient(sessionStore: sessionStore)),
      sessionStore,
      onReload: () async => reloadCount++,
    );

    await controller.logout();

    expect(sessionStore.signOutCalls, 1);
    expect(reloadCount, 1);
  });

  test('exercise memory is cleared, not carried into the next account',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = ExerciseMemoryStore.instance;
    await store.remember('ex-1', 100, 5);
    expect(await store.loadAll(), isNotEmpty);

    await store.clear();

    expect(await store.loadAll(), isEmpty);
  });

  test('active workout draft is cleared on sign-out', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ActiveWorkoutDraftStore.instance;
    final now = DateTime.now().toUtc();
    await store.save(ActiveWorkoutDraft(
      workoutSessionId: 'session-1',
      exerciseIndex: 0,
      setsByExercise: const [[]],
      exercises: const [],
      startedAtUtc: now,
      savedAtUtc: now,
    ));
    expect(await store.load('session-1'), isNotNull);

    await store.clear();

    expect(await store.load('session-1'), isNull);
  });
}
