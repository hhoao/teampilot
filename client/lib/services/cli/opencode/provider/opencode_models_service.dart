import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../io/filesystem.dart';
import '../../../storage/app_storage.dart';

/// Cache entry for a fetched models.dev catalog slice.
///
/// models.dev's `api.json` is a single global catalog (all providers); only the
/// `providerId -> [model ids]` mapping is kept on disk.
class OpencodeModelsCacheEntry {
  const OpencodeModelsCacheEntry({
    required this.fetchedAtMs,
    required this.modelsByProvider,
  });

  final int fetchedAtMs;
  final Map<String, List<String>> modelsByProvider;

  Map<String, Object?> toJson() => {
    'fetchedAtMs': fetchedAtMs,
    'modelsByProvider': modelsByProvider,
  };

  factory OpencodeModelsCacheEntry.fromJson(Map<String, Object?> json) {
    final byProvider = <String, List<String>>{};
    final raw = json['modelsByProvider'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final ids = entry.value;
        if (ids is List) {
          final list = OpencodeModelsService._extractModelIds(ids);
          if (list.isNotEmpty) {
            byProvider[entry.key.toString().trim()] = list;
          }
        }
      }
    }
    return OpencodeModelsCacheEntry(
      fetchedAtMs: (json['fetchedAtMs'] as num?)?.toInt() ?? 0,
      modelsByProvider: byProvider,
    );
  }
}

class _ResolvedStorage {
  const _ResolvedStorage({required this.fs, required this.basePath});

  final Filesystem fs;
  final String basePath;
}

/// Fetches and caches the models.dev catalog for opencode provider pickers.
///
/// opencode itself syncs its provider catalog from `https://models.dev/api.json`
/// (`packages/opencode/src/cli/cmd/providers.ts`). One fetch refreshes every
/// provider opencode can launch with (zen, go, openai, anthropic, google, …).
/// Falls back to the built-in static catalog (see `OpencodeCatalogSource`).
class OpencodeModelsService {
  OpencodeModelsService({
    @visibleForTesting Filesystem? fs,
    @visibleForTesting String? basePath,
    http.Client? httpClient,
    this.cacheTtl = const Duration(hours: 6),
  }) : _fsOverride = fs,
       _basePathOverride = basePath?.trim(),
       _httpClient = httpClient ?? http.Client();

  static const _modelsDevUrl = 'https://models.dev/api.json';
  static const _cacheKey = 'models';

  final Filesystem? _fsOverride;
  final String? _basePathOverride;
  final http.Client _httpClient;
  final Duration cacheTtl;

  OpencodeModelsCacheEntry? _memory;
  Future<void>? _inFlight;
  final _CatalogUpdatesNotifier _catalogUpdates = _CatalogUpdatesNotifier();
  String? _lastResolvedBasePath;

  Listenable get catalogUpdates => _catalogUpdates;

  List<String> modelIdsFor({String providerId = ''}) {
    final entry = _memory;
    if (entry == null) return const [];
    final ids = entry.modelsByProvider[providerId.trim()];
    if (ids == null) return const [];
    return List<String>.unmodifiable(ids);
  }

  Future<void> ensureLoaded({bool forceRefresh = false}) {
    if (!forceRefresh && _isFresh(_memory)) {
      return Future.value();
    }
    final existing = _inFlight;
    if (existing != null) return existing;
    final task = _load(forceRefresh: forceRefresh).whenComplete(
      () => _inFlight = null,
    );
    _inFlight = task;
    return task;
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final roots = await _resolveStorage();
    final disk = await _readDiskCache(roots);
    if (!forceRefresh && disk != null && _isFresh(disk)) {
      _memory = disk;
      _catalogUpdates.bump();
      return;
    }

    final fetched = await _fetchLive();
    if (fetched != null) {
      // Populate memory BEFORE writing so candidates are available even if the
      // write fails; swallow write errors (disk full, read-only FS, SFTP) so a
      // fire-and-forget refresh never throws. The disk cache self-heals on the
      // next refresh.
      _memory = fetched;
      try {
        await _writeDiskCache(roots, fetched);
      } on Object {
        // Ignored: memory is already populated.
      }
      _catalogUpdates.bump();
      return;
    }

    if (disk != null && _memory == null) {
      _memory = disk;
      _catalogUpdates.bump();
    }
  }

  Future<_ResolvedStorage> _resolveStorage() async {
    final fsOverride = _fsOverride;
    final basePathOverride = _basePathOverride;
    assert(
      (fsOverride == null) == (basePathOverride == null),
      'Test overrides must be provided together: fs and basePath, or neither.',
    );
    if (fsOverride != null && basePathOverride != null) {
      _syncMemoryForBasePath(basePathOverride);
      return _ResolvedStorage(fs: fsOverride, basePath: basePathOverride);
    }
    if (AppStorage.isInstalled) {
      final snap = AppStorage.context;
      _syncMemoryForBasePath(snap.teampilotRoot);
      return _ResolvedStorage(fs: snap.fs, basePath: snap.teampilotRoot);
    }
    _syncMemoryForBasePath(AppStorage.appDataRoot);
    return _ResolvedStorage(
      fs: AppStorage.fs,
      basePath: AppStorage.appDataRoot,
    );
  }

  void _syncMemoryForBasePath(String basePath) {
    if (_lastResolvedBasePath != null && _lastResolvedBasePath != basePath) {
      _memory = null;
    }
    _lastResolvedBasePath = basePath;
  }

  bool _isFresh(OpencodeModelsCacheEntry? entry) {
    if (entry == null || entry.modelsByProvider.isEmpty) return false;
    final age = DateTime.now().millisecondsSinceEpoch - entry.fetchedAtMs;
    return age >= 0 && age < cacheTtl.inMilliseconds;
  }

  String _cacheFilePath(_ResolvedStorage roots) => roots.fs.pathContext.join(
    roots.basePath,
    'cache',
    'opencode_models',
    '$_cacheKey.json',
  );

  Future<OpencodeModelsCacheEntry?> _readDiskCache(
    _ResolvedStorage roots,
  ) async {
    final path = _cacheFilePath(roots);
    final stat = await roots.fs.stat(path);
    if (!stat.isFile) return null;
    final text = await roots.fs.readString(path);
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return OpencodeModelsCacheEntry.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _writeDiskCache(
    _ResolvedStorage roots,
    OpencodeModelsCacheEntry entry,
  ) async {
    final path = _cacheFilePath(roots);
    await roots.fs.ensureDir(roots.fs.pathContext.dirname(path));
    await roots.fs.writeString(path, jsonEncode(entry.toJson()));
  }

  static List<String> _extractModelIds(Iterable<Object?> raw) {
    final ids = <String>[];
    for (final value in raw) {
      final id = value.toString().trim();
      if (id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  Future<OpencodeModelsCacheEntry?> _fetchLive() async {
    try {
      final response = await _httpClient
          .get(Uri.parse(_modelsDevUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final byProvider = <String, List<String>>{};
      for (final entry in decoded.entries) {
        final providerId = entry.key.toString().trim();
        if (providerId.isEmpty) continue;
        final provider = entry.value;
        if (provider is! Map) continue;
        final models = provider['models'];
        if (models is! Map) continue;
        final ids = _extractModelIds(models.keys);
        if (ids.isEmpty) continue;
        byProvider[providerId] = ids;
      }
      if (byProvider.isEmpty) return null;
      return OpencodeModelsCacheEntry(
        fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
        modelsByProvider: byProvider,
      );
    } on Object {
      return null;
    }
  }

  @visibleForTesting
  Future<void> writeCacheForTest(OpencodeModelsCacheEntry entry) async {
    _memory = entry;
    final roots = await _resolveStorage();
    await _writeDiskCache(roots, entry);
  }
}

class _CatalogUpdatesNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}
