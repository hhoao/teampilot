import 'dart:convert';
import 'dart:io' show Process;

import 'package:flutter/foundation.dart';

import '../../io/filesystem.dart';
import '../../storage/app_storage.dart';
import '../../storage/storage_resolver.dart';
import 'cursor_agent_models_parser.dart';
import 'cursor_home_layout.dart';
import 'cursor_launch_environment.dart';
import 'cursor_provider_credentials_service.dart';

typedef CursorAgentModelsProcessRunner =
    Future<CursorAgentModelsProcessResult> Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      String? workingDirectory,
    });

class CursorAgentModelsProcessResult {
  const CursorAgentModelsProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class CursorAgentModelsCacheEntry {
  const CursorAgentModelsCacheEntry({
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

  factory CursorAgentModelsCacheEntry.fromJson(Map<String, Object?> json) {
    final rawIds = json['modelIds'];
    return CursorAgentModelsCacheEntry(
      fetchedAtMs: (json['fetchedAtMs'] as num?)?.toInt() ?? 0,
      modelIds: rawIds is List
          ? rawIds.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
          : const [],
      defaultModelId: json['defaultModelId']?.toString().trim() ?? '',
    );
  }
}

class _ResolvedStorage {
  const _ResolvedStorage({required this.fs, required this.basePath});

  final Filesystem fs;
  final String basePath;
}

/// Fetches and caches `cursor-agent models` for provider model pickers.
class CursorAgentModelsService {
  CursorAgentModelsService({
    StorageRoots? storageRoots,
    @visibleForTesting Filesystem? fs,
    @visibleForTesting String? basePath,
    this.cursorExecutable = 'cursor-agent',
    CursorAgentModelsProcessRunner? processRunner,
    this.cacheTtl = const Duration(hours: 6),
  }) : _storageRoots = storageRoots,
       _fsOverride = fs,
       _basePathOverride = basePath?.trim(),
       _processRunner = processRunner ?? _defaultProcessRunner;

  static const _layout = CursorHomeLayout();
  static const _globalCacheKey = '_global';

  final StorageRoots? _storageRoots;
  final Filesystem? _fsOverride;
  final String? _basePathOverride;
  final String cursorExecutable;
  final CursorAgentModelsProcessRunner _processRunner;
  final Duration cacheTtl;

  final Map<String, CursorAgentModelsCacheEntry> _memory = {};
  final Map<String, Future<void>> _inFlight = {};
  final _CatalogUpdatesNotifier _catalogUpdates = _CatalogUpdatesNotifier();
  String? _lastResolvedBasePath;

  Listenable get catalogUpdates => _catalogUpdates;

  @visibleForTesting
  Future<void> writeCacheForTest({
    required String providerId,
    required CursorAgentModelsCacheEntry entry,
  }) async {
    final key = _cacheKey(providerId);
    _memory[key] = entry;
    final roots = await _resolveStorage();
    await _writeDiskCache(roots, key, entry);
  }

  List<String> modelIdsFor({String providerId = ''}) {
    final entry = _memory[_cacheKey(providerId)];
    if (entry == null) return const [];
    return List<String>.unmodifiable(entry.modelIds);
  }

  String defaultModelIdFor({String providerId = ''}) {
    final entry = _memory[_cacheKey(providerId)];
    return entry?.defaultModelId.trim() ?? '';
  }

  Future<void> ensureLoaded({
    required String providerId,
    String? executable,
    bool forceRefresh = false,
  }) {
    final key = _cacheKey(providerId);
    if (!forceRefresh && _isFresh(_memory[key])) {
      return Future.value();
    }
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final task = _load(key, providerId: providerId, executable: executable)
        .whenComplete(() => _inFlight.remove(key));
    _inFlight[key] = task;
    return task;
  }

  Future<void> _load(
    String cacheKey, {
    required String providerId,
    String? executable,
  }) async {
    final roots = await _resolveStorage();
    final disk = await _readDiskCache(roots, cacheKey);
    if (disk != null && _isFresh(disk)) {
      _memory[cacheKey] = disk;
      _catalogUpdates.bump();
      return;
    }

    final fetched = await _fetchLive(
      roots: roots,
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

  Future<_ResolvedStorage> _resolveStorage() async {
    final storageRoots = _storageRoots;
    if (storageRoots != null) {
      final snap = await storageRoots.resolve();
      _syncMemoryForBasePath(snap.teampilotRoot);
      return _ResolvedStorage(fs: snap.fs, basePath: snap.teampilotRoot);
    }
    final fsOverride = _fsOverride;
    final basePathOverride = _basePathOverride;
    if (fsOverride != null && basePathOverride != null) {
      _syncMemoryForBasePath(basePathOverride);
      return _ResolvedStorage(fs: fsOverride, basePath: basePathOverride);
    }
    _syncMemoryForBasePath(AppStorage.appDataRoot);
    return _ResolvedStorage(fs: AppStorage.fs, basePath: AppStorage.appDataRoot);
  }

  void _syncMemoryForBasePath(String basePath) {
    if (_lastResolvedBasePath != null && _lastResolvedBasePath != basePath) {
      _memory.clear();
    }
    _lastResolvedBasePath = basePath;
  }

  bool _isFresh(CursorAgentModelsCacheEntry? entry) {
    if (entry == null || entry.modelIds.isEmpty) return false;
    final age = DateTime.now().millisecondsSinceEpoch - entry.fetchedAtMs;
    return age >= 0 && age < cacheTtl.inMilliseconds;
  }

  String _cacheKey(String providerId) {
    final trimmed = providerId.trim();
    return trimmed.isEmpty ? _globalCacheKey : trimmed;
  }

  String _cacheFilePath(_ResolvedStorage roots, String cacheKey) =>
      roots.fs.pathContext.join(
        roots.basePath,
        'cache',
        'cursor_agent_models',
        '$cacheKey.json',
      );

  Future<CursorAgentModelsCacheEntry?> _readDiskCache(
    _ResolvedStorage roots,
    String cacheKey,
  ) async {
    final path = _cacheFilePath(roots, cacheKey);
    final stat = await roots.fs.stat(path);
    if (!stat.isFile) return null;
    final text = await roots.fs.readString(path);
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return CursorAgentModelsCacheEntry.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _writeDiskCache(
    _ResolvedStorage roots,
    String cacheKey,
    CursorAgentModelsCacheEntry entry,
  ) async {
    final path = _cacheFilePath(roots, cacheKey);
    await roots.fs.ensureDir(roots.fs.pathContext.dirname(path));
    await roots.fs.writeString(path, jsonEncode(entry.toJson()));
  }

  Future<CursorAgentModelsCacheEntry?> _fetchLive({
    required _ResolvedStorage roots,
    required String providerId,
    String? executable,
  }) async {
    final resolved = executable?.trim() ?? cursorExecutable;
    if (resolved.isEmpty) return null;

    final environment = await _environmentForProvider(roots, providerId);
    final result = await _processRunner(
      resolved,
      const ['models', '--trust'],
      environment: environment,
      workingDirectory: roots.fs.pathContext.dirname(roots.basePath),
    );
    if (result.exitCode != 0) return null;

    final modelIds = parseCursorAgentModelsOutput(result.stdout);
    if (modelIds.isEmpty) return null;

    return CursorAgentModelsCacheEntry(
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
      modelIds: modelIds,
      defaultModelId: parseCursorAgentDefaultModelId(result.stdout) ?? '',
    );
  }

  Future<Map<String, String>?> _environmentForProvider(
    _ResolvedStorage roots,
    String providerId,
  ) async {
    final id = providerId.trim();
    if (id.isEmpty) return null;

    final credentials = CursorProviderCredentialsService(
      fs: roots.fs,
      basePath: roots.basePath,
    );
    final home = credentials.providerHome(id);
    final authPath = _layout.authJson(home);
    final authStat = await roots.fs.stat(authPath);
    if (!authStat.isFile) return null;

    return CursorLaunchEnvironment.forMixed(homeRoot: home, useWslPaths: false);
  }

  static Future<CursorAgentModelsProcessResult> _defaultProcessRunner(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      environment: environment,
      workingDirectory: workingDirectory,
    );
    return CursorAgentModelsProcessResult(
      exitCode: result.exitCode,
      stdout: result.stdout.toString(),
      stderr: result.stderr.toString(),
    );
  }
}

class _CatalogUpdatesNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}
