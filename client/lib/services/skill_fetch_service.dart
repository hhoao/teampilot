import 'dart:convert';
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
  String toString() =>
      cause != null ? 'SkillFetchException: $message ($cause)' : 'SkillFetchException: $message';
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

/// Branch fallbacks aligned with cc-switch-1 (`download_repo`).
List<String> skillRepoBranchCandidates(String configuredBranch) {
  final branches = <String>[];
  final trimmed = configuredBranch.trim();
  if (trimmed.isNotEmpty && trimmed.toLowerCase() != 'head') {
    branches.add(trimmed);
  }
  if (!branches.contains('main')) branches.add('main');
  if (!branches.contains('master')) branches.add('master');
  return branches;
}

/// Scan tarball paths for SKILL.md (recursive, includes repo root).
List<DiscoverableSkill> discoverSkillsInTarballEntries({
  required Map<String, Uint8List> entries,
  required SkillRepo repo,
  required String resolvedBranch,
}) {
  const skillMd = 'SKILL.md';
  const skillMdSuffix = '/$skillMd';
  final result = <DiscoverableSkill>[];
  for (final entry in entries.entries) {
    final path = entry.key;
    if (path != skillMd && !path.endsWith(skillMdSuffix)) continue;

    final dir = path == skillMd
        ? repo.name
        : path.substring(0, path.length - skillMdSuffix.length);
    final installBasename = p.basename(dir);
    final displayName = _skillDisplayName(entry.value, installBasename);

    final docPath = path;
    result.add(
      DiscoverableSkill(
        key: '${repo.owner}/${repo.name}:$dir',
        name: displayName,
        description: _skillDescription(entry.value),
        directory: dir,
        readmeUrl:
            'https://github.com/${repo.owner}/${repo.name}/tree/$resolvedBranch/$docPath',
        repoOwner: repo.owner,
        repoName: repo.name,
        repoBranch: resolvedBranch,
      ),
    );
  }
  return result;
}

String _skillDisplayName(Uint8List skillMdBytes, String fallback) {
  try {
    return parseSkillFrontmatter(String.fromCharCodes(skillMdBytes)).name;
  } on SkillParseException {
    return fallback;
  }
}

String _skillDescription(Uint8List skillMdBytes) {
  try {
    return parseSkillFrontmatter(String.fromCharCodes(skillMdBytes)).description;
  } on SkillParseException {
    return '';
  }
}

class SkillFetchService {
  SkillFetchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Latest commit SHA for [branch] (null if branch missing or API error).
  Future<String?> fetchBranchCommitSha(
    String owner,
    String name,
    String branch,
  ) async {
    final url = Uri.parse(
      'https://api.github.com/repos/$owner/$name/commits/$branch',
    );
    try {
      final resp = await _client.get(
        url,
        headers: const {'Accept': 'application/vnd.github+json'},
      );
      if (resp.statusCode != 200) return null;
      final body = json.decode(resp.body) as Map<String, dynamic>;
      return body['sha'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Downloads and decodes a repo tarball (no in-memory cache).
  Future<({Map<String, Uint8List> entries, String branch})> downloadRepoEntries(
    SkillRepo repo,
  ) async {
    Object? lastError;
    for (final branch in skillRepoBranchCandidates(repo.branch)) {
      try {
        final payload = await _downloadTarball(repo, branch);
        return (entries: payload.entries, branch: branch);
      } catch (e) {
        lastError = e;
        try {
          final payload = await _downloadZipArchive(repo, branch);
          return (entries: payload.entries, branch: branch);
        } catch (e2) {
          lastError = e2;
        }
      }
    }
    throw SkillFetchException(
      'Failed to download ${repo.fullName} (tried ${skillRepoBranchCandidates(repo.branch).join(", ")})',
      lastError,
    );
  }

  Future<TarballPayload> _downloadTarball(SkillRepo repo, String branch) async {
    final url = Uri.parse(
      'https://codeload.github.com/${repo.owner}/${repo.name}/tar.gz/$branch',
    );
    final http.Response resp;
    try {
      resp = await _client.get(url);
    } catch (e) {
      throw SkillFetchException(
        'Network error for ${repo.fullName}@$branch: $e',
        e,
      );
    }
    if (resp.statusCode != 200) {
      throw SkillFetchException(
        'GitHub tarball HTTP ${resp.statusCode} for ${repo.fullName}@$branch',
      );
    }
    try {
      final gunzipped = GZipDecoder().decodeBytes(resp.bodyBytes);
      final archive = TarDecoder().decodeBytes(gunzipped);
      return TarballPayload(entries: _entriesFromArchive(archive));
    } catch (e) {
      throw SkillFetchException(
        'Failed to decode tarball for ${repo.fullName}@$branch',
        e,
      );
    }
  }

  Future<TarballPayload> _downloadZipArchive(SkillRepo repo, String branch) async {
    final url = Uri.parse(
      'https://github.com/${repo.owner}/${repo.name}/archive/refs/heads/$branch.zip',
    );
    final http.Response resp;
    try {
      resp = await _client.get(url);
    } catch (e) {
      throw SkillFetchException(
        'Network error (zip) for ${repo.fullName}@$branch: $e',
        e,
      );
    }
    if (resp.statusCode != 200) {
      throw SkillFetchException(
        'GitHub zip HTTP ${resp.statusCode} for ${repo.fullName}@$branch',
      );
    }
    try {
      final archive = ZipDecoder().decodeBytes(resp.bodyBytes);
      return TarballPayload(entries: _entriesFromArchive(archive));
    } catch (e) {
      throw SkillFetchException(
        'Failed to decode zip for ${repo.fullName}@$branch',
        e,
      );
    }
  }

  Map<String, Uint8List> _entriesFromArchive(Archive archive) {
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
    return entries;
  }

  /// Returns the relative paths inside [directory] from a fresh tarball download.
  Future<Map<String, Uint8List>> downloadSkillFilesFromNetwork(
    SkillRepo repo,
    String directory,
  ) async {
    final downloaded = await downloadRepoEntries(repo);
    final prefix = '$directory/';
    final out = <String, Uint8List>{};
    for (final e in downloaded.entries.entries) {
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
