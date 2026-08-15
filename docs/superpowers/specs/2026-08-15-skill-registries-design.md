# Skills 注册中心 + 统一发现流设计

- Date: 2026-08-15
- Status: Approved (design review)

## 背景与目标

当前 Skills 发现能力由三套互不相关的机制组成：

1. **仓库源**（`SkillReposSection`，导航项 `repos`）：用户添加 GitHub 仓库（owner/name/branch），本地同步目录扫描 `SKILL.md` 得到 `discoverable`，在发现页以 `repos` tab 展示、本地过滤。
2. **skills.sh 市场**（`SkillsShMarketplaceSource`）：`/api/search`，需 ≥2 字查询。
3. **SkillsMP 市场**（`SkillsMpMarketplaceSource`）：`/api/v1/skills/search`，必须传 `q`，支持 `sortBy/category/occupation/language` 过滤；API Key 存在 `AppSettingsRepository`（settings.json），UI 入口只在配额错误时出现。

用户诉求：

- 将「仓库」导航项改造为 **注册中心**（像 MCP 的 `McpRegistriesSection` 一样管理源）。
- 用户可**扩展、自定、可配置**：支持添加自定义源（Git 仓库源 + API 源两种类型）。
- 发现页去掉 tab，所有已启用源的结果**合并成一个流**。
- 打开发现页自动展示**热门 + 仓库技能**。

约束：不要求向后兼容（旧存储可一次性迁移后废弃），按最佳架构、可扩展性设计，不考虑工作量。

## 总体架构

```
registries.json (唯一配置源)
    │  SkillRegistryConfigService.load()/save()
    ▼
SkillRegistryFactory.build(config, deps)   ← 配置驱动实例化
    ├── GitRepoRegistrySource        (kind: git, 本地目录扫描)
    ├── SkillsShRegistrySource       (kind: api, protocol: skillsSh)
    ├── SkillsMpRegistrySource       (kind: api, protocol: skillsMp)
    └── CustomApiRegistrySource      (kind: api, protocol: 用户选)   ← 可扩展点
    ▼
SkillCubit（统一状态）+ 统一发现 UI + 注册中心 UI
```

## 数据模型

文件：`client/lib/models/skill_registry_source.dart`

```dart
enum SkillRegistryKind { gitRepo, api }
enum SkillRegistryProtocol { skillsSh, skillsMp }   // api 源专用

class SkillRegistrySourceConfig {
  String id;                       // 'skillsSh' | 'skillsMp' | 自定义 id
  SkillRegistryKind kind;
  String label;                    // 用户可改显示名
  SkillRegistryProtocol? protocol; // api 源专用
  bool enabled;                    // 默认 true
  String? baseUrl;                 // api 源；默认官方地址
  String? apiToken;                // api 源（加密不必要；与 MCP 同款存明文）
  String? browseQuery;             // api 源默认浏览词（skills.sh 默认 'ai'）
  String? gitOwner, gitName, gitBranch;  // git 源（branch 默认 'main'）
}

class SkillRegistriesConfig {
  List<SkillRegistrySourceConfig> sources;
  static SkillRegistriesConfig defaults();
  SkillRegistrySourceConfig? byId(String id);
  Map<String, Object?> toJson();
  factory SkillRegistriesConfig.fromJson(...);
}
```

内置源：`skillsSh`（skills.sh）、`skillsMp`（SkillsMP）——不可删除，可禁用/改显示名/改地址/改浏览词/配 Token。

默认值：

| id | kind | protocol | baseUrl | browseQuery |
|----|------|----------|---------|-------------|
| `skillsSh` | api | skillsSh | `https://skills.sh` | `ai` |
| `skillsMp` | api | skillsMp | `https://skillsmp.com/api/v1` | （无；browse 用单字符+stars） |

## 存储与迁移

- 新文件：`skills/registries.json`（teampilotRoot 下），路径经 `AppPaths.skillRegistriesConfigPathForTeampilotRoot(root)` + `RuntimeContext.skillRegistriesConfigPath` 暴露（同 `mcpRegistrySourcesConfigPath` 模式）。
- `SkillRegistryConfigService`（`client/lib/services/skill/registry/skill_registry_config_service.dart`）：`load()/save()`，JSON 容错，缺失/损坏 → `defaults()`。模式同 `McpRegistryConfigService`。
- **一次性迁移**：首次加载且 registries.json 不存在时，读取旧 `repos.json`（→ git 源条目）与 settings `skillsMpApiKey`（→ SkillsMP apiToken），合并到默认配置后落盘；之后旧存储不再读取。迁移逻辑放 config service 内（注入 Filesystem + AppSettingsRepository 读取器），单元可测。

## 源接口

文件：`client/lib/services/skill/registry/skill_registry_source.dart`

```dart
class SkillRegistryQuery {
  final String query;          // 空 = browse
  final int page; final int limit;
  final String? category, occupation, language, sortBy;
}

class SkillRegistryPage {
  final List<MarketplaceSkill> entries;  // 复用现有模型
  final bool hasNext; final int total;
}

abstract class SkillRegistrySource {
  String get id;
  String get label;
  bool get enabled;
  SkillRegistryKind get kind;
  MarketplaceCapabilities get capabilities;   // 复用现有
  Future<SkillRegistryPage> search(SkillRegistryQuery q);
  Future<void> testConnection();
  Future<void> setApiKey(String key);
}
```

实现：

- **GitRepoRegistrySource**：持有 `SkillRepo`（owner/name/branch）+ `enabled`；`search` = 本地 `discoverable` 过滤（复用 `filterDiscoverableSkills`；query 非空时按名称/描述本地匹配，query 空 = browse 显示全部），恒 `hasNext=false`；`testConnection` = 触发一次仓库同步（复用 `SkillRepoDiskCacheService`）；`setApiKey` 无操作。
- **SkillsShRegistrySource**：基于现有 `SkillsShService.search`，baseUrl 可注入（协议固定 `/api/search?q&limit&offset`）；browse（query 空）= 用 `browseQuery`；query ≥2 字用搜索词；无过滤能力。
- **SkillsMpRegistrySource**：基于现有 SkillsMP 实现改造，baseUrl/apiToken 来自 config；browse（query 空）= `q=a` + `sortBy: stars`（已验证可分页）；capabilities 同现有（category/occupation/language/sortBy）。
- **CustomApiRegistrySource**：通用包装，`protocol` 决定 search/browse/capabilities 行为（即 skillsSh/skillsMp 两个协议实现），baseUrl/apiToken/label 来自用户配置。
- **`SkillRegistryFactory`**（`skill_registry_factory.dart`）：`build(SkillRegistriesConfig, deps)` → `List<SkillRegistrySource>`，内置 + 自定义源按配置实例化；替换 `SkillMarketplaceRegistry`（删除）。

行为约定：`search` 失败抛 `MarketplaceFetchException` / `MarketplaceQuotaException`（沿用现有异常类型）。

## 注册中心 UI

文件：`client/lib/pages/skills/skill_registries_section.dart`（替换 `skill_repos_section.dart`）

导航：`SkillSection.repos` → 重命名 `SkillSection.registries`（枚举值/路由段 `registries`，l10n `skillsNavRegistries`，icon 沿用 `Icons.source_outlined`）；`SkillManagementPage` body 分支同步替换；发现页 `onGoRepos` 引用改为注册中心。

布局（同构 MCP `McpRegistriesSection`）：

- 单个 `WorkspaceLibraryCard`，`TpCardHeader(title: l10n.skillsNavRegistries)`。
- 每源一行 `_RegistryRow`：主文本 = label（或 git `owner/name`、api baseUrl），副文本 = `@skills.sh · 已设置 Token` / `@分支`；Switch（enabled）+ 重置按钮（内置源恢复默认，自定义源删除）；行点按 = 编辑。
- 编辑对话框 `_RegistrySourceEditDialog`：
  - git 源：显示名 / owner / name / branch（无测试按钮——同步即测试，保存后后台同步）。
  - api 源：显示名 / baseUrl（hint 为默认）/ Token（`obscureText`，仅 protocol=skillsMp 显示，skillsSh 不显示）/ 浏览词（skillsSh 才显示）。
  - 测试连接按钮（api 源）：`testConnection()`，成功/失败 toast（复用 `mcpRepoTestOk`/`mcpRepoTestFailed` 风格文案，新增 skills 版 l10n）。
- 「添加注册源」按钮（卡片底部，FilledButton.icon）→ `_AddSourceDialog`：第一步选类型（Git 仓库 / API 源），API 源第二步选协议（skills.sh 兼容 / SkillsMP 兼容）；表单与编辑对话框共用。
- 重置确认用现有 `TpDialog` + `skillConfirmDialog` 风格。

## Cubit 统一状态

`SkillState` 新增（替换 `marketplace: Map<String, MarketplaceSearchState>` 与旧 `SkillsShSearchState`）：

```dart
List<UnifiedSkillEntry> discoveryEntries;   // 合并、去重
Map<String, int> discoveryPages;            // 每源已加载页数
bool discoveryLoading;
String? discoveryError;
bool discoveryBrowsing;                     // browse 模式（无查询自动加载）
```

`UnifiedSkillEntry`（`client/lib/models/unified_skill_entry.dart`）：

```dart
class UnifiedSkillEntry {
  final MarketplaceSkill skill;   // 复用现有模型（git 源包装成 MarketplaceSkill，directory=skillId）
  final String sourceId;
  final String? repoKey;          // git 源过滤用
}
```

去重键：`(repoOwner, repoName, directory)` 小写；同源分页内 & 跨源间都去重，保留先出现者。

Cubit 动作：

- `unifiedBrowse()`：query 空时的浏览模式——git 源贡献本地技能 + 每个 enabled API 源并发 `search(browse)` 第 1 页，合并。
- `unifiedSearch(String query, {filters})`：query ≥2 字 → 全 enabled 源并发第 1 页；query 空 → 回落到 `unifiedBrowse`。
- `unifiedLoadMore()`：对 `hasNext` 的源并发取下一页（page = `discoveryPages[sourceId]+1`），追加合并去重。
- `unifiedSetApiKey(sourceId, key)`：转发 `source.setApiKey`。
- 安装：`installUnifiedEntry(UnifiedSkillEntry)`——目录已知 → `installGitDir`（复用现有 `installMarketplaceEntry` 逻辑）；无目录（SkillsMP 降级）→ 把 repo 加入注册中心 git 源 + 提示（沿用 `marketplaceRepoAddedNoticeKey` 文案）。

`SkillCubit` 构造改为接收 `List<SkillRegistrySource>`（由 `SkillRegistryFactory` 在 `app_shell.dart` 组装），删除 `marketplaces`/`SkillMarketplaceRegistry`。

## 统一发现 UI

文件：`client/lib/pages/skills/skill_discovery_section.dart`（大改）+ 删除 `skill_marketplace_panel.dart`（逻辑并入统一面板）。

- 顶部行：搜索框（debounce 400ms，≥2 字触发 `unifiedSearch`）+ 源过滤 TpSelect（`all` + 各 enabled 源 label）+ 状态过滤（all/installed/uninstalled）+ 刷新按钮。
- capabilities 过滤行：沿用现有 `_FilterRow`（sortBy/language/category/occupation），仅对声明支持这些能力的源生效（SkillsMP 协议源）。
- 打开页面（initState）自动 `unifiedBrowse()`；同步 banner 沿用（git 源同步中）。
- 空态：无任何 enabled 源 → 引导去注册中心；有源但浏览无结果 → `skillsDiscoveryEmpty`。
- 结果网格：统一卡片（复用 `MarketplaceSkillCard`，含 source 标注 + 安装按钮）；installed 判定沿用 `skillInstalledKeys`。
- 单「加载更多」按钮（`discoveryLoading` 时禁用）。
- 错误态：`marketplaceQuotaErrorKey` → 错误卡片 +「去注册中心设置 Token」按钮（导航到 registries 节）+ 重试；其他错误 → 重试。
- 搜索框 placeholder 更新（不再区分 repos/skills.sh 提示）。

## 错误处理与安全

- 网络失败 → `MarketplaceFetchException`，UI 错误态 + 重试；429 → `MarketplaceQuotaException` → 引导配 Token。
- apiToken 明文存储于 `skills/registries.json`（与 MCP apiToken 同款处理），不入日志。
- 自定义 API baseUrl 无白名单限制（用户自担风险，同 MCP 行为）。

## 测试计划

- `client/test/models/skill_registry_source_test.dart`：模型序列化/默认值/byId。
- `client/test/services/skill/registry/skill_registry_config_service_test.dart`：load/save/损坏容错/一次性迁移（旧 repos.json + skillsMpApiKey → registries.json）。
- `client/test/services/skill/registry/skill_registry_sources_test.dart`：mock HTTP——各协议 search/browse/testConnection/quota。
- `client/test/cubits/skill_cubit_test.dart`：unifiedBrowse/unifiedSearch/unifiedLoadMore 合并去重、分页游标、错误。
- `client/test/pages/skills/skill_registries_section_test.dart`（widget）：行渲染/开关/编辑对话框/添加向导/重置。
- `client/test/pages/skills/skill_discovery_section_test.dart`（widget）：统一流渲染、browse 自动加载、过滤、加载更多、quota 引导。
- 回归：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`。

## 涉及文件清单

| 文件 | 动作 |
|------|------|
| `client/lib/models/skill_registry_source.dart` | 新增 |
| `client/lib/models/unified_skill_entry.dart` | 新增 |
| `client/lib/services/skill/registry/skill_registry_config_service.dart` | 新增 |
| `client/lib/services/skill/registry/skill_registry_factory.dart` | 新增 |
| `client/lib/services/skill/registry/skill_registry_source.dart` | 新增 |
| `client/lib/services/skill/registry/git_repo_registry_source.dart` | 新增 |
| `client/lib/services/skill/registry/custom_api_registry_source.dart` | 新增 |
| `client/lib/services/storage/app_storage.dart` / `runtime_context.dart` | 加 `skillRegistriesConfigPath` |
| `client/lib/services/skill/marketplace/skills_sh_marketplace_source.dart` | 删除（并入 SkillsShRegistrySource） |
| `client/lib/services/skill/marketplace/skills_mp_marketplace_source.dart` | 删除（并入 SkillsMpRegistrySource） |
| `client/lib/services/skill/marketplace/skill_marketplace_registry.dart` | 删除 |
| `client/lib/cubits/skill_cubit.dart` | 统一状态 + 动作 |
| `client/lib/pages/skills/skill_section.dart` | repos → registries |
| `client/lib/pages/skills/skill_registries_section.dart` | 新增（替换 skill_repos_section.dart） |
| `client/lib/pages/skills/skill_discovery_section.dart` | 统一流 |
| `client/lib/pages/skills/skill_marketplace_panel.dart` | 删除（并入统一面板） |
| `client/lib/app/app_shell.dart` | SkillCubit 装配改为 factory |
| `client/lib/repositories/app_settings_repository.dart` | 删除 skillsMpApiKey 存取（迁移后） |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | 新增/更新文案 |
| `client/lib/pages/skills/skill_discover_card.dart` 等 | 视需要清理 |

## 非目标（YAGNI）

- 不做注册源协议插件动态加载（用户配置即可满足"可扩展"；新增协议=新增一个实现类）。
- 不做 token 加密/钥匙串。
- 不做统一排序策略（按源返回顺序 + 去重，`sortBy` 仅透传给支持源）。
- 不做跨源结果分页对齐（各源独立游标，单按钮推进）。
