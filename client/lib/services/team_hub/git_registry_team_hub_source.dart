import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/discoverable_team.dart';
import '../../utils/logger.dart';
import '../io/filesystem.dart';
import '../storage/app_storage.dart';
import 'team_hub_source.dart';

/// Reads public teams from a git registry (`index.json` + `teams/<slug>/team.json`)
/// and caches the parsed result under `team-hub/cache/<owner>-<name>/teams.json`.
class GitRegistryTeamHubSource implements TeamHubSource {
  GitRegistryTeamHubSource({
    this.registry = kDefaultTeamHubRegistry,
    RawContentFetcher? fetch,
    Filesystem? fs,
    String? cacheDirOverride,
  })  : _fetch = fetch ?? _httpFetch,
        _fsOverride = fs,
        _cacheDirOverride = cacheDirOverride;

  final TeamHubRegistry registry;
  final RawContentFetcher _fetch;
  final Filesystem? _fsOverride;
  final String? _cacheDirOverride;

  List<DiscoverableTeam>? _memory;

  Filesystem get _fs => _fsOverride ?? AppStorage.fs;

  String get _cacheFile {
    final dir = _cacheDirOverride ?? AppStorage.paths.teamHubCacheDir;
    final ctx = _fs.pathContext;
    return ctx.join(dir, '${registry.owner}-${registry.name}', 'teams.json');
  }

  static Future<String?> _httpFetch(Uri uri) async {
    try {
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;
      return res.body;
    } catch (e) {
      appLogger.w('[team-hub] fetch failed for $uri: $e');
      return null;
    }
  }

  @override
  Future<List<DiscoverableTeam>> fetchTeams({bool forceRefresh = false}) async {
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
    final teams = await fetchTeams(forceRefresh: forceRefresh);
    final set = <String>{
      for (final t in teams)
        if (t.category.trim().isNotEmpty) t.category.trim(),
    };
    final list = set.toList()..sort();
    return list;
  }

  Future<List<DiscoverableTeam>> _fetchFromNetwork() async {
    final indexRaw = await _fetch(registry.rawUri('index.json'));
    if (indexRaw == null) return const [];
    final slugs = _parseSlugs(indexRaw);
    final out = <DiscoverableTeam>[];
    for (final slug in slugs) {
      final raw = await _fetch(registry.rawUri('teams/$slug/team.json'));
      if (raw == null) continue;
      try {
        final json = (jsonDecode(raw) as Map).cast<String, Object?>();
        // Stamp the canonical key from registry + slug (manifest key ignored).
        json['key'] = '${registry.fullName}/$slug';
        out.add(DiscoverableTeam.fromJson(json));
      } on FormatException catch (e) {
        appLogger.w('[team-hub] bad team.json for $slug: $e');
      }
    }
    return out;
  }

  List<String> _parseSlugs(String indexRaw) {
    try {
      final root = (jsonDecode(indexRaw) as Map).cast<String, Object?>();
      final teams = root['teams'];
      if (teams is! List) return const [];
      return teams
          .whereType<Map>()
          .map((m) => (m['slug'] as String?)?.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList(growable: false);
    } on FormatException catch (e) {
      appLogger.w('[team-hub] bad index.json: $e');
      return const [];
    }
  }

  Future<List<DiscoverableTeam>?> _readCache() async {
    try {
      final text = await _fs.readString(_cacheFile);
      if (text == null || text.isEmpty) return null;
      final list = jsonDecode(text) as List;
      return list
          .whereType<Map>()
          .map((m) => DiscoverableTeam.fromJson(m.cast<String, Object?>()))
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(List<DiscoverableTeam> teams) async {
    try {
      final ctx = _fs.pathContext;
      await _fs.ensureDir(ctx.dirname(_cacheFile));
      await _fs.atomicWrite(
        _cacheFile,
        jsonEncode(teams.map((t) => t.toJson()).toList()),
      );
    } catch (e) {
      appLogger.w('[team-hub] cache write failed: $e');
    }
  }
}
