import 'dart:convert';
import 'dart:io' show Process;

import 'package:flutter/foundation.dart';

import '../../../io/filesystem.dart';
import '../../../storage/home_storage.dart';

typedef CodexModelsProcessRunner =
    Future<CodexModelsProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      String? workingDirectory,
    });

class CodexModelsProcessResult {
  const CodexModelsProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

/// Model slugs from `codex debug models`, dropping `visibility: hide` rows.
List<String> parseCodexModelsJson(Object? decoded) {
  if (decoded is! Map) return const [];
  final models = decoded['models'];
  if (models is! List) return const [];
  final ids = <String>[];
  for (final entry in models) {
    if (entry is! Map) continue;
    final visibility = entry['visibility']?.toString().trim().toLowerCase();
    if (visibility == 'hide') continue;
    final slug = entry['slug']?.toString().trim() ?? '';
    if (slug.isEmpty || ids.contains(slug)) continue;
    ids.add(slug);
  }
  return ids;
}

class CodexModelsCacheEntry {
  const CodexModelsCacheEntry({
    required this.fetchedAtMs,
    required this.modelIds,
  });

  final int fetchedAtMs;
  final List<String> modelIds;

  Map<String, Object?> toJson() => {
    'fetchedAtMs': fetchedAtMs,
    'modelIds': modelIds,
  };

  factory CodexModelsCacheEntry.fromJson(Map<String, Object?> json) {
    final rawIds = json['modelIds'];
    return CodexModelsCacheEntry(
      fetchedAtMs: (json['fetchedAtMs'] as num?)?.toInt() ?? 0,
      modelIds: rawIds is List
          ? rawIds.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
          : const [],
    );
  }
}

/// Fetches and caches `codex debug models` for the model pickers.
///
/// The CLI renders its bundled catalog as JSON, including the models the
/// signed-in account can launch. That covers both ChatGPT (OAuth) and API-key
/// logins, which the plain `/v1/models` endpoint cannot.
class CodexModelsService {
  CodexModelsService({
    HomeStorage? storage,
    @visibleForTesting Filesystem? fs,
    @visibleForTesting String? basePath,
    this.executable = 'codex',
    CodexModelsProcessRunner? processRunner,
    this.cacheTtl = const Duration(hours: 6),
    this.timeout = const Duration(seconds: 20),
  }) : _storage = storage,
       _fsOverride = fs,
       _basePathOverride = basePath?.trim(),
       _processRunner = processRunner ?? _defaultProcessRunner;

  static const _globalCacheKey = '_global';

  final HomeStorage? _storage;
  final Filesystem? _fsOverride;
  final String? _basePathOverride;
  final String executable;
  final CodexModelsProcessRunner _processRunner;
  final Duration cacheTtl;
  final Duration timeout;

  final Map<String, CodexModelsCacheEntry> _memory = {};
  final Map<String, Future<void>> _inFlight = {};
  final _CatalogUpdatesNotifier _catalogUpdates = _CatalogUpdatesNotifier();
  String? _lastBasePath;

  Listenable get catalogUpdates => _catalogUpdates;

  List<String> modelIdsFor({String providerId = ''}) {
    final entry = _memory[_cacheKey(providerId)];
    if (entry == null) return const [];
    return List<String>.unmodifiable(entry.modelIds);
  }

  Future<void> ensureLoaded({
    required String providerId,
    String? executable,
    bool forceRefresh = false,
  }) {
    final key = _cacheKey(providerId);
    if (!forceRefresh && _isFresh(_memory[key])) return Future.value();
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final task = _load(key, executable: executable, forceRefresh: forceRefresh)
        .whenComplete(() {
          // Block body: returning the removed future would make whenComplete wait
          // on itself and never complete.
          _inFlight.remove(key);
        });
    _inFlight[key] = task;
    return task;
  }

  Future<void> _load(
    String cacheKey, {
    String? executable,
    required bool forceRefresh,
  }) async {
    final roots = await _resolveStorage();
    final disk = forceRefresh ? null : await _readDiskCache(roots, cacheKey);
    if (disk != null && _isFresh(disk)) {
      _memory[cacheKey] = disk;
      _catalogUpdates.bump();
      return;
    }

    final fetched = await _fetchLive(executable: executable);
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

  Future<CodexModelsCacheEntry?> _fetchLive({String? executable}) async {
    final resolved = executable?.trim().isNotEmpty == true
        ? executable!.trim()
        : (this.executable.trim().isEmpty ? 'codex' : this.executable.trim());
    final result = await _processRunner(resolved, const ['debug', 'models']);
    if (result.exitCode != 0) return null;
    List<String> ids;
    try {
      ids = parseCodexModelsJson(jsonDecode(result.stdout));
    } on FormatException {
      return null;
    }
    if (ids.isEmpty) return null;
    return CodexModelsCacheEntry(
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
      modelIds: List<String>.unmodifiable(ids),
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
      throw StateError('CodexModelsService needs storage or fs+basePath');
    }
    _sync(snapshot.teampilotRoot);
    return _ResolvedStorage(fs: snapshot.fs, basePath: snapshot.teampilotRoot);
  }

  void _sync(String basePath) {
    if (_lastBasePath != null && _lastBasePath != basePath) _memory.clear();
    _lastBasePath = basePath;
  }

  bool _isFresh(CodexModelsCacheEntry? entry) {
    if (entry == null || entry.modelIds.isEmpty) return false;
    final age = DateTime.now().millisecondsSinceEpoch - entry.fetchedAtMs;
    return age >= 0 && age < cacheTtl.inMilliseconds;
  }

  String _cacheKey(String providerId) {
    final trimmed = providerId.trim();
    return trimmed.isEmpty ? _globalCacheKey : trimmed;
  }

  String _cacheFilePath(_ResolvedStorage roots, String key) => roots
      .fs
      .pathContext
      .join(roots.basePath, 'cache', 'codex_models', '$key.json');

  Future<CodexModelsCacheEntry?> _readDiskCache(
    _ResolvedStorage roots,
    String key,
  ) async {
    final raw = await roots.fs.readString(_cacheFilePath(roots, key));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return CodexModelsCacheEntry.fromJson(decoded.cast<String, Object?>());
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeDiskCache(
    _ResolvedStorage roots,
    String key,
    CodexModelsCacheEntry entry,
  ) async {
    final path = _cacheFilePath(roots, key);
    await roots.fs.ensureDir(roots.fs.pathContext.dirname(path));
    await roots.fs.atomicWrite(path, jsonEncode(entry.toJson()));
  }

  static Future<CodexModelsProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        environment: environment,
        workingDirectory: workingDirectory,
      ).timeout(const Duration(seconds: 20));
      return CodexModelsProcessResult(
        exitCode: result.exitCode,
        stdout: result.stdout.toString(),
        stderr: result.stderr.toString(),
      );
    } on Object catch (error) {
      return CodexModelsProcessResult(
        exitCode: -1,
        stdout: '',
        stderr: error.toString(),
      );
    }
  }
}

class _ResolvedStorage {
  const _ResolvedStorage({required this.fs, required this.basePath});

  final Filesystem fs;
  final String basePath;
}

class _CatalogUpdatesNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}
