import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process;

import 'package:flutter/foundation.dart';

import '../../../io/filesystem.dart';
import '../../../storage/home_storage.dart';
import 'codebuddy_auth_store.dart';
import 'codebuddy_region.dart';

/// Account model catalog reported by an `initialize` + `session/new` probe.
///
/// CodeBuddy's ACP `session/new` answers with the models the signed-in account
/// can actually launch, including each model's `effortOptions`; the static
/// picker list is only a cold-start fallback.
@immutable
class CodebuddyModelsSnapshot {
  const CodebuddyModelsSnapshot({
    required this.modelIds,
    this.defaultModelId = '',
    this.names = const {},
    this.descriptions = const {},
    this.effortOptions = const {},
  });

  final List<String> modelIds;
  final String defaultModelId;

  /// Display name per model id (`hy3` → `Hy3`).
  final Map<String, String> names;

  /// Account summary per model id (`x0.11 credits`, i.e. the credit
  /// multiplier the CLI bills for the model).
  final Map<String, String> descriptions;

  /// Reasoning-effort levels per model id, in the agent's order.
  final Map<String, List<String>> effortOptions;
}

/// Parses `session/new` `models.availableModels` into a snapshot.
CodebuddyModelsSnapshot? parseCodebuddyModelsResponse(Object? result) {
  if (result is! Map) return null;
  final models = result['models'];
  if (models is! Map) return null;
  final available = models['availableModels'];
  if (available is! List) return null;

  final ids = <String>[];
  final names = <String, String>{};
  final descriptions = <String, String>{};
  final effortOptions = <String, List<String>>{};
  for (final entry in available) {
    if (entry is! Map) continue;
    final id = entry['modelId']?.toString().trim() ?? '';
    if (id.isEmpty || ids.contains(id)) continue;
    ids.add(id);
    final name = entry['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) names[id] = name;
    final meta = entry['_meta'];
    final description = entry['description']?.toString().trim() ?? '';
    final credits = meta is Map ? meta['credits']?.toString().trim() ?? '' : '';
    if (description.isNotEmpty) {
      descriptions[id] = description;
    } else if (credits.isNotEmpty) {
      descriptions[id] = credits;
    }
    final rawOptions = meta is Map ? meta['effortOptions'] : null;
    if (rawOptions is! List) continue;
    final levels = <String>[];
    for (final option in rawOptions) {
      final value = option is Map ? option['value']?.toString().trim() : null;
      if (value == null || value.isEmpty || levels.contains(value)) continue;
      levels.add(value);
    }
    if (levels.isNotEmpty) effortOptions[id] = levels;
  }
  if (ids.isEmpty) return null;
  return CodebuddyModelsSnapshot(
    modelIds: List<String>.unmodifiable(ids),
    defaultModelId: models['currentModelId']?.toString().trim() ?? '',
    names: Map<String, String>.unmodifiable(names),
    descriptions: Map<String, String>.unmodifiable(descriptions),
    effortOptions: {
      for (final entry in effortOptions.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    },
  );
}

/// Runs one short-lived ACP handshake and returns the account's models.
///
/// [environment] is the account environment from
/// `CodebuddyAuthStore.accountEnvironment` (token + region); empty for the
/// machine login.
typedef CodebuddyAcpModelsOpener =
    Future<CodebuddyModelsSnapshot?> Function({
      required String executable,
      required String configDir,
      required Map<String, String> environment,
      required Duration timeout,
    });

class CodebuddyModelsCacheEntry {
  const CodebuddyModelsCacheEntry({
    required this.fetchedAtMs,
    required this.modelIds,
    this.defaultModelId = '',
    this.names = const {},
    this.descriptions = const {},
    this.effortOptions = const {},
  });

  final int fetchedAtMs;
  final List<String> modelIds;
  final String defaultModelId;
  final Map<String, String> names;
  final Map<String, String> descriptions;
  final Map<String, List<String>> effortOptions;

  Map<String, Object?> toJson() => {
    'fetchedAtMs': fetchedAtMs,
    'modelIds': modelIds,
    if (defaultModelId.isNotEmpty) 'defaultModelId': defaultModelId,
    if (names.isNotEmpty) 'names': names,
    if (descriptions.isNotEmpty) 'descriptions': descriptions,
    if (effortOptions.isNotEmpty) 'effortOptions': effortOptions,
  };

  factory CodebuddyModelsCacheEntry.fromJson(Map<String, Object?> json) {
    final raw = json['modelIds'];
    final rawEffort = json['effortOptions'];
    return CodebuddyModelsCacheEntry(
      fetchedAtMs: (json['fetchedAtMs'] as num?)?.toInt() ?? 0,
      modelIds: raw is List
          ? raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
          : const [],
      defaultModelId: json['defaultModelId']?.toString().trim() ?? '',
      names: _stringMap(json['names']),
      descriptions: _stringMap(json['descriptions']),
      effortOptions: <String, List<String>>{
        if (rawEffort is Map)
          for (final entry in rawEffort.entries)
            if (entry.value is List)
              entry.key.toString(): [
                for (final value in entry.value as List)
                  if (value.toString().trim().isNotEmpty)
                    value.toString().trim(),
              ],
      },
    );
  }
}

/// Fetches and caches the CodeBuddy account model catalog for the pickers.
///
/// The probe runs `codebuddy --acp` against a throwaway config dir and reads
/// `models.availableModels` from `session/new`. The provider's captured token
/// is passed through `CODEBUDDY_AUTH_TOKEN`; without one the machine login
/// under the user home still applies. Results are cached per provider in
/// memory and on disk for six hours.
class CodebuddyModelsService {
  CodebuddyModelsService({
    HomeStorage? storage,
    @visibleForTesting Filesystem? fs,
    @visibleForTesting String? basePath,
    this.executable = 'codebuddy',
    CodebuddyAcpModelsOpener? opener,
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
  final CodebuddyAcpModelsOpener _opener;
  final Duration cacheTtl;
  final Duration probeTimeout;

  /// Test seam for the read-only machine login fallback.
  final String? machineHome;

  final Map<String, CodebuddyModelsCacheEntry> _memory = {};
  final Map<String, Future<void>> _inFlight = {};
  final _CatalogUpdatesNotifier _catalogUpdates = _CatalogUpdatesNotifier();
  String? _lastBasePath;

  Listenable get catalogUpdates => _catalogUpdates;

  /// True once any account catalog has been loaded; until then the capability
  /// uses its static fallback instead of claiming "no effort levels".
  bool get hasLoadedCatalog =>
      _memory.values.any((entry) => entry.modelIds.isNotEmpty);

  List<String> modelIdsFor({required String providerId}) {
    final entry = _memory[_cacheKey(providerId)];
    if (entry == null) return const [];
    return List<String>.unmodifiable(entry.modelIds);
  }

  String defaultModelIdFor({required String providerId}) =>
      _memory[_cacheKey(providerId)]?.defaultModelId.trim() ?? '';

  /// Friendly label for [modelId], or null when the catalog has no name.
  String? modelNameFor({required String providerId, required String modelId}) {
    final name = _memory[_cacheKey(providerId)]?.names[modelId.trim()]?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  /// Credit multiplier text (`x0.11 credits`) for [modelId], when reported.
  String? modelDescriptionFor({
    required String providerId,
    required String modelId,
  }) {
    final text = _memory[_cacheKey(providerId)]?.descriptions[modelId.trim()]
        ?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  /// Reasoning-effort levels the account reports for [modelId].
  List<String> effortOptionsFor({
    required String providerId,
    required String modelId,
  }) =>
      _memory[_cacheKey(providerId)]?.effortOptions[modelId.trim()] ?? const [];

  /// Effort levels for [modelId] from any cached provider.
  ///
  /// `isApplicable` in the capability has no provider argument, so it scans
  /// the loaded catalogs; every account reports the same model metadata.
  List<String> liveEffortOptions(String modelId) {
    final id = modelId.trim();
    if (id.isEmpty) return const [];
    for (final entry in _memory.values) {
      final levels = entry.effortOptions[id];
      if (levels != null && levels.isNotEmpty) return levels;
    }
    return const [];
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
    final task =
        _load(
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

  Future<CodebuddyModelsCacheEntry?> _fetchLive(
    _ResolvedStorage roots, {
    required String providerId,
    String? executable,
  }) async {
    final configDir = roots.fs.pathContext.join(
      roots.basePath,
      'tmp',
      'codebuddy-models',
      _safeSegment(providerId),
    );
    await roots.fs.ensureDir(configDir);

    final store = CodebuddyAuthStore(
      fs: roots.fs,
      basePath: roots.basePath,
      pathContext: roots.fs.pathContext,
    );
    final environment = await store.accountEnvironment(providerId);
    if (environment == null && !await _machineLoginExists(store)) return null;

    // A provider's probe dir is reused across re-logins; drop the region it
    // cached under the previous account.
    await CodebuddyRegion.clearCachedRegion(roots.fs, configDir);

    final resolved = executable?.trim().isNotEmpty == true
        ? executable!.trim()
        : (this.executable.trim().isEmpty ? 'codebuddy' : this.executable);
    final snapshot = await _opener(
      executable: resolved,
      configDir: configDir,
      environment: environment ?? const {},
      timeout: probeTimeout,
    );
    if (snapshot == null || snapshot.modelIds.isEmpty) return null;
    return CodebuddyModelsCacheEntry(
      fetchedAtMs: DateTime.now().millisecondsSinceEpoch,
      modelIds: snapshot.modelIds,
      defaultModelId: snapshot.defaultModelId,
      names: snapshot.names,
      descriptions: snapshot.descriptions,
      effortOptions: snapshot.effortOptions,
    );
  }

  /// The CLI's own login lives under the (machine) user home, not the config
  /// dir, so a machine login is usable even when the provider row has no token.
  Future<bool> _machineLoginExists(CodebuddyAuthStore store) async {
    final home = (machineHome ?? _storage?.home ?? '').trim();
    if (home.isEmpty) return false;
    final dir = store.authDirIn(home);
    if (!(await store.fs.stat(dir)).isDirectory) return false;
    for (final entry in await store.fs.listDir(dir)) {
      if (!entry.isDirectory && entry.name.endsWith('.info')) return true;
    }
    return false;
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
      throw StateError('CodebuddyModelsService needs storage or fs+basePath');
    }
    _sync(snapshot.teampilotRoot);
    return _ResolvedStorage(fs: snapshot.fs, basePath: snapshot.teampilotRoot);
  }

  void _sync(String basePath) {
    if (_lastBasePath != null && _lastBasePath != basePath) _memory.clear();
    _lastBasePath = basePath;
  }

  bool _isFresh(CodebuddyModelsCacheEntry? entry) {
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
      .join(roots.basePath, 'cache', 'codebuddy_models', '$key.json');

  Future<CodebuddyModelsCacheEntry?> _readDiskCache(
    _ResolvedStorage roots,
    String key,
  ) async {
    final raw = await roots.fs.readString(_cacheFilePath(roots, key));
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return CodebuddyModelsCacheEntry.fromJson(
        decoded.cast<String, Object?>(),
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeDiskCache(
    _ResolvedStorage roots,
    String key,
    CodebuddyModelsCacheEntry entry,
  ) async {
    final path = _cacheFilePath(roots, key);
    await roots.fs.ensureDir(roots.fs.pathContext.dirname(path));
    await roots.fs.atomicWrite(path, jsonEncode(entry.toJson()));
  }

  static Future<CodebuddyModelsSnapshot?> _defaultOpener({
    required String executable,
    required String configDir,
    required Map<String, String> environment,
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
          'CODEBUDDY_CONFIG_DIR': configDir,
          ...environment,
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
        'params': {'cwd': configDir, 'mcpServers': const <Object?>[]},
      });
      return parseCodebuddyModelsResponse(opened['result']);
    } on Object {
      return null;
    } finally {
      await lines?.cancel();
      process?.kill();
    }
  }
}

class _ResolvedStorage {
  const _ResolvedStorage({required this.fs, required this.basePath});

  final Filesystem fs;
  final String basePath;
}

String _safeSegment(String value) {
  final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return safe.isEmpty ? 'provider' : safe;
}

Map<String, String> _stringMap(Object? raw) => raw is Map
    ? {
        for (final entry in raw.entries)
          if (entry.value.toString().trim().isNotEmpty)
            entry.key.toString(): entry.value.toString().trim(),
      }
    : const {};

class _CatalogUpdatesNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}
