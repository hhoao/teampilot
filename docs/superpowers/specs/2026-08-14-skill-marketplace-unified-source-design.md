# Skill Marketplace 统一抽象（skills.sh + SkillsMP 双源，注册表驱动）— 设计

日期：2026-08-14
状态：已评审（brainstorming 各节通过；用户委托定案：最优架构、可扩展性优先、不设工作量约束、不做向后兼容）

## 1. Context

TeamPilot 的 Skills 发现页目前有两个来源：**Repos**（本地/远程 git 仓库技能源，含同步/发现/过滤）和 **skills.sh**（远程 marketplace，独立面板 `SkillDiscoverySkillsShPanel` + 独立状态 `SkillsShSearchState` + 独立方法 `searchSkillsSh/loadMoreSkillsSh/installSkillsShEntry`）。

用户希望接入第二个 marketplace **SkillsMP**（skillsmp.com，200 万+ skills，独有 category/occupation/language/sortBy 过滤能力），并要求以**统一抽象**实现：新增源 = 加一个实现，不复制面板/状态代码。

### 外部事实（2026-08-14 核实）

| | skills.sh（已集成） | SkillsMP（新接入） |
|---|---|---|
| API | `GET https://skills.sh/api/search?q=&limit=&offset=` | `GET https://skillsmp.com/api/v1/skills/search?q=&page=&limit=&sortBy=&category=&occupation=&language=` |
| 限额 | 无 | 匿名 50 次/天、10 次/分；Bearer key 500 次/天 |
| 返回 | `{skills:[{id,name,skillId,source,installs}], count}`；`skillId` 即 repo 内子目录 | `{success,data:{skills:[{id,name,author,description,contentLanguage,githubUrl,stars,updatedAt}],pagination:{hasNext,total,...}}}`；**无子目录字段** |
| 过滤 | 无 | category/occupation/language(含 zh)/sortBy(stars\|recent)；列表端点不存在（OpenAPI 仅 search+health），取值需精编静态表 |

### 用户定案（brainstorming）

- 方案：**统一 marketplace 抽象**（注册表 + 共享面板/状态），重构现有 skills.sh 面板，不保留旧 API。
- 功能范围：**完整能力** —— SkillsMP 支持 category/occupation/language/sortBy；skills.sh 无过滤。
- 元数据：只展示 API 现有字段（skills.sh: installs；SkillsMP: stars + updatedAt + contentLanguage + description），**不做** GitHub API 富化（无 forks/下载量）。
- API key：**匿名 + 可选 Key**（存 `AppSettingsRepository`/SharedPrefs，面板内入口）。

## 2. 架构

```
services/skill/marketplace/
├── skill_marketplace_source.dart      # 接口 + 统一模型（SkillMarketplaceSource / MarketplaceSkill / …）
├── skill_marketplace_registry.dart    # SkillMarketplaceRegistry.builtIn()
├── skills_sh_marketplace_source.dart  # 包装现有 SkillsShService（本体不动）
└── skills_mp_marketplace_source.dart  # SkillsMP 实现（HTTP + 解析 + 配额）

SkillCubit（重构）：Map<String, MarketplaceSearchState> marketplace（按 sourceId 分槽）
  └─ 共享面板 pages/skills/skill_marketplace_panel.dart（按 capabilities 渲染过滤行）
      └─ pages/skills/marketplace_skill_card.dart（统一卡片：元数据行）
```

### 2.1 接口与模型（`skill_marketplace_source.dart`）

```dart
class MarketplaceSkill {
  final String key;                 // source 内唯一
  final String name;
  final String description;
  final String repoOwner;
  final String repoName;
  final String repoBranch;          // 固定 'main'
  final String? directory;          // repo 内子目录：skills.sh 有（一键装），SkillsMP null
  final String githubUrl;
  final int? installs;              // skills.sh
  final int? stars;                 // SkillsMP
  final int? updatedAt;             // SkillsMP（Unix 秒）
  final String? contentLanguage;    // SkillsMP（'zh'/'en'/…/null）
}

class MarketplaceCapabilities {
  final bool supportsCategory;
  final bool supportsOccupation;
  final bool supportsLanguage;
  final bool supportsSortBy;
  final Map<String, String> categoryChoices;    // slug -> 标签
  final Map<String, String> occupationChoices;  // slug -> 标签
  final List<String> languageChoices;           // ['zh','en',…]
  bool get hasAnyFilter;
}

class MarketplaceSearchQuery {
  final String query;
  final int page;                   // 1 基
  final int limit;                  // 固定 20
  final String? category;
  final String? occupation;
  final String? language;
  final String? sortBy;             // 'stars' | 'recent'
}

class MarketplaceSearchResult {
  final List<MarketplaceSkill> skills;
  final bool hasNext;
  final int total;                  // 仅展示用
}

abstract class SkillMarketplaceSource {
  String get id;                    // 'skillsSh' | 'skillsMp'
  String get label;                 // 展示名
  MarketplaceCapabilities get capabilities;
  Future<MarketplaceSearchResult> search(MarketplaceSearchQuery query);
  Future<void> setApiKey(String key);  // skills.sh no-op
}
```

异常（统一）：`MarketplaceFetchException`（非 2xx/解析失败/网络错误，携带可 l10n 消息）；`MarketplaceQuotaException extends MarketplaceFetchException`（429，提示注册 key）。

### 2.2 注册表（`skill_marketplace_registry.dart`）

```dart
abstract final class SkillMarketplaceRegistry {
  static List<SkillMarketplaceSource> builtIn({
    required AppSettingsRepository settings,   // app_shell.dart:401 的 SharedPrefsAppSettingsRepository
  }) => [
    SkillsShMarketplaceSource(SkillsShService()),
    SkillsMpMarketplaceSource(settings: settings),
  ];
}
```

`SkillCubit` 构造注入 `List<SkillMarketplaceSource> marketplaces`（app_shell 用 `SkillMarketplaceRegistry.builtIn(settings: appSettings)` 构建传入，`app_shell.dart:401` 的 SharedPrefs 实例）；**新增 marketplace = 往注册表加一个实现，UI/状态零改动**（来源行遍历该列表渲染 toggle）。

### 2.3 SkillsShMarketplaceSource（适配层）

- 包装现有 `SkillsShService`（`search(query, limit, offset)` 本体保留），offset = (page-1)*limit。
- 映射：`key=entry.key`、`directory=entry.directory`（= skillId，**可一键装**）、`installs`、`repoOwner/Name/Branch='main'`、`githubUrl=readmeUrl`、其余元数据 null。
- `capabilities`：全部 false；`setApiKey` no-op。
- `hasNext` = entries.length < totalCount；total = totalCount。

### 2.4 SkillsMpMarketplaceSource（新实现）

- 请求：`GET /api/v1/skills/search`，参数 `q/page/limit=20/sortBy/category/occupation/language`；每次搜索前经 `SettingsRepository` 读 `skillsMpApiKey`，非空则 `Authorization: Bearer <key>`。
- 解析：`data.skills[] → MarketplaceSkill`（`directory=null`、repoBranch='main'、githubUrl、stars/updatedAt/contentLanguage 透传；`author` 暂不展示）；`hasNext = data.pagination.hasNext`。
- 429 → `MarketplaceQuotaException`；503/其他非 200 → `MarketplaceFetchException`。
- `categoryChoices` / `occupationChoices` / `languageChoices`：**精编静态表**（skill_marketplace_source.dart 或本文件 const）。category 取 skillsmp.com/categories 主要分类（data-ai、devops、web-development、automation、data-analysis、marketing、productivity…）；occupation 取常用 SOC（software-developers、data-scientists、project-managers、devops-engineers…约 15 个）；language 取 `['zh','en','ja','ko','es','fr','de','pt','ru']`。
- `setApiKey(key)`：写 `AppSettingsRepository` 新增项 `skillsMpApiKey`（SharedPrefs impl + InMemory impl 同步加）。

### 2.5 SkillCubit 重构

```dart
class MarketplaceSearchState extends Equatable {
  final String query; final int page; final bool loading; final String? error;
  final List<MarketplaceSkill> entries; final bool hasNext; final int total;
  final String? category; final String? occupation; final String? language; final String? sortBy;
}
// SkillState：
//   删除 skillsSh 字段；新增 Map<String, MarketplaceSearchState> marketplace
```

方法（全部泛化，无 source 特判）：
- `searchMarketplace(String sourceId, {query, category, occupation, language, sortBy})` —— 重置该槽并首查（query 长度 <2 直接返回）；source 未知 → error。
- `loadMoreMarketplace(String sourceId)` —— 该槽 `loading || !hasNext` 守卫，page+1 追加。
- `installMarketplaceEntry(MarketplaceSkill e)` —— **唯一语义分叉点**：`directory != null` → 现有 `installFromDiscovery` 一键装（busyIds 管理）；否则 → `SkillRepoService.addRepo(owner/name/main)` + 消息提示"已加入仓库源，可到 Repos 页安装具体 skill"。
- `setMarketplaceApiKey(String sourceId, String key)` → 委托 source，随后 `clearMarketplaceError(sourceId)`。
- `clearMarketplaceError(String sourceId)`。
- 删除：`searchSkillsSh` / `loadMoreSkillsSh` / `installSkillsShEntry` / `SkillsShSearchState`。

### 2.6 UI

**`pages/skills/skill_marketplace_panel.dart`（新，共享面板）** —— 状态栏（`SkillManagementCard`）+ 结果区：
- 搜索框（enter/按钮触发，复用现有样式）；
- 过滤行：按 `source.capabilities` 渲染 —— `sortBy` 下拉（stars/recent）、`language` 下拉、`category` 下拉、`occupation` 下拉（`Wrap` 布局，变更即重搜，重置到 page 1）；无过滤能力则不渲染；
- 结果网格（复用现有 GridView 布局规则 1/2/3 列）+ `MarketplaceSkillCard`；"加载更多"按 `hasNext`；
- 空态：未搜索（提示图标）/ 无结果（复用 `skillsDiscoveryEmpty` 文案）；
- 配额错误态：`MarketplaceQuotaException` 时显示专用提示 + "填写 API Key"按钮 → `TpDialog` 输入 key（保存 → `setMarketplaceApiKey` 并重搜）。

**`pages/skills/marketplace_skill_card.dart`（新）**：name + description（两行截断）+ 元数据行（存在才显示：`★ stars`、`installs`、语言徽章、updatedAt 相对时间）+ GitHub 图标链接 + 安装按钮（busy 复用 busyIds）。`SkillDiscoverCard` 不动（Repos 页继续用）。

**`pages/skills/skill_discovery_section.dart` 改造**：
- `_SkillDiscoverySourceRow`：Repos toggle + 遍历 `SkillCubit.marketplaceSources`（或注入的 registry）渲染各 marketplace toggle（skills.sh / SkillsMP）；Repos 选中时显示原 refresh/sync 逻辑，marketplace 选中时显示对应面板；
- `_source` 状态改为 `repos | marketplaceSourceId`；
- 删除 `skill_discovery_skills_sh_panel.dart`（搜索条/网格逻辑并入共享面板）。

**l10n**：`app_en.arb` / `app_zh.arb` 新增键：来源标签（`skillsSourceSkillsMp`）、过滤标签（sort/语言/分类/职业）、元数据（stars/更新时间/语言徽章/installs 复用现有）、配额提示与 API key 按钮、addRepo 成功提示。

## 3. 数据流

```
面板(搜索/过滤变更) → cubit.searchMarketplace(sourceId, query)
  → registry 取 source → source.search(带 key) → 结果写入 marketplace[sourceId] 槽 → 面板重渲染
安装：卡片按钮 → cubit.installMarketplaceEntry(entry)
  → directory != null ? installFromDiscovery（一键装，busyIds）
    : addRepo(owner/name/main) + 提示
配额：429 → MarketplaceQuotaException → error 槽 → 面板专用错误态 + API key 弹窗
```

## 4. 错误处理

| 场景 | 处理 |
|---|---|
| 429（匿名额度耗尽） | `MarketplaceQuotaException` → 配额错误态 + API key 入口 |
| 非 2xx / 网络错误 / 解析失败 | `MarketplaceFetchException`（可 l10n 消息）→ error 槽 → 面板错误态 + 重试（重新搜索） |
| 未知 sourceId | cubit error，不崩 |
| addRepo 失败 | 复用现有 errorMessage 通道 |

## 5. 测试

- `skills_mp_marketplace_source_test.dart`：mock http —— URL/query 参数拼接、Bearer 头（有 key/无 key）、200 解析（含 hasNext/pagination）、429→QuotaException、503→FetchException、网络异常。
- `skills_sh_marketplace_source_test.dart`：现有 service（mock http）→ 统一模型映射（directory/installs/key）。
- `skill_cubit` marketplace 测试（fake source）：search 重置分槽、loadMore 追加与 hasNext 守卫、过滤变更重搜、install 分叉（directory 有 → installFromDiscovery；无 → addRepo）、setApiKey 委托、错误入槽。
- `skill_marketplace_registry`：builtIn 顺序与 id 唯一。
- （可选）面板 widget 测试：capabilities 驱动过滤行渲染。

## 6. 边界与不做

- 不改：Repos 本地发现流程、`SkillDiscoverCard`、`SkillsShService` 本体、安装管线（`SkillInstallService`/`SkillRepoService`/`SkillAcquisitionEngine`）。
- 不做：GitHub API 富化（forks/下载量）、SkillsMP 分类/职业列表端点（不存在，用精编静态表）、skills.sh 排行榜/趋势浏览、安装时解析 skillsmp 详情页取子目录。
- 向后兼容：不做 —— `SkillsShSearchState`/`searchSkillsSh`/`loadMoreSkillsSh`/`installSkillsShEntry` 删除，调用点一次性迁移（`skill_cubit.dart`、`skill_discovery_skills_sh_panel.dart` 移除，`skill_discovery_section.dart` 改造）。
