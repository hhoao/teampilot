import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/discoverable_member.dart';
import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import 'expert_hub_source.dart';

/// Reads public members from a git registry (`index.json` +
/// `members/<slug>/member.json`) and caches the parsed result under
/// `member-hub/cache/<owner>-<name>/members.json`.
class GitRegistryExpertHubSource implements ExpertHubSource {
  GitRegistryExpertHubSource({
    this.registry = kDefaultExpertHubRegistry,
    RawContentFetcher? fetch,
    Filesystem? fs,
    String? cacheDirOverride,
  }) : _fetch = fetch ?? _httpFetch,
       _fsOverride = fs,
       _cacheDirOverride = cacheDirOverride;

  final ExpertHubRegistry registry;
  final RawContentFetcher _fetch;
  final Filesystem? _fsOverride;
  final String? _cacheDirOverride;

  List<DiscoverableMember>? _memory;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;

  String get _cacheFile {
    final dir = _cacheDirOverride ?? AppStorage.paths.memberHubCacheDir;
    final ctx = _fs.pathContext;
    return ctx.join(dir, '${registry.owner}-${registry.name}', 'members.json');
  }

  static Future<String?> _httpFetch(Uri uri) async {
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;
      return res.body;
    } catch (e) {
      appLogger.w('[member-hub] fetch failed for $uri: $e');
      return null;
    }
  }

  @override
  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final mem = _memory;
      if (mem != null) return mem;
      final cached = await _readCache();
      if (cached != null) {
        _memory = cached;
        return cached;
      }
    }
    final fetched = await _fetchFromNetwork();
    _memory = fetched;
    await _writeCache(fetched);
    return fetched;
  }

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async {
    final members = await fetchMembers(forceRefresh: forceRefresh);
    final set = <String>{
      for (final m in members)
        if (m.category.trim().isNotEmpty) m.category.trim(),
    };
    final list = set.toList()..sort();
    return list;
  }

  Future<List<DiscoverableMember>> _fetchFromNetwork() async {
    final indexRaw = await _fetch(registry.rawUri('index.json'));
    if (indexRaw == null) return const [];
    final slugs = _parseSlugs(indexRaw);
    final out = <DiscoverableMember>[];
    for (final slug in slugs) {
      final raw = await _fetch(registry.rawUri('members/$slug/member.json'));
      if (raw == null) continue;
      try {
        final json = (jsonDecode(raw) as Map).cast<String, Object?>();
        // Stamp the canonical key from registry + slug (manifest key ignored).
        json['key'] = '${registry.catalogPrefix}/$slug';
        json['source'] = ExpertMemberSource.registry.value;
        out.add(DiscoverableMember.fromJson(json));
      } on FormatException catch (e) {
        appLogger.w('[member-hub] bad member.json for $slug: $e');
      }
    }
    return out;
  }

  List<String> _parseSlugs(String indexRaw) {
    try {
      final root = (jsonDecode(indexRaw) as Map).cast<String, Object?>();
      final members = root['members'];
      if (members is! List) return const [];
      return members
          .map((s) => s is String ? s.trim() : '')
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    } on FormatException catch (e) {
      appLogger.w('[member-hub] bad index.json: $e');
      return const [];
    }
  }

  Future<List<DiscoverableMember>?> _readCache() async {
    try {
      final text = await _fs.readString(_cacheFile);
      if (text == null || text.isEmpty) return null;
      final list = jsonDecode(text) as List;
      return list
          .whereType<Map>()
          .map((m) => DiscoverableMember.fromJson(m.cast<String, Object?>()))
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(List<DiscoverableMember> members) async {
    try {
      final ctx = _fs.pathContext;
      await _fs.ensureDir(ctx.dirname(_cacheFile));
      await _fs.atomicWrite(
        _cacheFile,
        jsonEncode(members.map((m) => m.toJson()).toList()),
      );
    } catch (e) {
      appLogger.w('[member-hub] cache write failed: $e');
    }
  }
}
