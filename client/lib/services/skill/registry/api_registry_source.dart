import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../models/catalog/catalog_types.dart';
import '../../../models/skill_registry_source.dart';
import '../marketplace/skill_marketplace_source.dart';
import '../skills_sh_service.dart';
import 'skill_registry_source.dart';

/// API 注册源：按 [SkillRegistryProtocol] 实现 skills.sh / SkillsMP 两种协议。
/// baseUrl / apiToken / browseQuery 均来自配置，支持自定义源。
class ApiRegistrySource implements SkillRegistrySource {
  ApiRegistrySource(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  final SkillRegistrySourceConfig config;
  final http.Client _client;

  SkillRegistryProtocol get protocol =>
      config.protocol ?? SkillRegistryProtocol.skillsSh;

  String get _baseUrl {
    final url = config.baseUrlOrDefault;
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  @override
  String get id => config.id;

  @override
  String get label => config.label;

  @override
  bool get enabled => config.enabled;

  @override
  SkillRegistryKind get kind => SkillRegistryKind.api;

  @override
  MarketplaceCapabilities get capabilities => switch (protocol) {
    SkillRegistryProtocol.skillsSh => const MarketplaceCapabilities(),
    SkillRegistryProtocol.skillsMp => const MarketplaceCapabilities(
      supportsCategory: true,
      supportsOccupation: true,
      supportsLanguage: true,
      supportsSortBy: true,
      categoryChoices: {
        'data-ai': 'Data & AI',
        'devops': 'DevOps',
        'web-development': 'Web Development',
        'automation': 'Automation',
        'data-analysis': 'Data Analysis',
        'marketing': 'Marketing',
        'productivity': 'Productivity',
        'design': 'Design',
        'business': 'Business',
        'education': 'Education',
      },
      occupationChoices: {
        'software-developers': 'Software Developers',
        'data-scientists': 'Data Scientists',
        'devops-engineers': 'DevOps Engineers',
        'project-managers': 'Project Managers',
        'product-managers': 'Product Managers',
        'marketing-specialists': 'Marketing Specialists',
        'content-writers': 'Content Writers',
        'data-analysts': 'Data Analysts',
        'it-support-specialists': 'IT Support',
        'ux-designers': 'UX Designers',
        'quality-assurance-analysts': 'QA Analysts',
        'security-analysts': 'Security Analysts',
        'sales-representatives': 'Sales',
        'customer-service-reps': 'Customer Service',
        'researchers': 'Researchers',
      },
      languageChoices: ['zh', 'en', 'ja', 'ko', 'es', 'fr', 'de', 'pt', 'ru'],
    ),
  };

  @override
  Future<SkillRegistryPage> search(SkillRegistryQuery query) async {
    switch (protocol) {
      case SkillRegistryProtocol.skillsSh:
        return _searchSkillsSh(query);
      case SkillRegistryProtocol.skillsMp:
        return _searchSkillsMp(query);
    }
  }

  Future<SkillRegistryPage> _searchSkillsSh(SkillRegistryQuery query) async {
    final q = query.query.trim().isEmpty
        ? (config.browseQuery ?? 'ai')
        : query.query;
    final service = SkillsShService(client: _client, baseUrl: _baseUrl);
    final res = await service.search(
      q,
      limit: query.limit,
      offset: (query.page - 1) * query.limit,
    );
    return SkillRegistryPage(
      entries: res.skills
          .map(
            (e) => MarketplaceSkill(
              key: e.key,
              name: e.name,
              description: '',
              repoOwner: e.repoOwner,
              repoName: e.repoName,
              repoBranch: e.repoBranch,
              directory: e.directory,
              githubUrl:
                  e.readmeUrl ??
                  'https://github.com/${e.repoOwner}/${e.repoName}',
              installs: e.installs,
              metrics: e.metrics,
            ),
          )
          .toList(),
      hasNext: (query.page * query.limit) < res.totalCount,
      total: res.totalCount,
    );
  }

  Future<SkillRegistryPage> _searchSkillsMp(SkillRegistryQuery query) async {
    final q = query.query.trim();
    final effectiveQ = q.isEmpty ? 'a' : q;
    final params = <String, String>{
      'q': effectiveQ,
      'page': '${query.page}',
      'limit': '${query.limit}',
      if (q.isEmpty) 'sortBy': 'stars',
      if (query.sortBy != null && query.sortBy!.isNotEmpty)
        'sortBy': query.sortBy!,
      if (query.category != null && query.category!.isNotEmpty)
        'category': query.category!,
      if (query.occupation != null && query.occupation!.isNotEmpty)
        'occupation': query.occupation!,
      if (query.language != null && query.language!.isNotEmpty)
        'language': query.language!,
    };
    final uri = Uri.parse(
      '$_baseUrl/skills/search',
    ).replace(queryParameters: params);
    final headers = <String, String>{
      if (config.hasApiToken)
        'Authorization': 'Bearer ${config.apiToken!.trim()}',
    };

    final http.Response resp;
    try {
      resp = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      throw MarketplaceFetchException('SkillsMP network error: $e', e);
    }
    if (resp.statusCode == 429) {
      throw MarketplaceQuotaException('SkillsMP daily quota exhausted');
    }
    if (resp.statusCode != 200) {
      throw MarketplaceFetchException('SkillsMP HTTP ${resp.statusCode}');
    }
    try {
      final body = json.decode(resp.body) as Map<String, dynamic>;
      final data = body['data'] as Map<String, dynamic>? ?? const {};
      final rawSkills = data['skills'] as List<dynamic>? ?? const [];
      final pagination =
          data['pagination'] as Map<String, dynamic>? ?? const {};
      final skills = <MarketplaceSkill>[];
      for (final raw in rawSkills) {
        final m = (raw as Map).cast<String, Object?>();
        final githubUrl = (m['githubUrl'] as String?) ?? '';
        final owner = _ownerOf(githubUrl);
        final repo = _repoOf(githubUrl);
        if (owner.isEmpty || repo.isEmpty) continue;
        skills.add(
          MarketplaceSkill(
            key: (m['id'] as String?) ?? githubUrl,
            name: (m['name'] as String?) ?? '',
            description: (m['description'] as String?) ?? '',
            repoOwner: owner,
            repoName: repo,
            githubUrl: githubUrl,
            stars: (m['stars'] as num?)?.toInt(),
            updatedAt: (m['updatedAt'] as num?)?.toInt(),
            contentLanguage: (m['contentLanguage'] as String?)?.trim(),
            metrics: CatalogMetrics(
              rating: (m['rating'] as num?)?.toDouble(),
              ratingCount: (m['ratingCount'] as num?)?.toInt(),
              updatedAtMs: _epochMilliseconds(m['updatedAt']),
              publishedAtMs: _epochMilliseconds(m['publishedAt']),
            ),
          ),
        );
      }
      return SkillRegistryPage(
        entries: skills,
        hasNext: pagination['hasNext'] == true,
        total: (pagination['total'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      throw MarketplaceFetchException('SkillsMP parse error: $e', e);
    }
  }

  @override
  Future<void> testConnection() async {
    await search(const SkillRegistryQuery(page: 1, limit: 1));
  }

  @override
  Future<void> setApiKey(String key) async {}

  static String _ownerOf(String githubUrl) {
    final parts = Uri.tryParse(githubUrl)?.pathSegments ?? const [];
    return parts.length >= 2 ? parts[0] : '';
  }

  static String _repoOf(String githubUrl) {
    final parts = Uri.tryParse(githubUrl)?.pathSegments ?? const [];
    return parts.length >= 2 ? parts[1] : '';
  }

  static int? _epochMilliseconds(Object? value) {
    final numeric = value is num ? value.toInt() : int.tryParse('$value');
    if (numeric != null) {
      return numeric.abs() < 100000000000 ? numeric * 1000 : numeric;
    }
    final parsed = DateTime.tryParse('$value');
    return parsed?.millisecondsSinceEpoch;
  }
}
