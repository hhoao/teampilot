import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/catalog/catalog_types.dart';
import '../../models/skill_pack.dart';
import '../../utils/logging/logger.dart';
import '../catalog/catalog_error_sanitizer.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import 'skill_pack_source.dart';

/// Reads public Skill Packs from a git registry (`index.json` +
/// `<slug>/pack.json`) and caches parsed results under
/// `skill-packs/cache/<owner>-<name>/packs.json`.
class GitRegistrySkillPackSource implements SkillPackSource {
  GitRegistrySkillPackSource({
    this.registry = kDefaultSkillPackRegistry,
    SkillPackRawContentFetcher? fetch,
    Filesystem? fs,
    String? cacheDirOverride,
  }) : _fetch = fetch ?? _httpFetch,
       _fsOverride = fs,
       _cacheDirOverride = cacheDirOverride;

  final SkillPackRegistryConfig registry;
  final SkillPackRawContentFetcher _fetch;
  final Filesystem? _fsOverride;
  final String? _cacheDirOverride;

  List<SkillPack>? _memory;
  CatalogSourceFailure? _lastFailure;

  CatalogSourceFailure? get lastFailure => _lastFailure;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;

  String get _cacheFile {
    final dir = _cacheDirOverride ?? AppStorage.paths.skillPackCatalogCacheDir;
    return _fs.pathContext.join(
      dir,
      '${registry.owner}-${registry.name}',
      'packs.json',
    );
  }

  static Future<String?> _httpFetch(Uri uri) async {
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;
      return response.body;
    } catch (error) {
      appLogger.w('[skill-packs] fetch failed for $uri: $error');
      return null;
    }
  }

  @override
  Future<List<SkillPack>> fetchPacks({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final memory = _memory;
      if (memory != null) return memory;
      final cached = await _readCache();
      if (cached != null) {
        _memory = cached;
        return cached;
      }
    }

    final indexRaw = await _fetch(registry.rawUri('index.json'));
    if (indexRaw == null) {
      _lastFailure = CatalogSourceFailure(
        sourceId: 'skill-pack-registry',
        sourceLabel: registry.fullName,
        message: CatalogErrorSanitizer.sanitize('Registry index unavailable'),
      );
      _memory = const [];
      await _writeCache(const []);
      return const [];
    }

    final packs = <SkillPack>[];
    for (final slug in _parseSlugs(indexRaw)) {
      final raw = await _fetch(registry.rawUri('$slug/pack.json'));
      if (raw == null) continue;
      try {
        packs.add(
          SkillPack.fromJson((jsonDecode(raw) as Map).cast<String, Object?>()),
        );
      } on FormatException catch (error) {
        appLogger.w('[skill-packs] bad pack.json for $slug: $error');
      }
    }

    _memory = packs;
    await _writeCache(packs);
    return packs;
  }

  List<String> _parseSlugs(String indexRaw) {
    try {
      final root = (jsonDecode(indexRaw) as Map).cast<String, Object?>();
      final packs = root['packs'];
      if (packs is! List) return const [];
      return packs
          .whereType<String>()
          .map((slug) => slug.trim())
          .where((slug) => slug.isNotEmpty)
          .toList(growable: false);
    } on FormatException catch (error) {
      appLogger.w('[skill-packs] bad index.json: $error');
      return const [];
    }
  }

  Future<List<SkillPack>?> _readCache() async {
    try {
      final raw = await _fs.readString(_cacheFile);
      if (raw == null || raw.isEmpty) return null;
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map>()
          .map((pack) => SkillPack.fromJson(pack.cast<String, Object?>()))
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(List<SkillPack> packs) async {
    try {
      final cacheFile = _cacheFile;
      await _fs.ensureDir(_fs.pathContext.dirname(cacheFile));
      await _fs.atomicWrite(
        cacheFile,
        jsonEncode(packs.map((pack) => pack.toJson()).toList()),
      );
    } catch (error) {
      appLogger.w('[skill-packs] cache write failed: $error');
    }
  }
}
