import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../models/skill.dart';

class SkillFetchException implements Exception {
  SkillFetchException(this.message, [this.cause]);
  final String message;
  final Object? cause;
  @override
  String toString() => 'SkillFetchException: $message';
}

class SkillParseException implements Exception {
  SkillParseException(this.message);
  final String message;
  @override
  String toString() => 'SkillParseException: $message';
}

class SkillFrontmatter {
  const SkillFrontmatter({required this.name, required this.description});
  final String name;
  final String description;
}

/// Minimal YAML frontmatter parser. Reads only `name` and `description`.
/// Indented subtrees (e.g. `webServer:`) are skipped to avoid pulling in a
/// full YAML dependency.
SkillFrontmatter parseSkillFrontmatter(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') {
    throw SkillParseException('Missing frontmatter');
  }
  var end = -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') {
      end = i;
      break;
    }
  }
  if (end < 0) throw SkillParseException('Unterminated frontmatter');

  String? name;
  String? description;
  var skipIndent = false;
  for (var i = 1; i < end; i++) {
    final raw = lines[i];
    if (skipIndent) {
      if (raw.startsWith(' ') || raw.startsWith('\t')) continue;
      skipIndent = false;
    }
    final line = raw.trimRight();
    if (line.isEmpty || line.startsWith('#')) continue;
    final colonIdx = line.indexOf(':');
    if (colonIdx < 0) continue;
    final key = line.substring(0, colonIdx).trim();
    final value = line.substring(colonIdx + 1).trim();
    if (value.isEmpty) {
      skipIndent = true;
      continue;
    }
    final unq = _unquote(value);
    if (key == 'name') name = unq;
    if (key == 'description') description = unq;
  }
  if (name == null || name.trim().isEmpty) {
    throw SkillParseException('Missing required "name" in frontmatter');
  }
  return SkillFrontmatter(name: name, description: description ?? '');
}

String _unquote(String v) {
  if (v.length >= 2) {
    final first = v.codeUnitAt(0);
    final last = v.codeUnitAt(v.length - 1);
    if ((first == 0x22 && last == 0x22) || (first == 0x27 && last == 0x27)) {
      return v.substring(1, v.length - 1);
    }
  }
  return v;
}

class TarballPayload {
  TarballPayload({required this.entries});
  final Map<String, Uint8List> entries;
}

class SkillFetchService {
  SkillFetchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, _CacheEntry> _cache = {};
  static const _cacheTtl = Duration(hours: 1);

  Future<TarballPayload> fetchTarball(SkillRepo repo) async {
    final key = '${repo.owner}/${repo.name}@${repo.branch}';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return cached.payload;
    }
    final payload = await _downloadAndDecode(repo);
    _cache[key] = _CacheEntry(payload, DateTime.now());
    return payload;
  }

  Future<TarballPayload> _downloadAndDecode(SkillRepo repo) async {
    final url = Uri.parse(
      'https://codeload.github.com/${repo.owner}/${repo.name}/tar.gz/${repo.branch}',
    );
    final http.Response resp;
    try {
      resp = await _client.get(url);
    } catch (e) {
      throw SkillFetchException(
        'Network error for ${repo.fullName}: $e',
        e,
      );
    }
    if (resp.statusCode != 200) {
      throw SkillFetchException(
        'GitHub tarball HTTP ${resp.statusCode} for ${repo.fullName}',
      );
    }
    try {
      final gunzipped = GZipDecoder().decodeBytes(resp.bodyBytes);
      final archive = TarDecoder().decodeBytes(gunzipped);
      final entries = <String, Uint8List>{};
      String? prefix;
      for (final file in archive) {
        if (!file.isFile) continue;
        final fullName = file.name;
        prefix ??= '${fullName.split('/').first}/';
        if (!fullName.startsWith(prefix)) continue;
        final rel = fullName.substring(prefix.length);
        if (rel.isEmpty) continue;
        entries[rel] = Uint8List.fromList(file.content as List<int>);
      }
      return TarballPayload(entries: entries);
    } catch (e) {
      throw SkillFetchException(
        'Failed to decode tarball for ${repo.fullName}',
        e,
      );
    }
  }

  Future<List<DiscoverableSkill>> listSkills(SkillRepo repo) async {
    final payload = await fetchTarball(repo);
    final byDir = <String, Uint8List>{};
    for (final entry in payload.entries.entries) {
      final parts = entry.key.split('/');
      if (parts.length >= 2 && parts.last == 'SKILL.md') {
        byDir[parts.sublist(0, parts.length - 1).join('/')] = entry.value;
      }
    }
    final result = <DiscoverableSkill>[];
    for (final e in byDir.entries) {
      final dir = e.key;
      final basename = p.basename(dir);
      try {
        final fm = parseSkillFrontmatter(String.fromCharCodes(e.value));
        result.add(DiscoverableSkill(
          key: '${repo.owner}/${repo.name}:$basename',
          name: fm.name,
          description: fm.description,
          directory: dir,
          readmeUrl:
              'https://github.com/${repo.owner}/${repo.name}/tree/${repo.branch}/$dir',
          repoOwner: repo.owner,
          repoName: repo.name,
          repoBranch: repo.branch,
        ));
      } on SkillParseException {
        continue;
      }
    }
    return result;
  }

  /// Returns the relative paths inside [directory] (e.g. `subdir/foo`) inside
  /// the tarball, with [directory] stripped from the keys.
  Future<Map<String, Uint8List>> downloadSkillFiles(
    SkillRepo repo,
    String directory,
  ) async {
    final payload = await fetchTarball(repo);
    final prefix = '$directory/';
    final out = <String, Uint8List>{};
    for (final e in payload.entries.entries) {
      if (e.key.startsWith(prefix)) {
        out[e.key.substring(prefix.length)] = e.value;
      }
    }
    if (out.isEmpty) {
      throw SkillFetchException(
        'Skill directory "$directory" not found in ${repo.fullName}',
      );
    }
    return out;
  }

  /// Fetches the raw `SKILL.md` for an installed skill. Returns null on 404.
  Future<String?> fetchRawSkillMd({
    required String owner,
    required String name,
    required String branch,
    required String directory,
  }) async {
    final url = Uri.parse(
      'https://raw.githubusercontent.com/$owner/$name/$branch/$directory/SKILL.md',
    );
    final resp = await _client.get(url);
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw SkillFetchException(
        'raw SKILL.md HTTP ${resp.statusCode} for $owner/$name',
      );
    }
    return resp.body;
  }

  void close() => _client.close();
}

class _CacheEntry {
  _CacheEntry(this.payload, this.fetchedAt);
  final TarballPayload payload;
  final DateTime fetchedAt;
}
