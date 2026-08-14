# Skill Marketplace 统一抽象（skills.sh + SkillsMP）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Skills 发现页的远程技能市场改为注册表驱动的统一抽象：`SkillMarketplaceSource` 接口 + 共享面板，skills.sh 适配为第一个实现，新增 SkillsMP（category/occupation/language/sortBy 过滤 + stars/updatedAt 元数据 + 可选 API Key）为第二个实现。

**Architecture:** 注册表 `SkillMarketplaceRegistry.builtIn()` 产出 `List<SkillMarketplaceSource>`（app_shell 注入 `SkillCubit`）；cubit 按 sourceId 分槽持有 `Map<String, MarketplaceSearchState>`；一个共享面板 `SkillMarketplacePanel` 按 `source.capabilities` 渲染过滤控件；安装语义单一分叉点（`directory` 有值 → `installFromDiscovery`，否则 `addRepo`）。

**Tech Stack:** Flutter/Dart、flutter_bloc、`package:http`（MockClient 测试）、shared_preferences（`AppSettingsRepository`）、l10n arb（en/zh）。

## Global Constraints

- 每任务结束跑该任务测试：`cd client && flutter test <test文件>`；全量收尾：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`。
- l10n 只改 `client/lib/l10n/app_en.arb` 与 `app_zh.arb`，改后跑 `cd client && flutter gen-l10n`（生成文件勿手改）。
- 不向后兼容：`SkillsShSearchState`、`searchSkillsSh`、`loadMoreSkillsSh`、`installSkillsShEntry`、`skillsShInstallKey`、`SkillSearchSource.skillsSh` 一律删除，调用点一次性迁移。
- 不修改：`SkillsShService`（`client/lib/services/skill/skills_sh_service.dart`）、`SkillDiscoverCard`、`SkillInstallService`/`SkillRepoService`/`SkillAcquisitionEngine` 本体、repos 本地发现流程。
- 不做 GitHub API 富化（无 forks/下载量）；SkillsMP 分类/职业用精编静态表（无列表端点）。
- 新面板/卡片/源文件 < 400 行；超过则拆 section 文件。

---

### Task 1: 市场模型、异常与注册表

**Files:**
- Create: `client/lib/services/skill/marketplace/skill_marketplace_source.dart`
- Create: `client/lib/services/skill/marketplace/skill_marketplace_registry.dart`
- Test: `client/test/services/skill/marketplace/skill_marketplace_source_test.dart`

**Interfaces:**
- Consumes: `SkillsShService`（`search(q, {limit, offset}) → SkillsShResult`，已有）、`AppSettingsRepository`（Task 4 加入 `loadSkillsMpApiKey/saveSkillsMpApiKey`，本任务代码引用其参数类型即可）、`SkillsShMarketplaceSource`/`SkillsMpMarketplaceSource`（Task 2/3 创建）。
- Produces: `MarketplaceSkill`、`MarketplaceCapabilities`、`MarketplaceSearchQuery`、`MarketplaceSearchResult`、`MarketplaceFetchException`、`MarketplaceQuotaException`、常量 `marketplaceQuotaErrorKey`、接口 `SkillMarketplaceSource`、`SkillMarketplaceRegistry.builtIn({required AppSettingsRepository settings, SkillsShService? skillsSh})`。

- [ ] **Step 1: 写失败测试**

`client/test/services/skill/marketplace/skill_marketplace_source_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';

void main() {
  test('MarketplaceSkill defaults repoBranch to main', () {
    const skill = MarketplaceSkill(
      key: 'k',
      name: 'n',
      description: 'd',
      repoOwner: 'o',
      repoName: 'r',
      githubUrl: 'https://github.com/o/r',
    );
    expect(skill.repoBranch, 'main');
    expect(skill.isInstalledDirectly, isFalse);
  });

  test('isInstalledDirectly true when directory present', () {
    const skill = MarketplaceSkill(
      key: 'k',
      name: 'n',
      description: 'd',
      repoOwner: 'o',
      repoName: 'r',
      directory: 'skills/x',
      githubUrl: 'https://github.com/o/r',
    );
    expect(skill.isInstalledDirectly, isTrue);
  });

  test('MarketplaceCapabilities.hasAnyFilter', () {
    const none = MarketplaceCapabilities();
    expect(none.hasAnyFilter, isFalse);
    const all = MarketplaceCapabilities(
      supportsCategory: true,
      supportsOccupation: true,
      supportsLanguage: true,
      supportsSortBy: true,
      categoryChoices: {'data-ai': 'Data & AI'},
      occupationChoices: {'software-developers': 'Software Developers'},
      languageChoices: ['zh', 'en'],
    );
    expect(all.hasAnyFilter, isTrue);
  });

  test('quota error key is stable', () {
    expect(marketplaceQuotaErrorKey, 'marketplace_quota_error');
  });

  test('MarketplaceQuotaException is a MarketplaceFetchException', () {
    final e = MarketplaceQuotaException('quota');
    expect(e, isA<MarketplaceFetchException>());
    expect(e.message, 'quota');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/services/skill/marketplace/skill_marketplace_source_test.dart`
Expected: FAIL（缺 `MarketplaceSkill` 等符号，编译错误）

- [ ] **Step 3: 实现模型与接口**

只创建 `client/lib/services/skill/marketplace/skill_marketplace_source.dart`（注册表文件在 Task 3 Step 5 创建，因为其 import 依赖 Task 2/3 的实现类）：

`client/lib/services/skill/marketplace/skill_marketplace_source.dart`：

```dart
const marketplaceQuotaErrorKey = 'marketplace_quota_error';

class MarketplaceSkill {
  const MarketplaceSkill({
    required this.key,
    required this.name,
    required this.description,
    required this.repoOwner,
    required this.repoName,
    this.repoBranch = 'main',
    this.directory,
    required this.githubUrl,
    this.installs,
    this.stars,
    this.updatedAt,
    this.contentLanguage,
  });

  final String key;
  final String name;
  final String description;
  final String repoOwner;
  final String repoName;
  final String repoBranch;

  /// SKILL.md 所在 repo 内子目录。null 表示无法直接定位（如 SkillsMP），
  /// 安装需降级为把整个 repo 加入仓库源。
  final String? directory;
  final String githubUrl;

  /// skills.sh 源的安装次数。
  final int? installs;

  /// SkillsMP 源的 GitHub stars 与最近更新时间（Unix 秒）。
  final int? stars;
  final int? updatedAt;
  final String? contentLanguage;

  bool get isInstalledDirectly =>
      directory != null && directory!.trim().isNotEmpty;
}

class MarketplaceCapabilities {
  const MarketplaceCapabilities({
    this.supportsCategory = false,
    this.supportsOccupation = false,
    this.supportsLanguage = false,
    this.supportsSortBy = false,
    this.categoryChoices = const {},
    this.occupationChoices = const {},
    this.languageChoices = const [],
  });

  final bool supportsCategory;
  final bool supportsOccupation;
  final bool supportsLanguage;
  final bool supportsSortBy;

  /// slug -> 展示标签。slug 直接作为 API 参数值。
  final Map<String, String> categoryChoices;
  final Map<String, String> occupationChoices;
  final List<String> languageChoices;

  bool get hasAnyFilter =>
      supportsCategory ||
      supportsOccupation ||
      supportsLanguage ||
      supportsSortBy;
}

class MarketplaceSearchQuery {
  const MarketplaceSearchQuery({
    required this.query,
    this.page = 1,
    this.limit = 20,
    this.category,
    this.occupation,
    this.language,
    this.sortBy,
  });

  final String query;
  final int page;
  final int limit;
  final String? category;
  final String? occupation;
  final String? language;

  /// 'stars' | 'recent'（SkillsMP 专有）。
  final String? sortBy;
}

class MarketplaceSearchResult {
  const MarketplaceSearchResult({
    required this.skills,
    this.hasNext = false,
    this.total = 0,
  });

  final List<MarketplaceSkill> skills;
  final bool hasNext;
  final int total;
}

class MarketplaceFetchException implements Exception {
  MarketplaceFetchException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => cause != null
      ? 'MarketplaceFetchException: $message ($cause)'
      : 'MarketplaceFetchException: $message';
}

class MarketplaceQuotaException extends MarketplaceFetchException {
  MarketplaceQuotaException(super.message);
}

abstract class SkillMarketplaceSource {
  String get id;
  String get label;
  MarketplaceCapabilities get capabilities;

  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query);

  Future<void> setApiKey(String key) async {}
}
```

`client/lib/services/skill/marketplace/skill_marketplace_registry.dart`（本任务不创建，见 Task 3 Step 5）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && flutter test test/services/skill/marketplace/skill_marketplace_source_test.dart`
Expected: PASS（仅模型文件，无外部依赖）

- [ ] **Step 5: 提交**

```bash
cd client && flutter test test/services/skill/marketplace/skill_marketplace_source_test.dart
git add client/lib/services/skill/marketplace/skill_marketplace_source.dart client/test/services/skill/marketplace/skill_marketplace_source_test.dart
git commit -m "feat(skills): marketplace unified models, capabilities and exceptions"
```

---

### Task 2: SkillsMP 市场源（HTTP + 解析 + 配额 + 静态过滤表）

**Files:**
- Create: `client/lib/services/skill/marketplace/skills_mp_marketplace_source.dart`
- Test: `client/test/services/skill/marketplace/skills_mp_marketplace_source_test.dart`

**Interfaces:**
- Consumes: `MarketplaceSkill/Capabilities/Query/Result`、`MarketplaceFetchException`、`MarketplaceQuotaException`（Task 1）；`AppSettingsRepository.loadSkillsMpApiKey/saveSkillsMpApiKey`（Task 4 实现，本任务源码引用方法即可，测试用 `InMemoryAppSettingsRepository` 时先临时继承并手写这两个方法？**不** —— Task 4 先于本任务实现接口方法会导致顺序问题。**调整**：Task 4 提升为 Task 2a，先加 settings 方法，再写本任务。）

**顺序修正**：先做 settings（原 Task 4）→ 再做 SkillsMP 源（本 Task）→ 再做 skills.sh 适配（原 Task 3）。

- [ ] **Step 1: 写失败测试**

`client/test/services/skill/marketplace/skills_mp_marketplace_source_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/marketplace/skills_mp_marketplace_source.dart';

void main() {
  const skillsJson = {
    'success': true,
    'data': {
      'skills': [
        {
          'id': 's1',
          'name': 'seo-audit',
          'author': 'coreyhaines31',
          'description': 'Run an SEO audit',
          'contentLanguage': 'en',
          'githubUrl': 'https://github.com/coreyhaines31/marketingskills',
          'skillUrl': 'https://skillsmp.com/skill/s1',
          'stars': 186,
          'updatedAt': 1720000000,
        },
      ],
      'pagination': {'hasNext': true, 'total': 42},
    },
    'meta': {'requestId': 'r1', 'responseTimeMs': 10},
  };

  InMemoryAppSettingsRepository settings({String? key}) =>
      InMemoryAppSettingsRepository(skillsMpApiKey: key);

  late Uri lastUri;
  late Map<String, String> lastHeaders;
  MockClient client(MockClientHandler handler) {
    return MockClient((request) async {
      lastUri = request.url;
      lastHeaders = request.headers;
      return handler(request);
    });
  }

  test('sends all query params and parses result', () async {
    final source = SkillsMpMarketplaceSource(
      client: client((_) async => http.Response(jsonEncode(skillsJson), 200)),
      settings: settings(),
    );
    final res = await source.search(const MarketplaceSearchQuery(
      query: 'seo',
      page: 2,
      category: 'data-ai',
      occupation: 'software-developers',
      language: 'zh',
      sortBy: 'recent',
    ));
    expect(lastUri.path, '/api/v1/skills/search');
    expect(lastUri.queryParameters['q'], 'seo');
    expect(lastUri.queryParameters['page'], '2');
    expect(lastUri.queryParameters['limit'], '20');
    expect(lastUri.queryParameters['sortBy'], 'recent');
    expect(lastUri.queryParameters['category'], 'data-ai');
    expect(lastUri.queryParameters['occupation'], 'software-developers');
    expect(lastUri.queryParameters['language'], 'zh');
    expect(res.skills, hasLength(1));
    final s = res.skills.first;
    expect(s.key, 's1');
    expect(s.name, 'seo-audit');
    expect(s.repoOwner, 'coreyhaines31');
    expect(s.repoName, 'marketingskills');
    expect(s.directory, isNull);
    expect(s.isInstalledDirectly, isFalse);
    expect(s.stars, 186);
    expect(s.updatedAt, 1720000000);
    expect(s.contentLanguage, 'en');
    expect(s.installs, isNull);
    expect(res.hasNext, isTrue);
    expect(res.total, 42);
  });

  test('omits empty filters and sends Bearer when key set', () async {
    final source = SkillsMpMarketplaceSource(
      client: client((_) async => http.Response(jsonEncode(skillsJson), 200)),
      settings: settings(key: 'sk_live_abc'),
    );
    await source.search(const MarketplaceSearchQuery(query: 'seo'));
    expect(lastUri.queryParameters.containsKey('sortBy'), isFalse);
    expect(lastUri.queryParameters.containsKey('category'), isFalse);
    expect(lastHeaders['Authorization'], 'Bearer sk_live_abc');
  });

  test('no Authorization header without key', () async {
    final source = SkillsMpMarketplaceSource(
      client: client((_) async => http.Response(jsonEncode(skillsJson), 200)),
      settings: settings(),
    );
    await source.search(const MarketplaceSearchQuery(query: 'seo'));
    expect(lastHeaders.containsKey('Authorization'), isFalse);
  });

  test('429 throws MarketplaceQuotaException', () async {
    final source = SkillsMpMarketplaceSource(
      client: client(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'error': {'code': 'DAILY_QUOTA_EXCEEDED', 'message': 'quota'},
          }),
          429,
        ),
      ),
      settings: settings(),
    );
    expect(
      () => source.search(const MarketplaceSearchQuery(query: 'seo')),
      throwsA(isA<MarketplaceQuotaException>()),
    );
  });

  test('non-2xx throws MarketplaceFetchException', () async {
    final source = SkillsMpMarketplaceSource(
      client: client(
        (_) async => http.Response(
          jsonEncode({
            'success': false,
            'error': {'code': 'INTERNAL_ERROR', 'message': 'boom'},
          }),
          500,
        ),
      ),
      settings: settings(),
    );
    expect(
      () => source.search(const MarketplaceSearchQuery(query: 'seo')),
      throwsA(isA<MarketplaceFetchException>()),
    );
  });

  test('invalid JSON throws MarketplaceFetchException', () async {
    final source = SkillsMpMarketplaceSource(
      client: client((_) async => http.Response('not json', 200)),
      settings: settings(),
    );
    expect(
      () => source.search(const MarketplaceSearchQuery(query: 'seo')),
      throwsA(isA<MarketplaceFetchException>()),
    );
  });

  test('capabilities enable all filters with curated choices', () {
    final source = SkillsMpMarketplaceSource(
      client: client((_) async => http.Response('{}', 200)),
      settings: settings(),
    );
    final caps = source.capabilities;
    expect(caps.supportsCategory, isTrue);
    expect(caps.supportsOccupation, isTrue);
    expect(caps.supportsLanguage, isTrue);
    expect(caps.supportsSortBy, isTrue);
    expect(caps.categoryChoices['data-ai'], isNotNull);
    expect(caps.occupationChoices['software-developers'], isNotNull);
    expect(caps.languageChoices, contains('zh'));
    expect(source.id, 'skillsMp');
  });

  test('setApiKey persists via settings and trims empty', () async {
    final s = settings();
    final source = SkillsMpMarketplaceSource(
      client: client((_) async => http.Response('{}', 200)),
      settings: s,
    );
    await source.setApiKey('  sk_x  ');
    expect(await s.loadSkillsMpApiKey(), 'sk_x');
    await source.setApiKey('  ');
    expect(await s.loadSkillsMpApiKey(), isNull);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/services/skill/marketplace/skills_mp_marketplace_source_test.dart`
Expected: FAIL（编译错误：无 `SkillsMpMarketplaceSource`；`InMemoryAppSettingsRepository` 缺 `skillsMpApiKey` 参数 —— 先完成 settings 任务）

- [ ] **Step 3: 实现 SkillsMP 源**

`client/lib/services/skill/marketplace/skills_mp_marketplace_source.dart`：

```dart
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && flutter test test/services/skill/marketplace/skills_mp_marketplace_source_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/skill/marketplace/skills_mp_marketplace_source.dart client/test/services/skill/marketplace/skills_mp_marketplace_source_test.dart
git commit -m "feat(skills): SkillsMP marketplace source with filters and quota handling"
```

---

### Task 3: skills.sh 适配源 + 注册表落盘

**Files:**
- Create: `client/lib/services/skill/marketplace/skills_sh_marketplace_source.dart`
- Create: `client/lib/services/skill/marketplace/skill_marketplace_registry.dart`
- Test: `client/test/services/skill/marketplace/skills_sh_marketplace_source_test.dart`

**Interfaces:**
- Consumes: `SkillsShService.search`（返回 `SkillsShResult{skills: List<SkillsShEntry>, totalCount, query}`；`SkillsShEntry{key, name, directory, repoOwner, repoName, repoBranch, readmeUrl, installs}`）、Task 1 模型、Task 2 的 `SkillsMpMarketplaceSource`。
- Produces: `SkillsShMarketplaceSource`（id `skillsSh`）、`SkillMarketplaceRegistry.builtIn({required AppSettingsRepository settings, SkillsShService? skillsSh})`。

- [ ] **Step 1: 写失败测试**

`client/test/services/skill/marketplace/skills_sh_marketplace_source_test.dart`：

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/marketplace/skills_sh_marketplace_source.dart';
import 'package:teampilot/services/skill/skills_sh_service.dart';

void main() {
  MockClient clientWith(MockClientHandler handler) => MockClient(handler);

  SkillsShMarketplaceSource sourceWith(MockClientHandler handler) =>
      SkillsShMarketplaceSource(
        SkillsShService(client: clientWith(handler)),
      );

  test('maps entries to unified model with directory', () async {
    final source = sourceWith(
      (_) async => http.Response(
        jsonEncode({
          'skills': [
            {
              'id': 'sh1',
              'name': 'frontend-design',
              'skillId': 'skills/frontend-design',
              'source': 'anthropics/skills',
              'installs': 775800,
            },
          ],
          'count': 1200,
          'query': 'design',
        }),
        200,
      ),
    );
    final res = await source.search(
      const MarketplaceSearchQuery(query: 'design', page: 1, limit: 20),
    );
    expect(source.id, 'skillsSh');
    expect(source.capabilities.hasAnyFilter, isFalse);
    final s = res.skills.single;
    expect(s.key, 'sh1');
    expect(s.name, 'frontend-design');
    expect(s.directory, 'skills/frontend-design');
    expect(s.isInstalledDirectly, isTrue);
    expect(s.repoOwner, 'anthropics');
    expect(s.repoName, 'skills');
    expect(s.repoBranch, 'main');
    expect(s.installs, 775800);
    expect(s.stars, isNull);
    expect(res.total, 1200);
    expect(res.hasNext, isTrue);
  });

  test('hasNext false when page is beyond totalCount', () async {
    final source = sourceWith(
      (_) async => http.Response(
        jsonEncode({
          'skills': [
            {
              'id': 'sh1',
              'name': 'x',
              'skillId': 'x',
              'source': 'a/b',
              'installs': 0,
            },
          ],
          'count': 1,
          'query': 'x',
        }),
        200,
      ),
    );
    final res = await source.search(
      const MarketplaceSearchQuery(query: 'x', page: 1, limit: 20),
    );
    expect(res.hasNext, isFalse);
  });

  test('offset maps from page', () async {
    late Uri requested;
    final source = sourceWith((request) async {
      requested = request.url;
      return http.Response(
        jsonEncode({
          'skills': <Object>[],
          'count': 0,
          'query': 'q',
        }),
        200,
      );
    });
    await source.search(
      const MarketplaceSearchQuery(query: 'q', page: 3, limit: 20),
    );
    expect(requested.queryParameters['offset'], '40');
    expect(requested.queryParameters['limit'], '20');
  });

  test('setApiKey is a no-op', () async {
    final source = sourceWith(
      (_) async => http.Response('{}', 200),
    );
    await source.setApiKey('anything');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/services/skill/marketplace/skills_sh_marketplace_source_test.dart`
Expected: FAIL（无 `SkillsShMarketplaceSource`；`SkillsShService` 构造需要 `client` 参数 —— 已有）

- [ ] **Step 3: 实现适配源**

`client/lib/services/skill/marketplace/skills_sh_marketplace_source.dart`：

```dart
import '../skills_sh_service.dart';
import 'skill_marketplace_source.dart';

class SkillsShMarketplaceSource implements SkillMarketplaceSource {
  SkillsShMarketplaceSource(this._service);

  final SkillsShService _service;

  @override
  String get id => 'skillsSh';

  @override
  String get label => 'skills.sh';

  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async {
    final res = await _service.search(
      query.query,
      limit: query.limit,
      offset: (query.page - 1) * query.limit,
    );
    return MarketplaceSearchResult(
      skills: res.skills
          .map(
            (e) => MarketplaceSkill(
              key: e.key,
              name: e.name,
              description: '',
              repoOwner: e.repoOwner,
              repoName: e.repoName,
              repoBranch: e.repoBranch,
              directory: e.directory,
              githubUrl: e.readmeUrl ??
                  'https://github.com/${e.repoOwner}/${e.repoName}',
              installs: e.installs,
            ),
          )
          .toList(),
      hasNext: (query.page * query.limit) < res.totalCount,
      total: res.totalCount,
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && flutter test test/services/skill/marketplace/skills_sh_marketplace_source_test.dart`
Expected: PASS

- [ ] **Step 5: 创建注册表（Task 1 延期部分）**

`client/lib/services/skill/marketplace/skill_marketplace_registry.dart`：

```dart
import '../../../repositories/app_settings_repository.dart';
import '../skills_sh_service.dart';
import 'skill_marketplace_source.dart';
import 'skills_mp_marketplace_source.dart';
import 'skills_sh_marketplace_source.dart';

abstract final class SkillMarketplaceRegistry {
  static List<SkillMarketplaceSource> builtIn({
    required AppSettingsRepository settings,
    SkillsShService? skillsSh,
  }) => [
    SkillsShMarketplaceSource(skillsSh ?? SkillsShService()),
    SkillsMpMarketplaceSource(settings: settings),
  ];
}
```

`client/test/services/skill/marketplace/skill_marketplace_registry_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_registry.dart';
import 'package:teampilot/services/skill/marketplace/skills_mp_marketplace_source.dart';
import 'package:teampilot/services/skill/marketplace/skills_sh_marketplace_source.dart';

void main() {
  test('builtIn returns both sources with unique ids', () {
    final sources = SkillMarketplaceRegistry.builtIn(
      settings: InMemoryAppSettingsRepository(),
    );
    expect(sources, hasLength(2));
    expect(sources.map((s) => s.id).toSet(), {'skillsSh', 'skillsMp'});
    expect(sources.first, isA<SkillsShMarketplaceSource>());
    expect(sources.last, isA<SkillsMpMarketplaceSource>());
  });
}
```

Run: `cd client && flutter test test/services/skill/marketplace/skill_marketplace_registry_test.dart`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/skill/marketplace/skills_sh_marketplace_source.dart client/lib/services/skill/marketplace/skill_marketplace_registry.dart client/test/services/skill/marketplace/skills_sh_marketplace_source_test.dart client/test/services/skill/marketplace/skill_marketplace_registry_test.dart
git commit -m "feat(skills): skills.sh adapter source and marketplace registry"
```

---

### Task 4: AppSettingsRepository 增加 skillsMpApiKey

**Files:**
- Modify: `client/lib/repositories/app_settings_repository.dart`
- Test: `client/test/repositories/app_settings_repository_test.dart`

**Interfaces:**
- Consumes: 无（独立）。
- Produces: `AppSettingsRepository.loadSkillsMpApiKey() → Future<String?>`、`saveSkillsMpApiKey(String?)`；`InMemoryAppSettingsRepository({String? skillsMpApiKey})`。

- [ ] **Step 1: 写失败测试**

`client/test/repositories/app_settings_repository_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';

void main() {
  test('InMemory round trip and null-on-empty', () async {
    final repo = InMemoryAppSettingsRepository();
    expect(await repo.loadSkillsMpApiKey(), isNull);
    await repo.saveSkillsMpApiKey('sk_abc');
    expect(await repo.loadSkillsMpApiKey(), 'sk_abc');
    await repo.saveSkillsMpApiKey(null);
    expect(await repo.loadSkillsMpApiKey(), isNull);
  });

  test('InMemory constructor seed', () async {
    final repo = InMemoryAppSettingsRepository(skillsMpApiKey: 'sk_seed');
    expect(await repo.loadSkillsMpApiKey(), 'sk_seed');
  });

  test('SharedPrefs persists key in the settings map', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = SharedPrefsAppSettingsRepository(prefs);
    expect(await repo.loadSkillsMpApiKey(), isNull);
    await repo.saveSkillsMpApiKey('sk_prefs');
    expect(await repo.loadSkillsMpApiKey(), 'sk_prefs');
    await repo.saveSkillsMpApiKey(null);
    expect(await repo.loadSkillsMpApiKey(), isNull);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/repositories/app_settings_repository_test.dart`
Expected: FAIL（接口缺方法）

- [ ] **Step 3: 实现**

`client/lib/repositories/app_settings_repository.dart`：

- 接口加两行（放在 `loadSkippedUpdateVersion/saveSkippedUpdateVersion` 之后）：

```dart
  /// SkillsMP 市场源的匿名限额升级 key（可选，空则匿名访问）。
  Future<String?> loadSkillsMpApiKey();
  Future<void> saveSkillsMpApiKey(String? key);
```

- `SharedPrefsAppSettingsRepository`：加常量 `static const _skillsMpApiKey = 'skillsMpApiKey';` 与实现（模式照抄 `loadSkippedUpdateVersion/saveSkippedUpdateVersion`）：

```dart
  @override
  Future<String?> loadSkillsMpApiKey() async {
    final value = _readMap()[_skillsMpApiKey];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  @override
  Future<void> saveSkillsMpApiKey(String? key) async {
    final current = _readMap();
    final trimmed = key?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      current.remove(_skillsMpApiKey);
    } else {
      current[_skillsMpApiKey] = trimmed;
    }
    await _writeMap(current);
  }
```

- `InMemoryAppSettingsRepository`：构造参数加 `String? skillsMpApiKey`（命名参数，存 `_skillsMpApiKey` 字段），实现：

```dart
  String? _skillsMpApiKey;

  @override
  Future<String?> loadSkillsMpApiKey() async => _skillsMpApiKey;

  @override
  Future<void> saveSkillsMpApiKey(String? key) async {
    final trimmed = key?.trim();
    _skillsMpApiKey = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && flutter test test/repositories/app_settings_repository_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add client/lib/repositories/app_settings_repository.dart client/test/repositories/app_settings_repository_test.dart
git commit -m "feat(settings): persist optional SkillsMP API key"
```

---

### Task 5: SkillCubit 重构为分槽市场状态

**Files:**
- Modify: `client/lib/cubits/skill_cubit.dart`
- Test: `client/test/cubits/skill_marketplace_cubit_test.dart`

**Interfaces:**
- Consumes: `MarketplaceSkill/Query/Result/Capabilities`、`marketplaceQuotaErrorKey`、`SkillMarketplaceSource`（Task 1）；`DiscoverableSkill`、`SkillRepo`（models/skill.dart，已有）；`SkillRepository.installFromDiscovery/loadInstalled`、`_repo.repos.addRepo`。
- Produces:
  - `class MarketplaceSearchState extends Equatable { query, page, loading, error, entries, hasNext, total, category, occupation, language, sortBy }`（含 `const MarketplaceSearchState()` 与 `copyWith`）
  - `SkillState` 新增 `final Map<String, MarketplaceSearchState> marketplace`、`final String? noticeMessage`（copyWith 支持 `marketplace`、`noticeMessage`、`clearNotice`）
  - `SkillCubit` 新增：`List<SkillMarketplaceSource> get marketplaces`；`Future<void> searchMarketplace(String sourceId, {required String query, String? category, String? occupation, String? language, String? sortBy})`；`Future<void> loadMoreMarketplace(String sourceId)`；`Future<void> installMarketplaceEntry(MarketplaceSkill e)`；`Future<void> setMarketplaceApiKey(String sourceId, String key)`；`void clearMarketplaceError(String sourceId)`
  - 常量 `SkillCubit.marketplaceRepoAddedNoticeKey = 'skillsMarketplaceRepoAdded'`
  - 删除：`SkillsShSearchState`、`SkillState.skillsSh`、`searchSkillsSh`、`loadMoreSkillsSh`、`installSkillsShEntry`

- [ ] **Step 1: 写失败测试**

`client/test/cubits/skill_marketplace_cubit_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';

class _FakeSource implements SkillMarketplaceSource {
  _FakeSource(this.id, {this.results = const [], this.quota = false});

  final String id;
  final List<MarketplaceSkill> results;
  final bool quota;

  @override
  String get label => id;

  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  final queries = <MarketplaceSearchQuery>[];
  String? setKey;

  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async {
    queries.add(query);
    if (quota) throw MarketplaceQuotaException('quota');
    final hasNext = results.length >= 20;
    return MarketplaceSearchResult(
      skills: results,
      hasNext: hasNext,
      total: results.length,
    );
  }

  @override
  Future<void> setApiKey(String key) async {
    setKey = key;
  }
}

void main() {
  MarketplaceSkill skill(String id, {String? directory}) => MarketplaceSkill(
    key: id,
    name: id,
    description: 'd',
    repoOwner: 'o',
    repoName: 'r',
    directory: directory,
    githubUrl: 'https://github.com/o/r',
  );
```

**说明**：`installMarketplaceEntry` 需要真实 `SkillRepository` 或注入；按现有测试惯例（`client/test/cubits/skill_cubit_test.dart`）用 `AppStorage.installForTesting` + 真实 `SkillRepository`，并用 fake `SkillAcquisitionEngine` 接管 installGitDir 避免网络。完整测试如下：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/models/skill.dart';
import 'package:teampilot/repositories/skill_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';
import 'package:teampilot/services/skill/skill_acquisition_engine.dart';
import 'package:teampilot/services/storage/app_storage.dart';

class _FakeSource implements SkillMarketplaceSource {
  _FakeSource(
    this.id, {
    this.quota = false,
    this.pageSize = 2,
    this.total = 3,
  });

  final String id;
  final bool quota;
  final int pageSize;
  final int total;

  @override
  String get label => id;

  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  final List<MarketplaceSearchQuery> queries = [];
  String? setKey;

  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async {
    queries.add(query);
    if (quota) throw MarketplaceQuotaException('quota');
    final start = (query.page - 1) * pageSize;
    final end = start + pageSize;
    final items = <MarketplaceSkill>[];
    for (var i = start; i < end && i < total; i++) {
      items.add(MarketplaceSkill(
        key: '$id-$i',
        name: '$id-$i',
        description: 'd',
        repoOwner: 'o',
        repoName: 'r',
        directory: 'dir/$i',
        githubUrl: 'https://github.com/o/r',
      ));
    }
    return MarketplaceSearchResult(
      skills: items,
      hasNext: end < total,
      total: total,
    );
  }

  @override
  Future<void> setApiKey(String key) async {
    setKey = key;
  }
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill-mp-cubit-');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  SkillCubit cubitWith(
    List<_FakeSource> sources, {
    List<MarketplaceSkill>? directResults,
  }) {
    final engine = SkillAcquisitionEngine(
      installGitDir: (d, {bool overwrite = false, String? idOverride}) async {
        final installed = directResults ?? const [];
        if (installed.isNotEmpty) return installed.first;
        return Skill(
          id: idOverride ?? d.expectedLocalId,
          name: d.name,
          description: d.description,
          directory: d.directory,
          installedAt: 1,
          updatedAt: 1,
        );
      },
      registerDirectory: ({required String id, required String directory}) {
        throw UnimplementedError();
      },
    );
    return SkillCubit(
      SkillRepository(),
      acquisitionEngine: engine,
      marketplaces: sources,
    );
  }

  test('searchMarketplace fills the slot per source id', () async {
    final a = _FakeSource('a');
    final b = _FakeSource('b');
    final cubit = cubitWith([a, b]);
    await cubit.searchMarketplace('a', query: 'foo');
    expect(cubit.state.marketplace['a']?.entries, hasLength(2));
    expect(cubit.state.marketplace['a']?.query, 'foo');
    expect(cubit.state.marketplace.containsKey('b'), isFalse);
    expect(a.queries.single.query, 'foo');
    await cubit.searchMarketplace('b', query: 'bar');
    expect(cubit.state.marketplace['b']?.entries, hasLength(2));
    expect(cubit.state.marketplace['a']?.entries, hasLength(2));
  });

  test('short query and unknown source are ignored', () async {
    final a = _FakeSource('a');
    final cubit = cubitWith([a]);
    await cubit.searchMarketplace('a', query: 'x');
    expect(a.queries, isEmpty);
    await cubit.searchMarketplace('nope', query: 'longquery');
    expect(cubit.state.marketplace, isEmpty);
  });

  test('loadMoreMarketplace appends and guards hasNext', () async {
    final a = _FakeSource('a', pageSize: 2, total: 3);
    final cubit = cubitWith([a]);
    await cubit.searchMarketplace('a', query: 'q');
    expect(cubit.state.marketplace['a']?.entries, hasLength(2));
    await cubit.loadMoreMarketplace('a');
    expect(cubit.state.marketplace['a']?.entries, hasLength(3));
    expect(cubit.state.marketplace['a']?.hasNext, isFalse);
    await cubit.loadMoreMarketplace('a');
    expect(a.queries, hasLength(2));
  });

  test('quota error maps to marketplaceQuotaErrorKey', () async {
    final a = _FakeSource('a', quota: true);
    final cubit = cubitWith([a]);
    await cubit.searchMarketplace('a', query: 'q');
    expect(cubit.state.marketplace['a']?.error, marketplaceQuotaErrorKey);
    expect(cubit.state.marketplace['a']?.loading, isFalse);
  });

  test('setMarketplaceApiKey delegates and clears error', () async {
    final a = _FakeSource('a', quota: true);
    final cubit = cubitWith([a]);
    await cubit.searchMarketplace('a', query: 'q');
    expect(cubit.state.marketplace['a']?.error, marketplaceQuotaErrorKey);
    await cubit.setMarketplaceApiKey('a', 'sk_x');
    expect(a.setKey, 'sk_x');
    expect(cubit.state.marketplace['a']?.error, isNull);
  });

  test('installMarketplaceEntry with directory installs directly', () async {
    final cubit = cubitWith([]);
    final entry = MarketplaceSkill(
      key: 'k',
      name: 'n',
      description: 'd',
      repoOwner: 'o',
      repoName: 'r',
      directory: 'skills/n',
      githubUrl: 'https://github.com/o/r',
    );
    await cubit.installMarketplaceEntry(entry);
    expect(cubit.state.installed, isNotEmpty);
    expect(cubit.state.noticeMessage, isNull);
    expect(cubit.state.busyIds, isEmpty);
  });

  test('installMarketplaceEntry without directory adds repo', () async {
    final cubit = cubitWith([]);
    final entry = MarketplaceSkill(
      key: 'k',
      name: 'n',
      description: 'd',
      repoOwner: 'o',
      repoName: 'r',
      githubUrl: 'https://github.com/o/r',
    );
    await cubit.installMarketplaceEntry(entry);
    final repos = await cubit.state.installed;
    final loaded = await SkillRepository().loadRepos();
    expect(loaded.any((r) => r.owner == 'o' && r.name == 'r'), isTrue);
    expect(
      cubit.state.noticeMessage,
      SkillCubit.marketplaceRepoAddedNoticeKey,
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/cubits/skill_marketplace_cubit_test.dart`
Expected: FAIL（缺 `marketplace`、`searchMarketplace` 等）

- [ ] **Step 3: 实现 cubit 重构**

`client/lib/cubits/skill_cubit.dart` 修改：

a) 顶部加 import：

```dart
import '../services/skill/marketplace/skill_marketplace_source.dart';
```

b) 替换 `SkillsShSearchState` 类为：

```dart
class MarketplaceSearchState extends Equatable {
  const MarketplaceSearchState({
    this.query = '',
    this.page = 1,
    this.loading = false,
    this.error,
    this.entries = const [],
    this.hasNext = false,
    this.total = 0,
    this.category,
    this.occupation,
    this.language,
    this.sortBy,
  });

  final String query;
  final int page;
  final bool loading;
  final String? error;
  final List<MarketplaceSkill> entries;
  final bool hasNext;
  final int total;
  final String? category;
  final String? occupation;
  final String? language;
  final String? sortBy;

  MarketplaceSearchState copyWith({
    String? query,
    int? page,
    bool? loading,
    String? error,
    bool clearError = false,
    List<MarketplaceSkill>? entries,
    bool? hasNext,
    int? total,
    String? category,
    String? occupation,
    String? language,
    String? sortBy,
  }) => MarketplaceSearchState(
    query: query ?? this.query,
    page: page ?? this.page,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    entries: entries ?? this.entries,
    hasNext: hasNext ?? this.hasNext,
    total: total ?? this.total,
    category: category ?? this.category,
    occupation: occupation ?? this.occupation,
    language: language ?? this.language,
    sortBy: sortBy ?? this.sortBy,
  );

  @override
  List<Object?> get props => [
    query,
    page,
    loading,
    error,
    entries,
    hasNext,
    total,
    category,
    occupation,
    language,
    sortBy,
  ];
}
```

c) `SkillState`：删 `final SkillsShSearchState skillsSh;` 与 copyWith 中对应项，新增：

```dart
  final Map<String, MarketplaceSearchState> marketplace;
  final String? noticeMessage;
```

（`const SkillState()` 默认 `marketplace: const {}`、`noticeMessage` null；copyWith 增加 `Map<String, MarketplaceSearchState>? marketplace`、`String? noticeMessage`、`bool clearNotice = false`，props 加入两者。）

d) `SkillCubit` 构造加参数：

```dart
  SkillCubit(
    this._repo, {
    this.marketplaces = const [],
    SkillAcquisitionEngine? acquisitionEngine,
    ...
  })

  final List<SkillMarketplaceSource> marketplaces;
```

e) 常量与方法（放在 `installFromZip` 之后）：

```dart
  static const marketplaceRepoAddedNoticeKey = 'skillsMarketplaceRepoAdded';
  static const _marketplacePageSize = 20;

  SkillMarketplaceSource? _marketplaceById(String sourceId) {
    for (final s in marketplaces) {
      if (s.id == sourceId) return s;
    }
    return null;
  }

  Future<void> searchMarketplace(
    String sourceId, {
    required String query,
    String? category,
    String? occupation,
    String? language,
    String? sortBy,
  }) async {
    final source = _marketplaceById(sourceId);
    if (source == null) return;
    if (query.trim().length < 2) return;
    final slot = state.marketplace[sourceId] ?? const MarketplaceSearchState();
    emit(
      state.copyWith(
        marketplace: {
          ...state.marketplace,
          sourceId: slot.copyWith(
            loading: true,
            query: query,
            page: 1,
            entries: const [],
            hasNext: false,
            clearError: true,
            category: category,
            occupation: occupation,
            language: language,
            sortBy: sortBy,
          ),
        },
        clearError: true,
      ),
    );
    try {
      final res = await source.search(
        MarketplaceSearchQuery(
          query: query,
          page: 1,
          limit: _marketplacePageSize,
          category: category,
          occupation: occupation,
          language: language,
          sortBy: sortBy,
        ),
      );
      emit(
        state.copyWith(
          marketplace: {
            ...state.marketplace,
            sourceId: MarketplaceSearchState(
              query: query,
              page: 1,
              entries: res.skills,
              hasNext: res.hasNext,
              total: res.total,
              category: category,
              occupation: occupation,
              language: language,
              sortBy: sortBy,
            ),
          },
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          marketplace: {
            ...state.marketplace,
            sourceId: slot.copyWith(
              loading: false,
              error: e is MarketplaceQuotaException
                  ? marketplaceQuotaErrorKey
                  : '$e',
            ),
          },
        ),
      );
    }
  }

  Future<void> loadMoreMarketplace(String sourceId) async {
    final source = _marketplaceById(sourceId);
    if (source == null) return;
    final slot = state.marketplace[sourceId];
    if (slot == null || slot.loading || !slot.hasNext) return;
    emit(
      state.copyWith(
        marketplace: {
          ...state.marketplace,
          sourceId: slot.copyWith(loading: true),
        },
      ),
    );
    try {
      final res = await source.search(
        MarketplaceSearchQuery(
          query: slot.query,
          page: slot.page + 1,
          limit: _marketplacePageSize,
          category: slot.category,
          occupation: slot.occupation,
          language: slot.language,
          sortBy: slot.sortBy,
        ),
      );
      emit(
        state.copyWith(
          marketplace: {
            ...state.marketplace,
            sourceId: slot.copyWith(
              page: slot.page + 1,
              entries: [...slot.entries, ...res.skills],
              hasNext: res.hasNext,
              total: res.total,
              loading: false,
            ),
          },
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          marketplace: {
            ...state.marketplace,
            sourceId: slot.copyWith(
              loading: false,
              error: e is MarketplaceQuotaException
                  ? marketplaceQuotaErrorKey
                  : '$e',
            ),
          },
        ),
      );
    }
  }

  Future<void> installMarketplaceEntry(MarketplaceSkill e) async {
    if (state.busyIds.contains(e.key)) return;
    emit(state.copyWith(busyIds: {...state.busyIds, e.key}, clearError: true));
    try {
      if (e.isInstalledDirectly) {
        await _acquisitionEngine.installGitDir(
          DiscoverableSkill(
            key: e.key,
            name: e.name,
            description: e.description,
            directory: e.directory!,
            readmeUrl: e.githubUrl,
            repoOwner: e.repoOwner,
            repoName: e.repoName,
            repoBranch: e.repoBranch,
          ),
        );
        final installed = await _repo.loadInstalled();
        emit(state.copyWith(installed: installed));
      } else {
        await _repo.repos.addRepo(
          SkillRepo(
            owner: e.repoOwner,
            name: e.repoName,
            branch: e.repoBranch,
          ),
        );
        emit(state.copyWith(noticeMessage: marketplaceRepoAddedNoticeKey));
      }
    } catch (e) {
      emit(state.copyWith(errorMessage: '$e'));
    } finally {
      final next = {...state.busyIds}..remove(e.key);
      emit(state.copyWith(busyIds: next));
    }
  }

  Future<void> setMarketplaceApiKey(String sourceId, String key) async {
    final source = _marketplaceById(sourceId);
    if (source == null) return;
    await source.setApiKey(key);
    clearMarketplaceError(sourceId);
  }

  void clearMarketplaceError(String sourceId) {
    final slot = state.marketplace[sourceId];
    if (slot == null || slot.error == null) return;
    emit(
      state.copyWith(
        marketplace: {...state.marketplace, sourceId: slot.copyWith(clearError: true)},
      ),
    );
  }
```

f) `clearError()` 改为同时清 notice：

```dart
  void clearError() => emit(state.copyWith(clearError: true, clearNotice: true));
```

g) 删除 `searchSkillsSh`、`loadMoreSkillsSh`、`installSkillsShEntry` 三个方法及其 `SkillsShSearchState` 引用（`installSkillsShEntry` 里的 `DiscoverableSkill` 构造逻辑已被 `installMarketplaceEntry` 覆盖）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && flutter test test/cubits/skill_marketplace_cubit_test.dart test/cubits/skill_cubit_test.dart`
Expected: PASS（旧 cubit 测试不受影响）

- [ ] **Step 5: 提交**

```bash
git add client/lib/cubits/skill_cubit.dart client/test/cubits/skill_marketplace_cubit_test.dart
git commit -m "refactor(skills): per-source marketplace search state in SkillCubit"
```

---

### Task 6: 统一市场卡片与共享面板

**Files:**
- Create: `client/lib/pages/skills/marketplace_skill_card.dart`
- Create: `client/lib/pages/skills/skill_marketplace_panel.dart`
- Modify: `client/lib/l10n/app_en.arb`、`client/lib/l10n/app_zh.arb`（新增键）
- Test: `client/test/pages/skills/skill_marketplace_panel_test.dart`

**Interfaces:**
- Consumes: `MarketplaceSkill`、`MarketplaceSearchState`、`SkillMarketplaceSource`（Task 1/5）；`SkillCubit.searchMarketplace/loadMoreMarketplace/installMarketplaceEntry/setMarketplaceApiKey`（Task 5）；l10n 键（本任务新增）。
- Produces: `MarketplaceSkillCard{skill, installed, busy, onInstall, onOpenGithub}`；`SkillMarketplacePanel{source}`（StatefulWidget，内部搜索控制器与过滤状态，经 Bloc 与 `SkillCubit` 交互）。

- [ ] **Step 1: 加 l10n 键**

`client/lib/l10n/app_en.arb`（在 `"skillsSourceSkillsSh"` 附近插入）：

```json
  "skillsSourceSkillsMp": "SkillsMP",
  "skillsMarketplaceSearchHint": "Search marketplaces (≥ 2 chars)…",
  "skillsMarketplaceLoadMore": "Load more",
  "skillsMarketplaceAddRepo": "Add repo",
  "skillsMarketplaceRepoAdded": "Repo added to skill sources; install individual skills in the Repos tab",
  "skillsFilterSortBy": "Sort",
  "skillsFilterSortByStars": "Stars",
  "skillsFilterSortByRecent": "Recent",
  "skillsFilterLanguage": "Language",
  "skillsFilterAnyLanguage": "Any",
  "skillsFilterCategory": "Category",
  "skillsFilterAnyCategory": "All",
  "skillsFilterOccupation": "Occupation",
  "skillsFilterAnyOccupation": "All",
  "skillsCardStars": "{count} stars",
  "skillsCardUpdatedAt": "Updated {date}",
  "skillsMpQuotaHint": "SkillsMP anonymous quota (50/day) exhausted. Set a free API key to continue.",
  "skillsMpApiKeyButton": "Set API Key",
  "skillsMpApiKeyDialogTitle": "SkillsMP API Key",
  "skillsMpApiKeyDialogHint": "Register for a free key at skillsmp.com/developers",
  "skillsMpApiKeySave": "Save",
  "skillsMarketplaceSearchError": "Search failed: {message}",
```

带占位符的键需要 `@` 元数据（`skillsCardStars`、`skillsCardUpdatedAt`、`skillsMarketplaceSearchError`）：

```json
  "@skillsCardStars": {
    "placeholders": {
      "count": {"type": "int"}
    }
  },
  "@skillsCardUpdatedAt": {
    "placeholders": {
      "date": {"type": "String"}
    }
  },
  "@skillsMarketplaceSearchError": {
    "placeholders": {
      "message": {"type": "String"}
    }
  },
```

`client/lib/l10n/app_zh.arb` 对应：

```json
  "skillsSourceSkillsMp": "SkillsMP",
  "skillsMarketplaceSearchHint": "搜索技能市场 (≥2 字)…",
  "skillsMarketplaceLoadMore": "加载更多",
  "skillsMarketplaceAddRepo": "添加仓库",
  "skillsMarketplaceRepoAdded": "已添加到仓库源，可在 Repos 页安装具体技能",
  "skillsFilterSortBy": "排序",
  "skillsFilterSortByStars": "星数",
  "skillsFilterSortByRecent": "最新",
  "skillsFilterLanguage": "语言",
  "skillsFilterAnyLanguage": "全部",
  "skillsFilterCategory": "分类",
  "skillsFilterAnyCategory": "全部",
  "skillsFilterOccupation": "职业",
  "skillsFilterAnyOccupation": "全部",
  "skillsCardStars": "{count} 星",
  "skillsCardUpdatedAt": "更新于 {date}",
  "skillsMpQuotaHint": "SkillsMP 匿名额度（每天 50 次）已用完。设置免费 API Key 后继续。",
  "skillsMpApiKeyButton": "设置 API Key",
  "skillsMpApiKeyDialogTitle": "SkillsMP API Key",
  "skillsMpApiKeyDialogHint": "在 skillsmp.com/developers 免费注册获取",
  "skillsMpApiKeySave": "保存",
  "skillsMarketplaceSearchError": "搜索失败：{message}",
```

（`@` 元数据照抄 en 版。）

然后：`cd client && flutter gen-l10n`

- [ ] **Step 2: 写失败测试**

`client/test/pages/skills/skill_marketplace_panel_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/pages/skills/skill_marketplace_panel.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';

class _NoFilterSource implements SkillMarketplaceSource {
  @override
  String get id => 'noFilters';
  @override
  String get label => 'noFilters';
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();

  final queries = <MarketplaceSearchQuery>[];

  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async {
    queries.add(query);
    return const MarketplaceSearchResult(skills: [], hasNext: false);
  }
}

class _FilteredSource implements SkillMarketplaceSource {
  @override
  String get id => 'filtered';
  @override
  String get label => 'filtered';
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities(
    supportsSortBy: true,
    supportsLanguage: true,
    categoryChoices: {'data-ai': 'Data & AI'},
    languageChoices: ['zh', 'en'],
  );

  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async =>
      const MarketplaceSearchResult(skills: [], hasNext: false);
}

Widget wrap(Widget child, SkillCubit cubit) => MaterialApp(
  home: BlocProvider<SkillCubit>.value(value: cubit, child: child),
);

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill-mp-panel-');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  SkillCubit cubit() => SkillCubit(SkillRepository());

  testWidgets('renders search bar; no filters when capabilities empty',
      (tester) async {
    final source = _NoFilterSource();
    final c = cubit();
    await tester.pumpWidget(wrap(SkillMarketplacePanel(source: source), c));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Sort'), findsNothing);
  });

  testWidgets('search submits to source', (tester) async {
    final source = _NoFilterSource();
    final c = cubit();
    await tester.pumpWidget(wrap(SkillMarketplacePanel(source: source), c));
    await tester.enterText(find.byType(TextField), 'seo');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(source.queries, isNotEmpty);
    expect(source.queries.single.query, 'seo');
  });

  testWidgets('renders filter dropdowns when capabilities declare them',
      (tester) async {
    final source = _FilteredSource();
    final c = cubit();
    await tester.pumpWidget(wrap(SkillMarketplacePanel(source: source), c));
    expect(find.text('Sort'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Category'), findsOneWidget);
  });
}
```

（`AppPaths`/`LocalFilesystem`/`AppStorage` 的 import 与 `skill_cubit_test.dart` 一致；测试文件顶部 import `dart:io`、`package:teampilot/services/io/local_filesystem.dart`、`package:teampilot/services/storage/app_storage.dart`。）

- [ ] **Step 3: 跑测试确认失败**

Run: `cd client && flutter test test/pages/skills/skill_marketplace_panel_test.dart`
Expected: FAIL（缺 `SkillMarketplacePanel`/`MarketplaceSkillCard`）

- [ ] **Step 4: 实现卡片**

`client/lib/pages/skills/marketplace_skill_card.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../services/skill/marketplace/skill_marketplace_source.dart';
import '../../theme/workspace_surface_layers.dart';
import '../../widgets/github_details_button.dart';

class MarketplaceSkillCard extends StatelessWidget {
  const MarketplaceSkillCard({
    super.key,
    required this.skill,
    required this.installed,
    required this.busy,
    required this.onInstall,
  });

  final MarketplaceSkill skill;
  final bool installed;
  final bool busy;
  final VoidCallback onInstall;

  static String formatUpdatedAt(int unixSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final textBase = cs.onSurface;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: workspaceCardDecoration(cs, radius: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  skill.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTextStyles.of(context).mdBoldColored(textBase),
                ),
              ),
              if (skill.contentLanguage != null) ...[
                const SizedBox(width: 6),
                _LanguageBadge(code: skill.contentLanguage!),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${skill.repoOwner}/${skill.repoName}',
            style: TpTextStyles.of(
              context,
            ).xsColored(textBase.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Text(
              skill.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TpTextStyles.of(
                context,
              ).smColored(textBase.withValues(alpha: 0.7)),
            ),
          ),
          _MetaRow(skill: skill, l10n: l10n),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GithubDetailsButton(url: skill.githubUrl, label: l10n.skillsCardDetails),
                if (installed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      l10n.skillsCardInstalled,
                      style: TpTextStyles.of(context).smBoldColored(const Color(0xFF15803D)),
                    ),
                  )
                else
                  FilledButton(
                    onPressed: busy ? null : onInstall,
                    child: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            skill.isInstalledDirectly
                                ? l10n.skillsCardInstall
                                : l10n.skillsMarketplaceAddRepo,
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageBadge extends StatelessWidget {
  const _LanguageBadge({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        code.toUpperCase(),
        style: TpTextStyles.of(context).xsBoldColored(cs.onSecondaryContainer),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.skill, required this.l10n});
  final MarketplaceSkill skill;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final textBase = Theme.of(context).colorScheme.onSurface;
    final dim = TpTextStyles.of(
      context,
    ).xsColored(textBase.withValues(alpha: 0.55));
    final chips = <String>[
      if (skill.stars != null) l10n.skillsCardStars(skill.stars!),
      if (skill.installs != null) l10n.skillsInstalls(skill.installs!),
      if (skill.updatedAt != null)
        l10n.skillsCardUpdatedAt(
          MarketplaceSkillCard.formatUpdatedAt(skill.updatedAt!),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [for (final c in chips) Text(c, style: dim)],
    );
  }
}
```

注意：`_MetaRow.l10n` 用 `AppLocalizations` 类型（`import '../../l10n/app_localizations.dart';`）；`_LanguageBadge` 中 `TpTextStyles.of(context).xsBoldColored` 若不存在用 `xsColored`；`_body` 的 `l10n` 参数类型用 `AppLocalizations`。

- [ ] **Step 5: 实现共享面板**

`client/lib/pages/skills/skill_marketplace_panel.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/skill_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/skill/marketplace/skill_marketplace_source.dart';
import '../../utils/debounce/debounce.dart';
import 'marketplace_skill_card.dart';
import 'skill_discovery_helpers.dart';
import 'skill_management_cards.dart';

class SkillMarketplacePanel extends StatefulWidget {
  const SkillMarketplacePanel({super.key, required this.source});

  final SkillMarketplaceSource source;

  @override
  State<SkillMarketplacePanel> createState() => _SkillMarketplacePanelState();
}

class _SkillMarketplacePanelState extends State<SkillMarketplacePanel> {
  final _searchCtl = TextEditingController();
  String? _sortBy;
  String? _language;
  String? _category;
  String? _occupation;

  @override
  void dispose() {
    Debounces.cancel('skill_marketplace_search');
    _searchCtl.dispose();
    super.dispose();
  }

  void _onSubmitted(String value) {
    final q = value.trim();
    if (q.length < 2) return;
    context.read<SkillCubit>().searchMarketplace(
      widget.source.id,
      query: q,
      category: _category,
      occupation: _occupation,
      language: _language,
      sortBy: _sortBy,
    );
  }

  void _search() {
    final q = _searchCtl.text.trim();
    if (q.length >= 2) _onSubmitted(q);
  }

  void _onFilterChanged() {
    final q = _searchCtl.text.trim();
    if (q.length >= 2) {
      context.read<SkillCubit>().searchMarketplace(
        widget.source.id,
        query: q,
        category: _category,
        occupation: _occupation,
        language: _language,
        sortBy: _sortBy,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocSelector<SkillCubit, SkillState, MarketplaceSearchState>(
      selector: (state) =>
          state.marketplace[widget.source.id] ?? const MarketplaceSearchState(),
      builder: (context, slot) {
        final l10n = context.l10n;
        final caps = widget.source.capabilities;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtl,
                    decoration: InputDecoration(
                      hintText: l10n.skillsMarketplaceSearchHint,
                      prefixIcon: Icon(Icons.search, size: context.tpIconSizes.md),
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                    ),
                    onSubmitted: _onSubmitted,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _search, child: Text(l10n.skillsSkillsShSearch)),
              ],
            ),
            if (caps.hasAnyFilter) ...[
              const SizedBox(height: 10),
              _FilterRow(
                caps: caps,
                sortBy: _sortBy,
                language: _language,
                category: _category,
                occupation: _occupation,
                onSortBy: (v) {
                  setState(() => _sortBy = v);
                  _onFilterChanged();
                },
                onLanguage: (v) {
                  setState(() => _language = v);
                  _onFilterChanged();
                },
                onCategory: (v) {
                  setState(() => _category = v);
                  _onFilterChanged();
                },
                onOccupation: (v) {
                  setState(() => _occupation = v);
                  _onFilterChanged();
                },
              ),
            ],
            const SizedBox(height: 12),
            Expanded(child: _body(context, slot, l10n)),
          ],
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    MarketplaceSearchState slot,
    AppLocalizations l10n,
  ) {
    if (slot.loading && slot.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (slot.error != null) {
      return _ErrorState(
        error: slot.error!,
        onRetry: () {
          context.read<SkillCubit>().clearMarketplaceError(widget.source.id);
          _onFilterChanged();
        },
        onSetApiKey: () => _showApiKeyDialog(context),
        sourceId: widget.source.id,
      );
    }
    if (slot.query.isEmpty) {
      return SingleChildScrollView(
        child: SkillManagementCard(
          child: TpEmptyState(
            icon: Icons.search,
            title: l10n.skillsSkillsShPlaceholder,
            hint: '',
          ),
        ),
      );
    }
    if (slot.entries.isEmpty) {
      return SingleChildScrollView(
        child: SkillManagementCard(
          child: TpEmptyState(
            icon: Icons.search_off,
            title: l10n.skillsDiscoveryEmpty,
            hint: l10n.skillsDiscoveryEmptyHint,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: BlocSelector<SkillCubit, SkillState, Set<String>>(
            selector: (state) => skillInstalledKeys(state.installed),
            builder: (context, installedKeys) {
              return BlocSelector<SkillCubit, SkillState, Set<String>>(
                selector: (state) => state.busyIds,
                builder: (context, busyIds) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final cols = constraints.maxWidth >= 1100
                          ? 3
                          : (constraints.maxWidth >= 700 ? 2 : 1);
                      return GridView.builder(
                        padding: const EdgeInsets.only(top: 2),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 168,
                        ),
                        itemCount: slot.entries.length,
                        itemBuilder: (context, i) {
                          final skill = slot.entries[i];
                          return MarketplaceSkillCard(
                            key: ValueKey('${widget.source.id}:${skill.key}'),
                            skill: skill,
                            installed: installedKeys.contains(
                              '${(skill.directory ?? skill.repoName).toLowerCase()}:${skill.repoOwner.toLowerCase()}:${skill.repoName.toLowerCase()}',
                            ),
                            busy: busyIds.contains(skill.key),
                            onInstall: () =>
                                context.read<SkillCubit>().installMarketplaceEntry(skill),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        if (slot.hasNext)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: OutlinedButton.icon(
              onPressed: slot.loading
                  ? null
                  : () => context.read<SkillCubit>().loadMoreMarketplace(
                      widget.source.id,
                    ),
              icon: slot.loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.expand_more, size: context.tpIconSizes.md),
              label: Text(l10n.skillsMarketplaceLoadMore),
            ),
          ),
      ],
    );
  }

  Future<void> _showApiKeyDialog(BuildContext context) async {
    final l10n = context.l10n;
    final ctl = TextEditingController();
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.skillsMpApiKeyDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.skillsMpApiKeyDialogHint,
              style: TpTextStyles.of(context).sm,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctl,
              decoration: InputDecoration(
                labelText: l10n.apiKey,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctl.text.trim()),
            child: Text(l10n.skillsMpApiKeySave),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (saved == null) return;
    await context.read<SkillCubit>().setMarketplaceApiKey(widget.source.id, saved);
    _onFilterChanged();
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.caps,
    required this.sortBy,
    required this.language,
    required this.category,
    required this.occupation,
    required this.onSortBy,
    required this.onLanguage,
    required this.onCategory,
    required this.onOccupation,
  });

  final MarketplaceCapabilities caps;
  final String? sortBy;
  final String? language;
  final String? category;
  final String? occupation;
  final ValueChanged<String?> onSortBy;
  final ValueChanged<String?> onLanguage;
  final ValueChanged<String?> onCategory;
  final ValueChanged<String?> onOccupation;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (caps.supportsSortBy)
          _FilterDropdown<String>(
            label: l10n.skillsFilterSortBy,
            value: sortBy,
            items: {
              'stars': l10n.skillsFilterSortByStars,
              'recent': l10n.skillsFilterSortByRecent,
            },
            onChanged: onSortBy,
          ),
        if (caps.supportsLanguage)
          _FilterDropdown<String>(
            label: l10n.skillsFilterLanguage,
            value: language,
            items: {
              for (final code in caps.languageChoices) code: code.toUpperCase(),
            },
            includeAny: l10n.skillsFilterAnyLanguage,
            onChanged: onLanguage,
          ),
        if (caps.supportsCategory)
          _FilterDropdown<String>(
            label: l10n.skillsFilterCategory,
            value: category,
            items: caps.categoryChoices,
            includeAny: l10n.skillsFilterAnyCategory,
            onChanged: onCategory,
          ),
        if (caps.supportsOccupation)
          _FilterDropdown<String>(
            label: l10n.skillsFilterOccupation,
            value: occupation,
            items: caps.occupationChoices,
            includeAny: l10n.skillsFilterAnyOccupation,
            onChanged: onOccupation,
          ),
      ],
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    this.includeAny,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final Map<T, String> items;
  final String? includeAny;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        hint: Text(label),
        isDense: true,
        items: [
          if (includeAny != null)
            DropdownMenuItem<T>(value: null, child: Text(includeAny!)),
          for (final e in items.entries)
            DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.error,
    required this.onRetry,
    required this.onSetApiKey,
    required this.sourceId,
  });

  final String error;
  final VoidCallback onRetry;
  final VoidCallback onSetApiKey;
  final String sourceId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isQuota = error == marketplaceQuotaErrorKey;
    return SingleChildScrollView(
      child: SkillManagementCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpEmptyState(
              icon: isQuota ? Icons.speed : Icons.error_outline,
              title: isQuota ? l10n.skillsMpQuotaHint : error,
              hint: '',
            ),
            if (isQuota) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.center,
                child: Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton(
                      onPressed: onSetApiKey,
                      child: Text(l10n.skillsMpApiKeyButton),
                    ),
                    OutlinedButton(
                      onPressed: onRetry,
                      child: Text(l10n.skillsSkillsShSearch),
                    ),
                  ],
                ),
              ),
            ] else
              Align(
                alignment: Alignment.center,
                child: OutlinedButton(
                  onPressed: onRetry,
                  child: Text(l10n.skillsSkillsShSearch),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

说明：`l10n.commonCancel` 若不存在则用 `MaterialLocalizations.of(context).cancelButton`；`l10n.skillsSkillsShPlaceholder`/`skillsDiscoveryEmptyHint`/`skillsSkillsShSearch` 为复用既有键。`_body` 的 `l10n` 参数类型用 `AppLocalizations`（`import '../../l10n/app_localizations.dart';`）。load-more 区域逻辑简化：`slot.hasNext` 控制。

- [ ] **Step 6: 跑测试确认通过**

Run: `cd client && flutter test test/pages/skills/skill_marketplace_panel_test.dart`
Expected: PASS

- [ ] **Step 7: 提交**

```bash
cd client && flutter gen-l10n
git add client/lib/pages/skills/marketplace_skill_card.dart client/lib/pages/skills/skill_marketplace_panel.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/test/pages/skills/skill_marketplace_panel_test.dart
git commit -m "feat(skills): unified marketplace panel and skill card with metadata"
```

---

### Task 7: 发现页接入（来源行遍历注册表，删除旧面板）

**Files:**
- Modify: `client/lib/pages/skills/skill_discovery_helpers.dart`
- Modify: `client/lib/pages/skills/skill_discovery_section.dart`
- Modify: `client/lib/pages/skills/skill_management_page.dart`
- Delete: `client/lib/pages/skills/skill_discovery_skills_sh_panel.dart`
- Test: `client/test/pages/skills/skill_discovery_section_test.dart`

**Interfaces:**
- Consumes: `SkillCubit.marketplaces`、`SkillMarketplacePanel`（Task 5/6）、`SkillState.noticeMessage`（Task 5）。
- Produces: `SkillSearchSource { repos, marketplace }`；来源行按 `cubit.marketplaces` 渲染 toggle。

- [ ] **Step 1: 更新 helpers**

`client/lib/pages/skills/skill_discovery_helpers.dart`：

- `enum SkillSearchSource { repos, marketplace }`
- 删除 `skillsShInstallKey`（唯一调用方为被删面板）
- 其余不动

- [ ] **Step 2: 改造发现页 section**

`client/lib/pages/skills/skill_discovery_section.dart`：

- 删除 `import 'skill_discovery_skills_sh_panel.dart';`，加 `import 'skill_marketplace_panel.dart';`
- 状态：`SkillSearchSource _source = SkillSearchSource.repos;` + `String? _marketplaceId;`
- `_SkillDiscoverySourceRow` 改为接收 `List<SkillMarketplaceSource>` 与 `_marketplaceId`，渲染：

```dart
Row(
  children: [
    SkillSourceToggle(
      label: l10n.skillsSourceRepos,
      selected: source == SkillSearchSource.repos,
      onTap: () => onSourceChanged(SkillSearchSource.repos, null),
    ),
    for (final mp in marketplaces) ...[
      const SizedBox(width: 8),
      SkillSourceToggle(
        label: mp.label,
        selected: source == SkillSearchSource.marketplace && marketplaceId == mp.id,
        onTap: () => onSourceChanged(SkillSearchSource.marketplace, mp.id),
      ),
    ],
    const Spacer(),
    if (source == SkillSearchSource.repos) const _SkillDiscoveryRefreshButton(),
  ],
)
```

- `build` 中：`_source == repos ? ReposBody : SkillMarketplacePanel(source: 选中的 source)`（从 `context.read<SkillCubit>().marketplaces` 找 `_marketplaceId`；找不到则回退 repos body）；`onSourceChanged(SkillSearchSource next, String? id)` 里 `setState` 更新两者，`_marketplaceId` 为 null 时取第一个 marketplace id。
- 顶部 `SkillManagementCard` 内：repos 分支保持现有 filters 与 sync banner；marketplace 分支只渲染 `SkillMarketplacePanel`（搜索框已在面板内，`_skillsShCtl` 删除）。

- [ ] **Step 3: 删除旧面板文件**

`git rm client/lib/pages/skills/skill_discovery_skills_sh_panel.dart`

（确认无其它引用：`grep -rn "skill_discovery_skills_sh_panel" client/lib client/test` 应为空。）

- [ ] **Step 4: 页面级 notice 展示**

`client/lib/pages/skills/skill_management_page.dart`：在现有 errorMessage `BlocListener` 后追加：

```dart
BlocListener<SkillCubit, SkillState>(
  listenWhen: (a, b) =>
      a.noticeMessage != b.noticeMessage && b.noticeMessage != null,
  listener: (context, state) {
    if (!context.mounted) return;
    AppToast.show(
      context,
      message: state.noticeMessage == SkillCubit.marketplaceRepoAddedNoticeKey
          ? context.l10n.skillsMarketplaceRepoAdded
          : state.noticeMessage!,
      variant: TpToastVariant.success,
      duration: const Duration(seconds: 4),
    );
    context.read<SkillCubit>().clearError();
  },
  child: ...,
),
```

（若 `TpToastVariant.success` 不存在，用 `TpToastVariant.info` 或省略 variant 参数；以 analyze 为准。）

- [ ] **Step 5: 面板 widget 测试（来源行）**

`client/test/pages/skills/skill_discovery_section_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/pages/skills/skill_discovery_section.dart';
import 'package:teampilot/services/skill/marketplace/skill_marketplace_source.dart';

class _TmpSource implements SkillMarketplaceSource {
  @override
  String get id => 'tmp';
  @override
  String get label => 'Tmp Market';
  @override
  MarketplaceCapabilities get capabilities => const MarketplaceCapabilities();
  @override
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query) async =>
      const MarketplaceSearchResult(skills: [], hasNext: false);
}

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('skill-disc-section-');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('renders a toggle per registered marketplace', (tester) async {
    final cubit = SkillCubit(
      SkillRepository(),
      marketplaces: [_TmpSource()],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<SkillCubit>.value(
          value: cubit,
          child: Scaffold(
            body: SizedBox(
              height: 800,
              child: SkillDiscoverySection(onGoRepos: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tmp Market'), findsOneWidget);
    expect(find.text('Repos'), findsOneWidget);
  });
}
```

（import 补充：`dart:io`、`package:teampilot/services/io/local_filesystem.dart`、`package:teampilot/services/storage/app_storage.dart`，setUp/tearDown 模式同 `skill_cubit_test.dart`。）

- [ ] **Step 6: 跑全部相关测试 + analyze**

Run: `cd client && flutter test test/pages/skills/ test/cubits/skill_marketplace_cubit_test.dart test/cubits/skill_cubit_test.dart`
Expected: PASS

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error

- [ ] **Step 7: 提交**

```bash
git add client/lib/pages/skills/skill_discovery_helpers.dart client/lib/pages/skills/skill_discovery_section.dart client/lib/pages/skills/skill_management_page.dart client/test/pages/skills/skill_discovery_section_test.dart
git commit -m "feat(skills): registry-driven source row and unified marketplace panel wiring"
```

---

### Task 8: app_shell 接线 + 全量验证

**Files:**
- Modify: `client/lib/app/app_shell.dart`

**Interfaces:**
- Consumes: `SkillMarketplaceRegistry.builtIn`（Task 3）、`appSettings`（app_shell.dart:401 的 `SharedPrefsAppSettingsRepository`）、`skillRepo.skillsSh`（`SkillRepository` 字段）。
- Produces: `SkillCubit(marketplaces: ...)` 完整接线。

- [ ] **Step 1: 接线**

`client/lib/app/app_shell.dart` 的 `SkillCubit(...)` 构造（约 953 行）加参数：

```dart
  skillCubit = SkillCubit(
    skillRepo,
    marketplaces: SkillMarketplaceRegistry.builtIn(
      settings: appSettings,
      skillsSh: skillRepo.skillsSh,
    ),
    acquisitionEngine: skillAcquisitionEngine,
    onSkillUninstalled: teamCubit.removeSkillFromAllTeams,
    packAcquireActivity: packAcquireActivityAdapter,
  );
```

并加 import：

```dart
import '../services/skill/marketplace/skill_marketplace_registry.dart';
```

（若 `appSettings` 在 953 行作用域不可见，则改为在 `SkillMarketplaceRegistry.builtIn(settings: appSettings, ...)` 之前局部取用同一实例 —— 两个变量都在同一 `_buildAppShell`/`buildAppShell` 函数作用域内；以实际文件为准。）

- [ ] **Step 2: 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error

Run: `cd client && flutter test --exclude-tags integration`
Expected: 全部通过（含新增 marketplace 测试与既有 skill 测试）

- [ ] **Step 3: 提交**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(skills): wire marketplace registry into SkillCubit at bootstrap"
```

---

## Self-Review 结论（写入时已核对）

- **Spec 覆盖**：§2.1 模型（T1）、§2.2 注册表（T3/T8）、§2.3 skills.sh 适配（T3）、§2.4 SkillsMP 源（T2/T4）、§2.5 cubit 分槽（T5）、§2.6 UI 面板/卡片/来源行/配额态/l10n（T6/T7）、§3 数据流（T5 方法）、§4 错误处理（T2 429 + T5 槽 error）、§5 测试（每任务内建）。
- **无占位符**：每步含完整代码与命令。
- **类型一致性**：`MarketplaceSearchState`（T5）字段与面板 `slot` 读取（T6）一致；`marketplaceQuotaErrorKey`（T1）在 cubit（T5）与面板（T6）统一；`SkillCubit.marketplaceRepoAddedNoticeKey`（T5）在页面展示（T7）统一；`SkillMarketplaceRegistry.builtIn({settings, skillsSh})`（T3）与 app_shell 调用（T8）一致。
