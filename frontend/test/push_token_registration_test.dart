import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/features/notifications/notifications_repository.dart';
import 'package:silafit/features/notifications/push_messaging_service.dart';
import 'package:silafit/features/onboarding/onboarding_controller.dart';
import 'package:silafit/features/onboarding/onboarding_repository.dart';

/// Captures the body of every POST so the test can assert what the opt-in
/// actually stored. `parse` is still invoked so the repository's `void`
/// parsing path is exercised, not bypassed.
class PostRecordingClient extends ApiClient {
  final List<Map<String, dynamic>> posts = [];

  PostRecordingClient() : super(sessionStore: SessionStore());

  @override
  Future<T> post<T>(String path, T Function(dynamic json) parse,
      {Object? body}) async {
    posts.add({'path': path, 'body': body});
    return parse({'success': true, 'data': true});
  }
}

/// Stands in for the Firebase-backed service so no plugin/channel is touched.
class FakePushMessagingService extends PushMessagingService {
  FakePushMessagingService(super.repository, {this.token});

  final String? token;
  int requestTokenCalls = 0;

  @override
  Future<String?> requestToken() async {
    requestTokenCalls++;
    return token;
  }
}

void main() {
  test('granted permission stores the FCM token with the opt-in', () async {
    final client = PostRecordingClient();
    final notifications = NotificationsRepository(client);
    final push =
        FakePushMessagingService(notifications, token: 'fcm-token-123');
    final controller = OnboardingController(
      OnboardingRepository(client),
      notifications,
      autoAdvanceEnabled: false,
      pushMessaging: push,
    );
    addTearDown(controller.dispose);

    await controller.submitNotificationOptIn(true);

    expect(push.requestTokenCalls, 1);
    expect(client.posts, hasLength(1));
    expect(client.posts.single['path'], '/notifications/device-token');
    final body = client.posts.single['body'] as Map<String, dynamic>;
    expect(body['token'], 'fcm-token-123');
    expect(body['notificationsEnabled'], true);
    expect(body['platform'], isNotNull);
  });

  test('denied permission stores the opt-in without a token, no FCM ask',
      () async {
    final client = PostRecordingClient();
    final notifications = NotificationsRepository(client);
    final push =
        FakePushMessagingService(notifications, token: 'should-not-be-used');
    final controller = OnboardingController(
      OnboardingRepository(client),
      notifications,
      autoAdvanceEnabled: false,
      pushMessaging: push,
    );
    addTearDown(controller.dispose);

    await controller.submitNotificationOptIn(false);

    expect(push.requestTokenCalls, 0);
    final body = client.posts.single['body'] as Map<String, dynamic>;
    expect(body.containsKey('token'), isFalse);
    expect(body['notificationsEnabled'], false);
  });

  test('with no push service wired the opt-in still records', () async {
    final client = PostRecordingClient();
    final notifications = NotificationsRepository(client);
    final controller = OnboardingController(
      OnboardingRepository(client),
      notifications,
      autoAdvanceEnabled: false,
    );
    addTearDown(controller.dispose);

    await controller.submitNotificationOptIn(true);

    final body = client.posts.single['body'] as Map<String, dynamic>;
    expect(body.containsKey('token'), isFalse);
    expect(body['notificationsEnabled'], true);
  });
}
