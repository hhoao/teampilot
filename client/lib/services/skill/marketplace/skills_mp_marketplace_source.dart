import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../repositories/app_settings_repository.dart';
import 'skill_marketplace_source.dart';

class SkillsMpMarketplaceSource implements SkillMarketplaceSource {
  SkillsMpMarketplaceSource({
    http.Client? client,
    required AppSettingsRepository settings,
  }) : _client = client ?? http.Client(),
       _settings = settings;

  static const _apiBase = 'https://skillsmp.com/api/v1';

  final http.Client _client;
  final AppSettingsRepository _settings;

  @override
  String get id => 'skillsMp';

  @override
  String get label => 'SkillsMP';

  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities(
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
    languageChoices: [
      'zh',
      'en',
      'ja',
      'ko',
      'es',
      'fr',
      'de',
      'pt',
      'ru',
    ],
  );

  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async {
    final key = await _settings.loadSkillsMpApiKey();
    final params = <String, String>{
      'q': query.query,
      'page': '${query.page}',
      'limit': '${query.limit}',
      if (query.sortBy != null && query.sortBy!.isNotEmpty)
        'sortBy': query.sortBy!,
      if (query.category != null && query.category!.isNotEmpty)
        'category': query.category!,
      if (query.occupation != null && query.occupation!.isNotEmpty)
        'occupation': query.occupation!,
      if (query.language != null && query.language!.isNotEmpty)
        'language': query.language!,
    };
    final uri = Uri.parse('$_apiBase/skills/search').replace(
      queryParameters: params,
    );
    final headers = <String, String>{
      if (key != null && key.isNotEmpty) 'Authorization': 'Bearer $key',
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
      throw MarketplaceFetchException(
        'SkillsMP HTTP ${resp.statusCode}',
      );
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
          ),
        );
      }
      return MarketplaceSearchResult(
        skills: skills,
        hasNext: pagination['hasNext'] == true,
        total: (pagination['total'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      throw MarketplaceFetchException('SkillsMP parse error: $e', e);
    }
  }

  static String _ownerOf(String githubUrl) {
    final parts = Uri.tryParse(githubUrl)?.pathSegments ?? const [];
    return parts.length >= 2 ? parts[0] : '';
  }

  static String _repoOf(String githubUrl) {
    final parts = Uri.tryParse(githubUrl)?.pathSegments ?? const [];
    return parts.length >= 2 ? parts[1] : '';
  }

  @override
  Future<void> setApiKey(String key) async {
    final trimmed = key.trim();
    await _settings.saveSkillsMpApiKey(trimmed.isEmpty ? null : trimmed);
  }

  void close() => _client.close();
}
