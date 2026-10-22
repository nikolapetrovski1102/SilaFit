import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:silafit/core/api/api_client.dart';
import 'package:silafit/core/api/api_exception.dart';
import 'package:silafit/core/session/session_store.dart';
import 'package:silafit/core/state/resource_state.dart';
import 'package:silafit/features/splits/splits_controller.dart';
import 'package:silafit/features/splits/splits_models.dart';
import 'package:silafit/features/splits/splits_repository.dart';

/// The network answers only when [network] is completed; the saved copy is
/// [saved], straight away.
class _SlowSplits extends SplitsRepository {
  _SlowSplits(this.saved) : super(ApiClient(sessionStore: SessionStore()));

  final List<WorkoutSplit>? saved;
  final network = Completer<List<WorkoutSplit>>();

  @override
  Future<List<WorkoutSplit>?> getCachedAll() async => saved;

  @override
  Future<List<WorkoutSplit>> getAll() => network.future;
}

void main() {
  test('a screen shows its saved copy while the request is still out',
      () async {
    final repo = _SlowSplits(const []);
    final controller = SplitsController(repo);
    final load = controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(controller.state.hasData, isTrue);
    expect(controller.state.isLoading, isFalse);

    repo.network.completeError(const ApiException('Locked', statusCode: 403));
    await load;
    // A real refusal still wins over the saved copy.
    expect(controller.state.error, 'Locked');
    expect(controller.requiresUpgrade, isTrue);
  });

  test('a saved copy that turns up after the answer is ignored', () async {
    final saved = Completer<String?>();
    final painted = <String>[];
    final result = await fetchPaintingCached<String>(
      cached: () => saved.future,
      fetch: () async => 'fresh',
      paint: painted.add,
    );
    saved.complete('old');
    await Future<void>.delayed(Duration.zero);
    expect(result, 'fresh');
    expect(painted, isEmpty);
  });
}
