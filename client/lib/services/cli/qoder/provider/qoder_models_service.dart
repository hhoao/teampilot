import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart';

import '../../../io/filesystem.dart';
import '../../../storage/home_storage.dart';
import 'qoder_auth_store.dart';

/// Account model catalog reported by an `initialize` + `session/new` probe.
@immutable
class QoderModelsSnapshot {
  const QoderModelsSnapshot({
    required this.modelIds,
    this.defaultModelId = '',
  });

  final List<String> modelIds;
  final String defaultModelId;
}

/// Runs one short-lived ACP handshake and returns the account's models.
typedef QoderAcpModelsOpener = Future<QoderModelsSnapshot?> Function({
  required String executable,
  required String configDir,
  required Duration timeout,
});

/// Parses `session/new` `models.availableModels` into ACP model ids.
///
/// Qoder's `--list-models` prints display names (`Qwen3.8-Max`), but
/// `session/set_model` only accepts the ids (`qwen3.8-max`, `smodel`,
/// `cmodel`), so the catalog must come from the ACP payload.
QoderModelsSnapshot? parseQoderModelsResponse(Object? result) {
  if (result is! Map) return null;
  final models = result['models'];
  if (models is! Map) return null;
  final available = models['availableModels'];
  if (available is! List) return null;
  final ids = <String>[];
  for (final entry in available) {
    if (entry is! Map) continue;
    final id = entry['modelId']?.toString().trim() ?? '';
    if (id.isEmpty || ids.contains(id)) continue;
    ids.add(id);
  }
  if (ids.isEmpty) return null;
  return QoderModelsSnapshot(
    modelIds: List<String>.unmodifiable(ids),
    defaultModelId: models['currentModelId']?.toString().trim() ?? '',
  );
}

class _ResolvedStorage {
  const _ResolvedStorage({required this.fs, required this.basePath});

  final Filesystem fs;
  final String basePath;
}

class QoderModelsCacheEntry {
  const QoderModelsCacheEntry({
    required this.fetchedAtMs,
    required this.modelIds,
    this.defaultModelId = '',
  });

  final int fetchedAtMs;
  final List<String> modelIds;
  final String defaultModelId;

  Map<String, Object?> toJson() => {
    'fetchedAtMs': fetchedAtMs,
    'modelIds': modelIds,
    if (defaultModelId.isNotEmpty) 'defaultModelId': defaultModelId,
  };

  factory QoderModelsCacheEntry.fromJson(Map<String, Object?> json) {
    final raw = json['modelIds'];
    return QoderModelsCacheEntry(
      fetchedAtMs: (json['fetchedAtMs'] as num?)?.toInt() ?? 0,
      modelIds: raw is List
          ? raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
          : const [],
      defaultModelId: json['defaultModelId']?.toString().trim() ?? '',
    );
  }
}

/// Fetches and caches Qoder account models for the provider pickers.
///
/// The probe seeds a throwaway config dir with the provider's `.auth` (or the
/// machine login), then reads `models.availableModels` from `session/new`.
/// Results are cached per provider in memory and on disk for six hours.
class QoderModelsService {
  QoderModelsService({
    HomeStorage? storage,
    @visibleForTesting Filesystem? fs,
    @visibleForTesting String? basePath,
    this.executable = 'qodercli',
    QoderAcpModelsOpener? opener,
    this.cacheTtl = const Duration(hours: 6),
    this.probeTimeout = const Duration(seconds: 20),
    this.machineHome,
  }) : _storage = storage,
       _fsOverride = fs,
       _basePathOverride = basePath?.trim(),
       _opener = opener ?? _defaultOpener;

  static const _globalCacheKey = '_global';

  final HomeStorage? _storage;
  final Filesystem? _fsOverride;
  final String? _basePathOverride;
  final String executable;
  final QoderAcpModelsOpener _opener;
  final Duration cacheTtl;
  final Duration probeTimeout;

  /// Test seam for the read-only machine login fallback.
  final String? machineHome;

  final Map<String, QoderModelsCacheEntry> _memory = {};
  final Map<String, Future<void>> _inFlight = {};
  final _CatalogUpdatesNotifier _catalogUpdates = _CatalogUpdatesNotifier();
  String? _lastBasePath;

  Listenable get catalogUpdates => _catalogUpdates;

  List<String> modelIdsFor({required String providerId}) {
    final entry = _memory[_cacheKey(providerId)];
    if (entry == null) return const [];
    return List<String>.unmodifiable(entry.modelIds);
  }

  String defaultModelIdFor({required String providerId}) =>
      _memory[_cacheKey(providerId)]?.defaultModelId.trim() ?? '';

  Future<void> ensureLoaded({
    required String providerId,
    String? executable,
    bool forceRefresh = false,
  }) {
    final key = _cacheKey(providerId);
    if (!forceRefresh && _isFresh(_memory[key])) return Future.value();
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final task = _load(
      key,
      providerId: providerId,
      executable: executable,
      forceRefresh: forceRefresh,
    ).whenComplete(() {
      _inFlight.remove(key);
    });
    _inFlight[key] = task;
    return task;
  }

  Future<void> _load(
    String cacheKey, {
    required String providerId,
    String? executable,
    bool forceRefresh = false,
  }) async {
    final roots = await _resolveStorage();
    final disk = forceRefresh ? null : await _readDiskCache(roots, cacheKey);
    if (disk != null && _isFresh(disk)) {
      _memory[cacheKey] = disk;
      _catalogUpdates.bump();
      return;
    }

    final fetched = await _fetchLive(
      roots,
      providerId: providerId,
      executable: executable,
    );
    if (fetched != null) {
      _memory[cacheKey] = fetched;
      await _writeDiskCache(roots, cacheKey, fetched);
      _catalogUpdates.bump();
      return;
    }

    if (disk != null && _memory[cacheKey] == null) {
      _memory[cacheKey] = disk;
      _catalogUpdates.bump();
    }
  }

  Future<QoderModelsCacheEntry?> _fetchLive(
    _ResolvedStorage roots, {
    required String providerId,
    String? executable,
  }) async {
    final configDir = roots.fs.pathContext.join(
      roots.basePath,
      'tmp',
      'qoder-models',
      _safeSegment(providerId),
    );
    final store = QoderAuthStore(
      fs: roots.fs,
      basePath: roots.basePath,
      pathContext: roots.fs.pathContext,
      machineHome: machineHome,
    );
    final seeded = await store.seedSessionAuth(
      providerId: providerId,
      sessionConfigDir: configDir,
    );
    if (!seeded) return null;

    final resolved = executable?.trim().isNotEmpty == true
        ? executable!.trim()
        : (this.executable.trim().isEmpty ? 'qodercli' : this.executable.trim());
    final snapshot = await _opener(
      executable: resolved,
      configDir: configDir,
      timeout: probeTimeout,
    );
    if (snapshot == null || snapshot.modelIds.isEmpty) return null;
    return QoderModelsCacheEntry(
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
      modelIds: snapshot.modelIds,
      defaultModelId: snapshot.defaultModelId,
    );
  }

  Future<_ResolvedStorage> _resolveStorage() async {
    final fs = _fsOverride;
    final basePath = _basePathOverride;
    if (fs != null && basePath != null) {
      _sync(basePath);
      return _ResolvedStorage(fs: fs, basePath: basePath);
    }
    final snapshot = _storage?.context;
    if (snapshot == null) {
      throw StateError('QoderModelsService needs storage or fs+basePath');
    }
    _sync(snapshot.teampilotRoot);
    return _ResolvedStorage(fs: snapshot.fs, basePath: snapshot.teampilotRoot);
  }

  void _sync(String basePath) {
    if (_lastBasePath != null && _lastBasePath != basePath) _memory.clear();
    _lastBasePath = basePath;
  }

  bool _isFresh(QoderModelsCacheEntry? entry) {
    if (entry == null || entry.modelIds.isEmpty) return false;
    final age = DateTime.now().millisecondsSinceEpoch - entry.fetchedAtMs;
    return age >= 0 && age < cacheTtl.inMilliseconds;
  }

  String _cacheKey(String providerId) {
    final trimmed = providerId.trim();
    return trimmed.isEmpty ? _globalCacheKey : trimmed;
  }

  String _cacheFilePath(_ResolvedStorage roots, String key) => roots.fs
      .pathContext
      .join(roots.basePath, 'cache', 'qoder_models', '$key.json');

  Future<QoderModelsCacheEntry?> _readDiskCache(
    _ResolvedStorage roots,
    String key,
  ) async {
    final path = _cacheFilePath(roots, key);
    if (!(await roots.fs.stat(path)).isFile) return null;
    final text = await roots.fs.readString(path);
    if (text == null || text.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return QoderModelsCacheEntry.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _writeDiskCache(
    _ResolvedStorage roots,
    String key,
    QoderModelsCacheEntry entry,
  ) async {
    final path = _cacheFilePath(roots, key);
    await roots.fs.ensureDir(roots.fs.pathContext.dirname(path));
    await roots.fs.writeString(path, jsonEncode(entry.toJson()));
  }

  static Future<QoderModelsSnapshot?> _defaultOpener({
    required String executable,
    required String configDir,
    required Duration timeout,
  }) async {
    Process? process;
    StreamSubscription<String>? lines;
    try {
      process = await Process.start(
        executable,
        const ['--acp'],
        environment: {
          ...Platform.environment,
          'QODER_CONFIG_DIR': configDir,
        },
        workingDirectory: configDir,
      );
      process.stderr.drain<void>();
      final pending = <int, Completer<Map<String, Object?>>>{};
      lines = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            Map<String, Object?>? message;
            try {
              final decoded = jsonDecode(line);
              if (decoded is Map) {
                message = Map<String, Object?>.from(decoded);
              }
            } on FormatException {
              return;
            }
            final id = message?['id'];
            if (id is int) pending.remove(id)?.complete(message);
          });
      process.stdin.encoding = utf8;

      Future<Map<String, Object?>> request(
        int id,
        Map<String, Object?> payload,
      ) {
        final completer = Completer<Map<String, Object?>>();
        pending[id] = completer;
        process!.stdin.writeln(jsonEncode(payload));
        return completer.future.timeout(timeout);
      }

      await request(1, {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'protocolVersion': 1,
          'clientCapabilities': <String, Object?>{},
        },
      });
      final opened = await request(2, {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'session/new',
        'params': {
          'cwd': configDir,
          'mcpServers': const <Object?>[],
        },
      });
      return parseQoderModelsResponse(opened['result']);
    } on Object {
      return null;
    } finally {
      await lines?.cancel();
      process?.kill();
    }
  }
}

String _safeSegment(String value) {
  final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return safe.isEmpty ? 'provider' : safe;
}

class _CatalogUpdatesNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}
