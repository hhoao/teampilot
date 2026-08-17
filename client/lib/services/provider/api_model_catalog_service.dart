import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/app_provider_config.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';

/// Supported provider API model-list response formats.
enum ApiModelCatalogProtocol { openAi, anthropic }

/// Disk-cache payload for a provider's model IDs.
class ApiModelCatalogCacheEntry {
  const ApiModelCatalogCacheEntry({
    required this.fetchedAtMs,
    required this.modelIds,
  });

  final int fetchedAtMs;
  final List<String> modelIds;

  Map<String, Object?> toJson() => {
    'fetchedAtMs': fetchedAtMs,
    'modelIds': modelIds,
  };

  factory ApiModelCatalogCacheEntry.fromJson(Map<String, Object?> json) {
    final rawIds = json['modelIds'];
    final ids = rawIds is List
        ? (rawIds
              .map((value) => value.toString().trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList()
            ..sort())
        : const <String>[];
    return ApiModelCatalogCacheEntry(
      fetchedAtMs: (json['fetchedAtMs'] as num?)?.toInt() ?? 0,
      modelIds: ids,
    );
  }
}

/// Fetches and caches model IDs from an API-compatible provider endpoint.
class ApiModelCatalogService {
  ApiModelCatalogService({
    required this.protocol,
    required this.cacheDirectory,
    @visibleForTesting Filesystem? fs,
    @visibleForTesting String? basePath,
    http.Client? httpClient,
    this.cacheTtl = const Duration(hours: 6),
  }) : _fsOverride = fs,
       _basePathOverride = basePath?.trim(),
       _httpClient = httpClient ?? http.Client();

  final ApiModelCatalogProtocol protocol;
  final String cacheDirectory;
  final Duration cacheTtl;

  final Filesystem? _fsOverride;
  final String? _basePathOverride;
  final http.Client _httpClient;

  final Map<String, ApiModelCatalogCacheEntry> _memory = {};
  final Map<String, Future<void>> _inFlight = {};
  final _CatalogUpdatesNotifier _catalogUpdates = _CatalogUpdatesNotifier();
  String? _lastResolvedBasePath;

  Listenable get catalogUpdates => _catalogUpdates;

  List<String> modelIdsFor({required String providerId}) {
    final entry = _memory[providerId.trim()];
    return entry == null ? const [] : List<String>.unmodifiable(entry.modelIds);
  }

  Future<void> ensureLoaded({
    required String providerId,
    required AppProviderConfig provider,
    bool forceRefresh = false,
  }) {
    final key = providerId.trim();
    if (key.isEmpty || provider.apiKey.trim().isEmpty) return Future.value();
    if (!forceRefresh && _isFresh(_memory[key])) return Future.value();

    final existing = _inFlight[key];
    if (existing != null) return existing;

    final task = _load(key, provider: provider, forceRefresh: forceRefresh)
        .whenComplete(() {
          _inFlight.remove(key);
        });
    _inFlight[key] = task;
    return task;
  }

  @visibleForTesting
  Future<void> writeCacheForTest({
    required String providerId,
    required ApiModelCatalogCacheEntry entry,
  }) async {
    final key = providerId.trim();
    _memory[key] = entry;
    final roots = await _resolveStorage();
    await _writeDiskCache(roots, key, entry);
  }

  Future<void> _load(
    String providerId, {
    required AppProviderConfig provider,
    required bool forceRefresh,
  }) async {
    final roots = await _resolveStorage();
    final disk = await _readDiskCache(roots, providerId);
    if (!forceRefresh && _isFresh(disk)) {
      _memory[providerId] = disk!;
      _catalogUpdates.bump();
      return;
    }

    final fetched = await _fetchLive(provider);
    if (fetched != null) {
      _memory[providerId] = fetched;
      try {
        await _writeDiskCache(roots, providerId, fetched);
      } on Object {
        // Keep a successful live response in memory when disk is unavailable.
      }
      _catalogUpdates.bump();
      return;
    }

    if (disk != null && _memory[providerId] == null) {
      _memory[providerId] = disk;
      _catalogUpdates.bump();
    }
  }

  Future<ApiModelCatalogCacheEntry?> _fetchLive(
    AppProviderConfig provider,
  ) async {
    try {
      final response = await _httpClient
          .get(_modelsUri(provider.baseUrl), headers: _headers(provider))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final modelIds = parseModelIds(jsonDecode(response.body));
      if (modelIds.isEmpty) return null;
      return ApiModelCatalogCacheEntry(
        fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
        modelIds: modelIds,
      );
    } on Object {
      return null;
    }
  }

  Map<String, String> _headers(AppProviderConfig provider) {
    final key = provider.apiKey.trim();
    return switch (protocol) {
      ApiModelCatalogProtocol.openAi => {'Authorization': 'Bearer $key'},
      ApiModelCatalogProtocol.anthropic => {
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
      },
    };
  }

  Uri _modelsUri(String rawBaseUrl) {
    final baseUrl = rawBaseUrl.trim();
    if (baseUrl.isEmpty) {
      return Uri.parse(
        protocol == ApiModelCatalogProtocol.openAi
            ? 'https://api.openai.com/v1/models'
            : 'https://api.anthropic.com/v1/models',
      );
    }

    final parsed = Uri.parse(baseUrl);
    final path = parsed.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith('/models')) return parsed;
    final suffix = path.endsWith('/v1') ? '/models' : '/v1/models';
    return parsed.replace(path: '${path.isEmpty ? '' : path}$suffix');
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
      _memory.clear();
    }
    _lastResolvedBasePath = basePath;
  }

  bool _isFresh(ApiModelCatalogCacheEntry? entry) {
    if (entry == null || entry.modelIds.isEmpty) return false;
    final age = DateTime.now().millisecondsSinceEpoch - entry.fetchedAtMs;
    return age >= 0 && age < cacheTtl.inMilliseconds;
  }

  String _cacheFilePath(_ResolvedStorage roots, String providerId) {
    final safeId = providerId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return roots.fs.pathContext.join(
      roots.basePath,
      'cache',
      cacheDirectory,
      '$safeId.json',
    );
  }

  Future<ApiModelCatalogCacheEntry?> _readDiskCache(
    _ResolvedStorage roots,
    String providerId,
  ) async {
    final path = _cacheFilePath(roots, providerId);
    final stat = await roots.fs.stat(path);
    if (!stat.isFile) return null;
    final text = await roots.fs.readString(path);
    if (text == null) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return ApiModelCatalogCacheEntry.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _writeDiskCache(
    _ResolvedStorage roots,
    String providerId,
    ApiModelCatalogCacheEntry entry,
  ) async {
    final path = _cacheFilePath(roots, providerId);
    await roots.fs.ensureDir(roots.fs.pathContext.dirname(path));
    await roots.fs.writeString(path, jsonEncode(entry.toJson()));
  }

  static List<String> parseModelIds(Object? payload) {
    final rawItems = payload is Map
        ? payload['data']
        : payload is List
        ? payload
        : null;
    if (rawItems is! List) return const [];

    final ids = <String>{};
    for (final item in rawItems) {
      final id = item is Map ? item['id']?.toString().trim() ?? '' : '';
      if (id.isNotEmpty) ids.add(id);
    }
    return ids.toList()..sort();
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
