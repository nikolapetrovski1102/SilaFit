import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// One cached GET payload - the envelope's `data`, exactly as the server sent
/// it, plus when it was stored.
class CachedPayload {
  final dynamic data;
  final DateTime savedAtUtc;

  const CachedPayload(this.data, this.savedAtUtc);
}

/// Last-known-good copy of opted-in GET responses, kept on disk so the app
/// still has something to show when a gym has no signal - including after
/// the OS killed the app between sets and it cold-starts offline.
///
/// One small JSON file per (user, path, query), named by a hash so paths and
/// query strings never have to be filename-safe. Lives in the app-support
/// directory rather than the cache directory, which iOS may purge exactly
/// when storage is tight. Every failure here is swallowed: the cache is an
/// optimisation, never a reason for a request to fail.
class ResponseCache {
  final Future<Directory> Function() _directory;
  final Map<String, CachedPayload> _memory = {};
  Directory? _resolved;

  ResponseCache({Future<Directory> Function()? directory})
      : _directory = directory ??
            (() async => Directory(
                '${(await getApplicationSupportDirectory()).path}/api_cache'));

  /// Stable key for one user's view of one endpoint. Query parameters are
  /// sorted so `?a=1&b=2` and `?b=2&a=1` share an entry.
  static String keyFor(String userId, String path,
      [Map<String, String>? query]) {
    final params = (query?.entries.toList() ?? [])
      ..sort((a, b) => a.key.compareTo(b.key));
    final queryString = params.map((e) => '${e.key}=${e.value}').join('&');
    return sha1.convert(utf8.encode('$userId\n$path?$queryString')).toString();
  }

  Future<CachedPayload?> read(String key) async {
    final inMemory = _memory[key];
    if (inMemory != null) return inMemory;
    try {
      final file = File('${(await _dir()).path}/$key.json');
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final payload = CachedPayload(
          json['data'], DateTime.parse(json['savedAtUtc'] as String));
      _memory[key] = payload;
      return payload;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, dynamic data) async {
    final payload = CachedPayload(data, DateTime.now().toUtc());
    _memory[key] = payload;
    try {
      final dir = await _dir();
      await dir.create(recursive: true);
      // Write-then-rename so a kill mid-write never leaves a torn file
      // behind for the next offline cold start to choke on.
      final tmp = File('${dir.path}/$key.json.tmp');
      await tmp.writeAsString(jsonEncode({
        'savedAtUtc': payload.savedAtUtc.toIso8601String(),
        'data': data,
      }));
      await tmp.rename('${dir.path}/$key.json');
    } catch (_) {}
  }

  /// Drops every entry for every user - run on sign-out/account deletion
  /// alongside the other per-user local caches.
  Future<void> clear() async {
    _memory.clear();
    try {
      final dir = await _dir();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  Future<Directory> _dir() async => _resolved ??= await _directory();
}
