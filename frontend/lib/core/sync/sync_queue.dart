import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';

/// One write that couldn't reach the server, kept on the phone until it can.
///
/// Every endpoint queued through here is safe to replay: workout completion
/// replaces the session's sets, bodyweight and meals carry a client-generated
/// id the server deduplicates on, and deleting a meal that's already gone is
/// a no-op. That matters because a request that timed out may well have
/// landed - the queue can't know, so it sends it again.
class PendingWrite {
  final String id;

  /// What this write is, so screens can overlay it on data that doesn't
  /// include it yet - one of the `SyncQueue.kind*` constants.
  final String kind;
  final String method; // POST | PUT | DELETE
  final String path;
  final Map<String, dynamic>? body;

  /// The workout session, meal or bodyweight entry the write is about.
  final String? entityId;
  final DateTime createdAtUtc;

  /// How many times the server answered this write with a 5xx.
  final int serverErrors;

  /// How many of those came in a run where another write got through - the
  /// server was fine, it's this write it can't handle. See
  /// [SyncQueue.maxStrikes].
  final int strikes;

  const PendingWrite({
    required this.id,
    required this.kind,
    required this.method,
    required this.path,
    this.body,
    this.entityId,
    required this.createdAtUtc,
    this.serverErrors = 0,
    this.strikes = 0,
  });

  factory PendingWrite.create({
    required String kind,
    required String method,
    required String path,
    Map<String, dynamic>? body,
    String? entityId,
  }) =>
      PendingWrite(
        id: const Uuid().v4(),
        kind: kind,
        method: method,
        path: path,
        body: body,
        entityId: entityId,
        createdAtUtc: DateTime.now().toUtc(),
      );

  PendingWrite _refused({required bool struck}) => PendingWrite(
        id: id,
        kind: kind,
        method: method,
        path: path,
        body: body,
        entityId: entityId,
        createdAtUtc: createdAtUtc,
        serverErrors: serverErrors + 1,
        strikes: strikes + (struck ? 1 : 0),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'method': method,
        'path': path,
        if (body != null) 'body': body,
        if (entityId != null) 'entityId': entityId,
        'createdAtUtc': createdAtUtc.toIso8601String(),
        if (serverErrors > 0) 'serverErrors': serverErrors,
        if (strikes > 0) 'strikes': strikes,
      };

  factory PendingWrite.fromJson(Map<String, dynamic> json) => PendingWrite(
        id: json['id'] as String,
        kind: json['kind'] as String,
        method: json['method'] as String,
        path: json['path'] as String,
        body: (json['body'] as Map?)?.cast<String, dynamic>(),
        entityId: json['entityId'] as String?,
        createdAtUtc: DateTime.parse(json['createdAtUtc'] as String),
        serverErrors: json['serverErrors'] as int? ?? 0,
        strikes: json['strikes'] as int? ?? 0,
      );
}

/// The phone-side outbox for writes made with no signal - a workout finished
/// in a basement gym, a meal logged on the train. Persisted per user in
/// `shared_preferences` (the same store the active-workout draft lives in),
/// so it survives the app being killed, and replayed in order as soon as the
/// server answers again.
///
/// Replay rules: a 2xx removes the write. No connection stops the run and
/// keeps everything for the next attempt. A 5xx keeps the write and holds
/// back later writes for the same meal/session/entry (order matters - an
/// edit must never land before the meal it edits), but lets writes for
/// anything else through, so one write the server chokes on can't wedge the
/// whole queue; a second 5xx in the same run means the server itself is
/// down, and stops it. Any other refusal (a 4xx) is dropped, since resending
/// it would only be refused again, and reported through [droppedMessage] -
/// as is a write the server keeps failing on (see [maxStrikes]).
class SyncQueue {
  static const kindWorkoutComplete = 'workout.complete';
  static const kindBodyweight = 'bodyweight.log';
  static const kindMealUpsert = 'meal.upsert';
  static const kindMealDelete = 'meal.delete';

  /// How often a non-empty queue retries on its own, on top of the explicit
  /// triggers (app start, resume, the connection coming back).
  static const retryInterval = Duration(seconds: 30);

  /// A write that 5xx'd in this many runs where other writes got through is
  /// one the server can't handle - dropped and reported rather than retried
  /// for ever.
  static const maxStrikes = 5;

  /// Backstop for a write that keeps 5xx'ing with nothing else queued to
  /// tell a broken write from a broken server: dropped after this many
  /// tries, once it's also older than [maxServerErrorAge]. Long enough that
  /// no real outage loses a workout.
  static const maxServerErrors = 20;
  static const maxServerErrorAge = Duration(days: 7);

  static const _keyPrefix = 'silen.sync_queue.';

  final ApiClient _api;

  /// How many writes are waiting - drives the offline pill's count.
  final ValueNotifier<int> pendingCount = ValueNotifier(0);

  /// Bumped after a replay run uploads at least one write, so screens holding
  /// data with queued writes overlaid can re-fetch the real thing.
  final ValueNotifier<int> syncedVersion = ValueNotifier(0);

  /// The server's message for the most recent write it refused on replay.
  final ValueNotifier<String?> droppedMessage = ValueNotifier(null);

  List<PendingWrite> _writes = const [];
  String? _loadedFor;
  Future<void>? _loading;
  Future<void>? _flushing;
  Timer? _timer;
  bool _wasOffline = false;

  SyncQueue(this._api);

  String get _userId => _api.sessionStore.current?.userId ?? 'anonymous';

  /// Writes waiting for the signed-in user, oldest first. Only meaningful
  /// after [ready] - before that it's empty.
  List<PendingWrite> get pending =>
      _loadedFor == _userId ? List.unmodifiable(_writes) : const [];

  /// Loads the signed-in user's queue from disk if it isn't already.
  Future<void> ready() async {
    if (_loadedFor == _userId) return;
    await (_loading ??= _load().whenComplete(() => _loading = null));
    // The account changed while that load was running - load theirs.
    if (_loadedFor != _userId) await ready();
  }

  Future<void> _load() async {
    final userId = _userId;
    var writes = <PendingWrite>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_keyPrefix$userId');
      if (raw != null) {
        writes = (jsonDecode(raw) as List)
            .map((e) => PendingWrite.fromJson((e as Map).cast()))
            .toList();
      }
    } catch (_) {
      // A corrupt queue is unrecoverable either way - start empty rather
      // than wedging every future write behind it.
    }
    _writes = writes;
    _loadedFor = userId;
    pendingCount.value = writes.length;
  }

  Future<void> _persist() async {
    final userId = _loadedFor;
    if (userId == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      if (_writes.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(
            key, jsonEncode([for (final w in _writes) w.toJson()]));
      }
    } catch (_) {}
  }

  /// Queues [write] for upload. A workout completion replaces any earlier
  /// queued completion of the same session - only the final version of a
  /// workout is worth sending.
  Future<void> enqueue(PendingWrite write) async {
    await ready();
    _writes = [
      for (final w in _writes)
        if (!(write.kind == kindWorkoutComplete &&
            w.kind == kindWorkoutComplete &&
            w.entityId == write.entityId))
          w,
      write,
    ];
    pendingCount.value = _writes.length;
    await _persist();
  }

  /// Uploads queued writes in order until one can't get through. Concurrent
  /// calls share the run in progress. Returns how many were uploaded.
  Future<int> flush() async {
    if (_flushing != null) {
      await _flushing;
      return 0;
    }
    var uploaded = 0;
    final run = () async {
      await ready();
      // Nothing to upload without an account to upload it as.
      if (_api.sessionStore.current == null) return;
      final tried = <String>{};
      // Entities with a write held back this run - later writes for them
      // have to wait behind it.
      final heldBack = <String>{};
      final refused = <String, String>{}; // write id -> the server's message
      while (true) {
        PendingWrite? write;
        for (final w in _writes) {
          if (tried.contains(w.id) || heldBack.contains(w.entityId)) continue;
          write = w;
          break;
        }
        if (write == null) break;
        tried.add(write.id);
        try {
          await _send(write);
          uploaded++;
        } on ApiException catch (e) {
          if (e.isRetryable && !e.isNetworkError) {
            refused[write.id] = e.userMessage;
            // A write about nothing in particular can't be told apart from
            // what follows it, and a second refusal means the server's down
            // rather than this write - either way, stop here.
            if (write.entityId == null || refused.length > 1) break;
            heldBack.add(write.entityId!);
            continue;
          }
          if (e.isRetryable || e.isUnauthorized) break;
          droppedMessage.value = e.userMessage;
        } catch (_) {
          // Not an API answer (a bug, a bad stored body) - retrying won't
          // change it, so it must not block everything queued behind it.
          droppedMessage.value = ApiException.genericMessage;
        }
        // Remove by identity - an enqueue during the await may have
        // replaced the list.
        _writes = [
          for (final w in _writes)
            if (w.id != write.id) w
        ];
        pendingCount.value = _writes.length;
        await _persist();
      }
      if (refused.isNotEmpty) {
        await _recordRefusals(refused,
            struck: uploaded > 0 && refused.length == 1);
      }
    }();
    _flushing = run;
    try {
      await run;
    } finally {
      _flushing = null;
    }
    if (uploaded > 0) syncedVersion.value++;
    return uploaded;
  }

  /// Counts this run's 5xx answers against their writes, and drops any write
  /// that has now failed too often to be worth keeping (see [maxStrikes]).
  Future<void> _recordRefusals(Map<String, String> refused,
      {required bool struck}) async {
    final now = DateTime.now().toUtc();
    final kept = <PendingWrite>[];
    for (final w in _writes) {
      final message = refused[w.id];
      if (message == null) {
        kept.add(w);
        continue;
      }
      final counted = w._refused(struck: struck);
      final givenUp = counted.strikes >= maxStrikes ||
          (counted.serverErrors >= maxServerErrors &&
              now.difference(counted.createdAtUtc) >= maxServerErrorAge);
      if (givenUp) {
        droppedMessage.value = message;
      } else {
        kept.add(counted);
      }
    }
    _writes = kept;
    pendingCount.value = _writes.length;
    await _persist();
  }

  Future<void> _send(PendingWrite write) {
    switch (write.method) {
      case 'POST':
        return _api.post(write.path, (_) => null, body: write.body);
      case 'PUT':
        return _api.put(write.path, (_) => null, body: write.body);
      case 'DELETE':
        return _api.delete(write.path, (_) => null, body: write.body);
      default:
        throw StateError('Unsupported queued method ${write.method}');
    }
  }

  /// Starts the automatic retries: right away, whenever the connection comes
  /// back (any request getting through flips [ApiClient.isOffline]), and on
  /// a timer while anything is waiting. Idempotent.
  void start() {
    if (_timer != null) return;
    _wasOffline = _api.isOffline.value;
    _api.isOffline.addListener(_onConnectivity);
    _timer = Timer.periodic(retryInterval, (_) {
      if (pendingCount.value > 0) unawaited(flush());
    });
    unawaited(flush());
  }

  void _onConnectivity() {
    final offline = _api.isOffline.value;
    if (_wasOffline && !offline && pendingCount.value > 0) unawaited(flush());
    _wasOffline = offline;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _api.isOffline.removeListener(_onConnectivity);
  }

  /// Forgets every queued write for every account - part of sign-out's
  /// local wipe, alongside the response cache and the workout draft.
  Future<void> clear() async {
    _writes = const [];
    pendingCount.value = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith(_keyPrefix)) await prefs.remove(key);
      }
    } catch (_) {}
    _loadedFor = null;
  }
}
