import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/skill.dart';
import 'skill_fetch_service.dart';

class SkillsShResult {
  const SkillsShResult({
    required this.skills,
    required this.totalCount,
    required this.query,
  });
  final List<SkillsShEntry> skills;
  final int totalCount;
  final String query;
}

class SkillsShService {
  SkillsShService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<SkillsShResult> search(
    String query, {
    int limit = 20,
    int offset = 0,
  }) async {
    final uri = Uri.parse(
      'https://skills.sh/api/search',
    ).replace(queryParameters: {
      'q': query,
      'limit': '$limit',
      'offset': '$offset',
    });
    final resp = await _client
        .get(uri)
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw SkillFetchException('skills.sh HTTP ${resp.statusCode}');
    }
    final body = json.decode(resp.body) as Map<String, dynamic>;
    final list = (body['skills'] as List<dynamic>? ?? []);
    final entries = <SkillsShEntry>[];
    for (final raw in list) {
      final m = (raw as Map).cast<String, Object?>();
      final source = (m['source'] as String?) ?? '';
      final parts = source.split('/');
      if (parts.length != 2) continue;
      final owner = parts[0];
      final repo = parts[1];
      // Filter non-GitHub sources (e.g. mcp-hub.momenta.works).
      if (owner.contains('.') || repo.contains('.')) continue;
      final skillId = (m['skillId'] as String?) ?? '';
      entries.add(
        SkillsShEntry(
          key: (m['id'] as String?) ?? '$owner/$repo:$skillId',
          name: (m['name'] as String?) ?? skillId,
          directory: skillId,
          repoOwner: owner,
          repoName: repo,
          repoBranch: 'main',
          readmeUrl: 'https://github.com/$owner/$repo',
          installs: (m['installs'] as int?) ?? 0,
        ),
      );
    }
    return SkillsShResult(
      skills: entries,
      totalCount: (body['count'] as int?) ?? entries.length,
      query: (body['query'] as String?) ?? query,
    );
  }

  void close() => _client.close();
}
