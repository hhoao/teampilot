# Plugin 管理设计方案

- 日期：2026-05-23
- 作者：hhoao
- 状态：草案，待评审

## 1. 背景与目标

TeamPilot 当前已实现 **Skill 管理**（Installed / Discovery / Repos 三段式），通过 GitHub 仓库 sync 单个 skill 包。Plugin 是与之并列的另一类扩展概念：一个 plugin 是 **Claude Code 风格** 的打包单元，可以同时包含 commands、agents、skills、hooks、MCP servers 五类子资源，通过 **marketplace**（带 `.claude-plugin/marketplace.json` 的 GitHub 仓库）分发。

底层 `flashskyai` CLI 已支持 plugin 加载，从固定路径读取——目录布局与 Claude Code 一致，但根目录为 `~/.flashskyai/plugins/`。TeamPilot 需要为用户提供一个统一的 plugin 管理界面，覆盖发现、安装、更新、卸载、按 team 启用等完整生命周期。

**核心目标**：

1. Plugin 与现有 Skill 管理在 UI / 服务 / 存储结构上高度对齐，降低用户与开发者的心智负担
2. TeamPilot 自维护 plugin 的安装目录与元数据；team 通过 linker 投影启用
3. 启用关系的 source of truth 是 `TeamConfig.pluginIds`，与现有 `skillIds` 完全对称

## 2. 架构总览

```
┌─────────────────────────────────────────────────────────────┐
│ UI Layer (Flutter)                                          │
│  PluginManagementPage  → Installed / Discovery / Marketplaces │
│  TeamConfigPage         → plugin 区块（启用入口）           │
│       │                                                     │
│       └─ PluginCubit ───┐                                   │
│       └─ TeamCubit ─────┤                                   │
└──────────────────────────┼──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ Service Layer (Dart)                                        │
│  PluginRepoService            marketplaces.json 读写        │
│  PluginRepoDiskCacheService   marketplace clone / 解析      │
│  PluginRepoGitService         git fetch + hash diff         │
│  PluginManifestService        plugin.json + 子资源解析      │
│  PluginFetchService           从 marketplace 拉取 plugin    │
│  PluginInstallService         install/update/uninstall      │
│  PluginRepository             已安装 plugin CRUD            │
│  TeamPluginLinkerService      pluginIds → team 目录投影     │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ Storage Layer                                               │
│  <teampilotRoot>/plugins/                  ← 已安装 plugin  │
│  <teampilotRoot>/plugins.json              ← plugin 元数据  │
│  <teampilotRoot>/plugin-marketplaces.json  ← marketplaces   │
│  <teampilotRoot>/plugin-backups/           ← 卸载/更新备份  │
│  config-profiles/teams/<teamId>/flashskyai/plugins/         │
│      ← 按 team 投影的链接/拷贝（CLI 实际加载源）            │
└─────────────────────────────────────────────────────────────┘
```

**与现有 Skill 管理的关系**：

- 完全独立的服务和数据流（marketplace 配置、cache、目录都独立）
- 共享底层基础设施：`AppPaths`、`FlashskyaiStorageRoots`、`CliDataLayout`、文件系统抽象（Local/SFTP）
- 复用 UI 框架：`WorkspaceHubPage` / `WorkspaceSplitShell` / `_Card` / `_EmptyBlock`，但有独立的页面和 cubit
- `TeamPluginLinkerService` 与 `TeamSkillLinkerService` 完全对称（同样的 3 层继承模型、symlink/copy fallback、SFTP 支持）

**Source of truth**：

| 数据 | 位置 |
|------|------|
| 已安装 plugin 文件 | `<teampilotRoot>/plugins/<plugin-id>/` |
| Plugin 安装元数据 | `<teampilotRoot>/plugins.json` |
| Marketplace 列表 | `<teampilotRoot>/plugin-marketplaces.json` |
| Team 启用关系 | `TeamConfig.pluginIds`（在 team 配置文件中） |

## 3. 数据模型

新增 `client/lib/models/plugin.dart`。

### 3.1 Plugin

```dart
class Plugin {
  final String id;                    // marketplaceOwner/marketplaceName/pluginName
  final String name;                  // plugin.json 的 name
  final String description;
  final String version;
  final String directory;             // 相对 <teampilotRoot>/plugins/ 的目录名
  final String? marketplaceOwner;     // null = 本地导入
  final String? marketplaceName;
  final String? marketplaceBranch;
  final String? homepageUrl;
  final String? readmeUrl;
  final PluginCapabilities capabilities;
  final String? contentHash;          // update detection
  final int installedAt;
  final int updatedAt;

  String get source =>
      marketplaceOwner != null ? '$marketplaceOwner/$marketplaceName' : 'local';
}
```

Plugin 模型只描述 plugin 本身，**不持有启用关系**（启用关系由 team 持有）。

### 3.2 PluginCapabilities（子资源摘要）

```dart
class PluginCapabilities {
  final List<PluginCommand> commands;     // commands/*.md
  final List<PluginAgent> agents;         // agents/*.md
  final List<PluginSkillRef> skills;      // skills/<name>/SKILL.md
  final List<PluginHook> hooks;           // hooks/hooks.json
  final List<PluginMcpServer> mcpServers; // .mcp.json
}

class PluginCommand   { final String name; final String? description; }
class PluginAgent     { final String name; final String? description; }
class PluginSkillRef  { final String name; final String? description; }
class PluginHook      { final String event; final String matcher; }
class PluginMcpServer { final String name; final String type; }  // stdio/http/sse
```

只读摘要，TeamPilot 不在 UI 中展示这些（保持列表清爽），仅用于：

- 卸载确认对话框中的"将影响 N 个 team" 计算（通过反查 `pluginIds`）
- 未来可能的"哪个 team 有哪些命令可用"派生信息

### 3.3 TeamConfig 扩展

在 `client/lib/models/team_config.dart` 的 `TeamConfig` 中新增字段（与 `skillIds` 完全对称）：

```dart
class TeamConfig {
  // ...既有字段...
  final List<String> skillIds;          // 已有
  final List<String> pluginIds;         // 新增
}
```

`pluginIds` 元素是 `Plugin.id`（即 `marketplaceOwner/marketplaceName/pluginName`）。`fromJson` / `toJson` / `copyWith` / equality / hashCode 按 `skillIds` 的模式扩展。

### 3.4 PluginMarketplace

对应 `.claude-plugin/marketplace.json` 的来源仓库：

```dart
class PluginMarketplace {
  final String owner;
  final String name;
  final String branch;
  final bool enabled;
  final String? displayName;     // marketplace.json 的 name（可能与 repo name 不同）

  String get fullName => '$owner/$name';
  String get githubUrl => 'https://github.com/$owner/$name';
}
```

### 3.5 DiscoverablePlugin / PluginUpdateInfo / PluginBackup / UnmanagedPlugin

模型与 skill 对应物对称（结构参考 [skill.dart](../../client/lib/models/skill.dart)）。`DiscoverablePlugin` 额外包含 `version` / `categories` / `keywords` 字段以支持过滤。

### 3.6 持久化文件结构

**`<teampilotRoot>/plugins.json`**：

```json
{
  "plugins": [ { "id": "...", "name": "...", ... } ],
  "updates": [ { "id": "...", "currentHash": "...", "remoteHash": "..." } ]
}
```

**`<teampilotRoot>/plugin-marketplaces.json`**：

```json
{
  "marketplaces": [ { "owner": "...", "name": "...", "branch": "main", "enabled": true } ]
}
```

首次加载时写入默认 marketplace（参考 `SkillRepoService._defaultRepos` 的预置模式）。

## 4. 服务层

服务模块严格对齐现有 skill 服务的结构。

| Plugin 服务 | 对应 skill 服务 | 核心职责 |
|------|--------------------|------|
| `PluginRepoService` | `SkillRepoService` | 读写 `plugin-marketplaces.json`；写入默认 marketplace |
| `PluginRepoDiskCacheService` | `SkillRepoDiskCacheService` | clone/拉取 marketplace 仓库；解析 `marketplace.json` |
| `PluginRepoGitService` | `SkillRepoGitService` | git fetch + hash 比对 |
| `PluginManifestService` | `SkillManifestService` | 解析 `.claude-plugin/plugin.json` 和子资源，产出 `PluginCapabilities` |
| `PluginFetchService` | `SkillFetchService` | 从 marketplace tarball 拉取单个 plugin 文件树 |
| `PluginInstallService` | `SkillInstallService` | install / update / uninstall / 备份 / 恢复 |
| `PluginRepository` | `SkillRepository` | 已安装 plugin CRUD 入口 |
| `TeamPluginLinkerService` | `TeamSkillLinkerService` | 根据 `TeamConfig.pluginIds` 投影 team 目录 |

### 4.1 PluginManifestService

**输入**：plugin 根目录路径
**输出**：`Plugin` + `PluginCapabilities`

主信息从 `.claude-plugin/plugin.json` 读取（`name` / `version` / `description` / `homepage` / `author`）。子资源扫描：

- `commands/*.md` → 解析 frontmatter 的 `description`
- `agents/*.md` → 同上
- `skills/<name>/SKILL.md` → 解析 frontmatter 的 `name` / `description`
- `hooks/hooks.json` → 读出 event + matcher 列表
- `.mcp.json` → 读出 server 名称与 type

`plugin.json` 不存在但有上述子资源 → 视为合法 plugin，从目录名推断 name（与 Claude Code 宽容策略一致）。

### 4.2 PluginInstallService 关键流程

**install(DiscoverablePlugin)**：

1. 调 `PluginRepoDiskCacheService` 确保 marketplace 已 sync
2. 解析 marketplace.json 中该 plugin 的 `source`，得到拉取方式
3. 调 `PluginFetchService` 复制到 `<teampilotRoot>/plugins/<plugin-id>/`
4. 调 `PluginManifestService` 生成 `Plugin` 记录，写入 `plugins.json`
5. 计算 `contentHash`
6. **不**自动启用（用户在 team 配置页选）

**installFromZip / installFromDirectory**：

1. 解压/复制到临时目录
2. 验证存在 `.claude-plugin/plugin.json` 或可识别子资源
3. 通过 `PluginManifestService` 产出 plugin 信息
4. 写入 `<teampilotRoot>/plugins/<plugin-id>/`，`plugin-id` 用 `local/<sanitized-name>` 形式

**update(Plugin)**：

1. 备份当前目录到 `<teampilotRoot>/plugin-backups/<backup-id>/`
2. 重新 fetch + 替换目录
3. 重新解析 capabilities
4. 对所有引用该 id 的 team 调用 `TeamPluginLinkerService.syncTeam(...)` 更新链接目标
5. 失败 → 从备份恢复

**uninstall(Plugin)**：

1. 备份目录
2. 调 `TeamRepository` 批量从所有 `TeamConfig.pluginIds` 中移除该 id
3. 调 `TeamPluginLinkerService.syncTeam(...)` 对受影响 team 移除链接
4. 删除 `<teampilotRoot>/plugins/<plugin-id>/`
5. 从 `plugins.json` 移除

**checkUpdates()**：对每个有 marketplace 来源的 plugin，调 git service 比对远端 hash，产出 `PluginUpdateInfo` 列表。

### 4.3 TeamPluginLinkerService

与 `TeamSkillLinkerService` 完全对称。核心方法：

```dart
Future<TeamPluginSyncResult> syncTeam({
  required String teamId,
  required List<String> enabledPluginIds,
  required List<Plugin> allInstalledPlugins,
  required CliDataLayout layout,
});
```

实现策略：

- Linux/macOS：symlink 到 `<teampilotRoot>/plugins/<dir>`
- Windows：优先 symlink（需要管理员/开发者模式），fallback 复制；与现有 `useWslSymlinks` 同一开关
- SSH 远程：拷贝（SFTP 不支持 symlink）
- 同步：生成预期集合 → diff 现有 team 目录 → 添加缺失/删除多余
- 错误聚合，部分失败可见（`linked` / `skippedMissingIds` / `errors`）

**调用时机**：

- Team 配置保存（`pluginIds` 变更）后由 `TeamCubit` 触发
- Plugin install/update/uninstall 后由 `PluginCubit` 对所有相关 team 触发
- Team 启动前由 `SessionLifecycleService` 兜底 sync
- Team 删除时调用一次，移除整个 `config-profiles/teams/<teamId>/flashskyai/plugins/` 目录

### 4.4 PluginCubit 状态

```dart
class PluginState {
  final List<Plugin> installed;
  final List<DiscoverablePlugin> discoverable;
  final List<PluginMarketplace> marketplaces;
  final List<PluginUpdateInfo> updates;
  final Set<String> busyIds;
  final Set<String> marketplaceSyncingKeys;
  final bool discoveryLoading;
  final bool updatesLoading;
  final String? errorMessage;
}
```

事件方法：`installFromDiscovery` / `installFromZip` / `scanUnmanaged` / `importUnmanaged` / `uninstall` / `update` / `updateAll` / `checkUpdates` / `refreshDiscoverable` / `addMarketplace` / `removeMarketplace` / `toggleMarketplaceEnabled`。

**不包含**任何按 team 启用的事件——这些在 `TeamCubit` 中通过修改 `pluginIds` 完成。

## 5. UI 与路由

### 5.1 路由

```dart
enum PluginSection { installed, discovery, marketplaces }
```

| 路径 | 页面 |
|------|------|
| `/plugins` | `PluginManagementHubPage` |
| `/plugins/installed` | `PluginManagementPage(section: installed)` |
| `/plugins/discovery` | `PluginManagementPage(section: discovery)` |
| `/plugins/marketplaces` | `PluginManagementPage(section: marketplaces)` |

无独立详情页路由。

### 5.2 Installed 段

只负责 plugin 库的生命周期管理，不展示 team 关系：

- 顶部操作行：`Update All` / `Import from Disk` / `Install from ZIP` / `Check Updates`
- 列表行：
  - 左：name + version 徽标 + source（`owner/name` 或 `local`）+ description（最多 2 行）
  - 右：`Update`（如有更新）/ `Uninstall`
- **不展示**子资源徽标、启用开关、team 关系

### 5.3 Discovery 段

- 顶部过滤：搜索框 / marketplace 下拉（all / 各启用的 marketplace） / 状态下拉（all / installed / uninstalled）
- 卡片网格：复用 `_SkillCard` 风格（独立组件 `_PluginCard`），展示 name / source / version / description / 安装按钮

### 5.4 Marketplaces 段

- 已添加 marketplace 列表（owner/name + branch + 启用 switch + sync 指示 + 删除按钮）
- "添加 marketplace" 表单（URL + branch 输入 + 添加按钮），复用 `parseGithubRepoUrl`

### 5.5 Team 配置页的 Plugin 区块

在 [team_config_page.dart](../../client/lib/pages/team_config_page.dart) 已有的 skill 区块旁加 plugin 区块，UI 风格与 skill 区块完全对称：

```
Plugins
选择本团队启用的 plugin

☑ my-awesome-plugin           v1.2.3
   owner/marketplace
☐ another-plugin              v0.3.0
   owner/marketplace
☐ local/dev-plugin            v0.1.0
   local
```

- 列表来源：`PluginRepository.loadAll()`
- 勾选状态来自 `TeamConfig.pluginIds`
- 保存团队时写入 `pluginIds` + 触发 `TeamPluginLinkerService.syncTeam(...)`
- 列表为空时提示"尚无可用 plugin" + 跳转 `/plugins/discovery` 的按钮
- 对 `pluginIds` 中存在但磁盘上找不到源的项目，显示灰色 "missing" 徽标 + 可手动移除

### 5.6 国际化

新增 i18n keys（中英文 ARB 同步）：

- `pluginsTitle / pluginsSubtitle`
- `pluginsNavInstalled / pluginsNavDiscovery / pluginsNavMarketplaces`
- `pluginsInstalledCount / pluginsUpdateAll / pluginsImportFromDisk / pluginsInstallFromZip / pluginsCheckUpdates / pluginsCheckingUpdates`
- `pluginsNoInstalled / pluginsNoInstalledHint / pluginsGoDiscovery`
- `pluginsCardInstall / pluginsCardInstalled / pluginsCardUpdate / pluginsCardUninstall`
- `pluginsMarketplaceAdd / pluginsMarketplaceUrl / pluginsMarketplaceBranch / pluginsMarketplaceRemoveConfirm / pluginsMarketplaceInvalidUrl`
- `pluginsUninstallImpactNTeams(n) / pluginsUninstallImpactList`
- `teamConfigPluginsSection / teamConfigPluginsSelect / teamConfigPluginsEmpty / teamConfigPluginsGoToDiscovery / teamConfigPluginsMissing`
- `pluginsCliUnsupportedBanner`

## 6. 边界场景

**A. 启用的 plugin 在磁盘上消失**

- `TeamPluginLinkerService.syncTeam(...)` 把"找不到源文件的 pluginId"聚合进 `skippedMissingIds`
- `TeamConfig.pluginIds` 中失效的 id **不主动清理**（用户重装同名 plugin 后无需重新勾选）
- Team 配置页 plugin 区块对失效项显示灰色 "missing" 徽标 + 手动移除按钮

**B. Plugin 卸载时仍被 team 引用**

- 卸载确认对话框预先实时计算所有引用该 id 的 team 列表，提示"将影响 N 个 team：[列表]"
- 用户确认后按 4.2 的 uninstall 流程级联清理 + 移除链接 + 删文件
- 任意步骤失败 → 回滚（恢复备份 + 恢复 `pluginIds`）

**C. Marketplace 移除/禁用**

- 移除 marketplace **不**级联删除已安装的 plugin（避免数据丢失）；已安装的 update check 显示"marketplace 不可达"
- 禁用 marketplace：Discovery 列表中过滤掉，但已安装的不受影响

**D. CLI 不支持 plugin 的 team（codex 等）**

- 允许保存 `pluginIds`（数据层不阻止）
- Linker 仍执行 sync
- Team 配置页 plugin 区块顶部显示 info banner：「当前 team CLI（codex）暂不支持 plugin，启用记录已保存但不会生效」
- CLI 升级后自动生效，无需用户重新勾选

**E. 同名 plugin 来自不同 marketplace**

- `Plugin.id` 包含 marketplace 路径，模型层不冲突
- Linker 在 team 目录下用 `<plugin-name>` 作目录名时若冲突，fallback 为 `<marketplaceOwner>__<plugin-name>`，并在 `syncTeam` 结果中报告
- UI 在受影响 plugin 上显示警告徽标

**F. 本地导入 plugin 的版本管理**

- `marketplaceOwner` 为 null，version 取 plugin.json 中的值（无则 `0.0.0+local`）
- 不参与 update check
- 重新导入即更新——通过相同 plugin-id 覆盖（先备份）

**G. SSH 远程模式（SFTP）**

- 所有 plugin 库操作通过 `FlashskyaiStorageRoots` 解析的 fs 抽象进行
- Linker 在 SFTP 下走 copy fallback
- Marketplace git clone 假设远端有 git 工具（与现有 skill 一致）

**H. plugins.json 并发写入**

- 复用现有"读-改-写"模式（短临界区，cubit 事件循环天然串行化）
- 不引入文件锁

## 7. 错误处理

服务层抛 `PluginException` 及子类：`PluginNotFoundException` / `PluginManifestException` / `PluginInstallException` / `MarketplaceUnreachableException`。

Cubit 捕获后 emit `errorMessage`，UI 通过 `BlocConsumer` 的 listener 弹 SnackBar 并清错（参考 [skill_management_page.dart:70-82](../../client/lib/pages/skill_management_page.dart#L70-L82) 的模式）。

| 场景 | 处理 |
|------|------|
| Manifest 解析失败 | 安装回滚，不写 `plugins.json` |
| Git clone 超时 | Marketplace sync 失败 + 重试按钮 |
| Symlink 创建失败 | Linker 自动 fallback 复制；记录 warning 不阻断 |
| 磁盘写满 | 安装中断 + 提示空间；保留备份 |
| 子资源解析部分失败 | capabilities 缺该项；不阻断安装；记录 warning |
| Update 失败 | 自动从备份恢复；提示用户 |

## 8. 测试策略

**单元测试**（`client/test/`）：

| 测试文件 | 覆盖 |
|---------|------|
| `plugin_manifest_service_test.dart` | 合法/非法 plugin.json；五种子资源解析；空目录 |
| `plugin_install_service_test.dart` | install / installFromZip / installFromDirectory / update / uninstall（含备份恢复）/ 重复 id |
| `plugin_repo_service_test.dart` | marketplaces.json 默认初始化；CRUD；启用切换 |
| `plugin_repo_disk_cache_service_test.dart` | marketplace clone / sync / dirty detection |
| `team_plugin_linker_service_test.dart` | 同步；symlink/copy fallback；缺失源；id 冲突；空 list；SFTP |
| `plugin_cubit_test.dart` | 各事件状态机；错误传播；busy id 跟踪 |
| `team_config_test.dart`（扩展）| `pluginIds` 字段的 json / `copyWith` / equality |

**Widget 测试**：

| 测试文件 | 覆盖 |
|---------|------|
| `plugin_management_page_test.dart` | 三段切换；空态；Installed 行操作；Discovery 过滤；Marketplaces CRUD |
| `team_config_page_plugin_section_test.dart` | plugin 区块勾选 → `pluginIds` 更新 → linker 调用；失效项展示 |

**集成测试**（沿用现有 PTY 集成测试模式）：

- `plugin_team_lifecycle_test.dart`：完整流程——添加 marketplace → 安装 plugin → 配置 team 启用 → 验证 team 目录链接 → 卸载 → 验证清理
- 标记 `@Tags(['integration'])`，沿用 `LD_LIBRARY_PATH` 等运行约定

## 9. 增量交付

虽然 MVP 是完整套，但内部分批落地：

1. **Phase 1 — 数据层**：模型 + manifest 服务 + 安装服务 + repository + plugins.json 持久化（无 UI，纯单测）
2. **Phase 2 — Plugin 管理页**：Installed / Discovery / Marketplaces 三段 + Cubit + 国际化
3. **Phase 3 — Team 集成**：`TeamConfig.pluginIds` + Team 配置页 plugin 区块 + `TeamPluginLinkerService` + 启动时 sync
4. **Phase 4 — 边界与可观察性**：失效项展示、卸载影响提示、CLI 不支持的 banner、错误聚合 UI、id 冲突 warning

每个 phase 独立可测、可合并。
