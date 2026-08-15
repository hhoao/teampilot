# Skills/Plugins/MCP 发现与市场刷新策略 — 设计

日期：2026-08-15
状态：已评审（brainstorming 各节通过）

## 1. Context

Skills 发现、Plugins 发现（市场）、MCP 发现三个页面目前都有**打开即检查远端**的行为：

| 页面 | 现状 |
|---|---|
| Skills | `SkillCubit.ensureDiscoveryLoaded` → `_syncReposInBackground` → `SkillRepoDiskCacheService.ensureSynced`：每次都对每个启用 repo 做一次 GitHub commit SHA 检查，SHA 变化才重下 |
| Plugins | `PluginCubit.ensureDiscoveryLoaded` → `_syncMarketplacesInBackground` → `PluginRepoDiskCacheService.syncMarketplace`：每次 git 检查远端 SHA，变化才重拉 |
| MCP | `McpDiscoveryCubit.initialize`：hydrate 磁盘缓存后，快照为空（无缓存）才 `_warmRemoteCaches` 拉远端；手动刷新按钮总是强制拉取 |

问题：用户每次打开发现页都会触发网络请求（即使缓存新鲜、远端无新 commit）；仓库一有新 commit 就会重拉。用户希望**默认纯手动刷新**，自动刷新作为可配置项（默认关，开启后按 24h TTL 检查）。

### 用户定案（brainstorming）

- 刷新策略：**手动刷新为默认**；打开发现页只显示磁盘缓存、不发网络请求。
- **自动刷新做成设置项，默认关**；开启后按 **TTL（24h）** 检查：缓存年龄 < 24h 不检查远端，≥ 24h 才检查远端 SHA 并更新。
- 作用范围：**一个全局开关**，同时控制 skills / plugins / mcp 三个发现页。
- 例外：**首次无缓存时仍自动拉取一次**（初始化），之后不再自动刷新。
- 手动刷新按钮不受限，总是强制更新。
- 配置位置：**App 设置页**，新增「发现与市场」分组（settings 弹窗 + `/config/discovery` 路由 + Android hub）。
- 实现层次：TTL 下沉到缓存服务层（方案 A）。

## 2. 架构

```
AppSettingsRepository（SharedPreferences teampilot.app_settings.v1）
  └─ loadDiscoveryAutoRefreshEnabled() / saveDiscoveryAutoRefreshEnabled(bool)   # 默认 false
      └─ DiscoverySettingsCubit（新）—— 设置页与三个发现 cubit 共享

services/discovery/discovery_refresh_policy.dart（新）
  └─ const ttl = Duration(hours: 24)   # 唯一 TTL 常量，固定值（不可配置）

SkillRepoDiskCacheService.ensureSynced(repo, {force, requiredRelativePaths, maxStaleness})  # 改
PluginRepoDiskCacheService.syncMarketplace(m, {force, maxStaleness})                        # 改

SkillCubit.ensureDiscoveryLoaded({force})   # 改：策略判断
PluginCubit.ensureDiscoveryLoaded({force})  # 改：策略判断 + force 透传修复
McpDiscoveryCubit.initialize()              # 改：策略判断

pages/config/discovery_config_section.dart（新）——「发现与市场」设置分组（开关行）
config_workspace.dart / app_router.dart / config_cubit.dart / android_shell_chrome.dart / app_keys.dart  # 注册新分组
```

## 3. 行为规格

### 3.1 服务层 TTL（`maxStaleness`）

两个缓存服务的入口新增可选参数 `Duration? maxStaleness`：

- `maxStaleness == null`（默认）：保持现状——有缓存也检查远端 commit SHA，变化才更新。
- `maxStaleness != null` 且存在可信磁盘缓存（`meta.json` 完整、branch 匹配）：`now - meta.syncedAtMs < maxStaleness` → **直接返回磁盘缓存，零网络请求**（不发 SHA 请求）；否则走现有检查流程。
- 无磁盘缓存（首次）：无视 TTL，总是同步一次（初始化）。
- `force == true`：无视 TTL，总是检查远端。

### 3.2 Cubit 策略

| 场景 | 自动刷新=关（默认） | 自动刷新=开 |
|---|---|---|
| 打开发现页，有磁盘缓存 | 只显示缓存，零网络请求 | 缓存 <24h：只显示缓存；≥24h：检查远端 SHA 并更新 |
| 打开发现页，无缓存（首次） | 自动拉取一次完成初始化 | 自动拉取 |
| 手动刷新按钮 | 总是强制（force: true） | 总是强制（force: true） |

**SkillCubit.ensureDiscoveryLoaded：**

```
if force: refreshDiscoverable(force: true)
elif 自动刷新开: refreshDiscoverable()  → syncRepoCache(repo, maxStaleness: ttl)
elif discoverable 非空: return                    # 内存已有 → 不动
else: 磁盘聚合 + 仅对「无缓存」的 repo 同步一次     # 有缓存的 repo 不发网络
```

**PluginCubit.ensureDiscoveryLoaded：** 同上；顺带修复 `_syncMarketplacesInBackground` 中 `_diskCache.syncMarketplace(m)` 不透传 `force` 的问题（`plugin_cubit.dart:245`），改为 `syncMarketplace(m, force: force, maxStaleness: …)`，使手动刷新真正强制。

**McpDiscoveryCubit.initialize：**

```
hydrateFromDisk()
自动刷新关 && 有磁盘缓存(任一动 → 快照非空): 不 warm
自动刷新关 && 无缓存: 照旧 warm（首次初始化）
自动刷新开: 检查磁盘快照 syncedAtMs，≥24h 才 warm；无缓存则 warm
```

`_hydrateSourceFromDisk` 已读取磁盘快照（含 `syncedAtMs`），在快照上判断即可；「磁盘缓存新鲜」= 快照非空且 `now - syncedAtMs < ttl`。手动 `refreshRemote()` 不受限。

### 3.3 错误处理

- 网络失败：保持现有回落行为——skills/plugins 复用磁盘缓存；MCP 保留已加载缓存并显示错误。
- 首次初始化失败：维持现状（skills 显示错误信息；MCP 显示空态/错误），用户可点刷新重试。
- TTL 判断的缓存年龄以 `meta.json` / 磁盘快照的 `syncedAtMs` 为准；meta 缺失/损坏 → 视为无缓存，走初始化同步。

## 4. 设置 UI

- 新分组「发现与市场」（icon `Icons.storefront_outlined`），放在 **Download Sources** 之后、**Shortcuts** 之前（settings 弹窗与 `/config/*` 路由同步注册）。
- 内容：一个开关行「自动刷新发现/市场」+ 说明文案（"开启后，打开发现页时若缓存超过 24 小时将自动检查更新；默认关闭，手动刷新始终可用"）。
- 持久化走 `DiscoverySettingsCubit` → `AppSettingsRepository`；开关即时生效，无需重启。
- 新增 l10n：`app_en.arb` / `app_zh.arb`（分组标题、副标题、开关标题、说明）。

## 5. 测试

- `SkillRepoDiskCacheService`：TTL 内不发网络（mock fetch 不被调用）；过期/force/无 meta 时发网络；meta 缺失按无缓存处理。
- `PluginRepoDiskCacheService`：同上（mock git service）。
- `SkillCubit` / `PluginCubit`：自动刷新关 + 有缓存 → 不发同步；开 + 新鲜缓存 → 不发；开 + 过期 → 同步；force → 同步；首次无缓存 → 初始化同步。
- `McpDiscoveryCubit`：自动刷新关 + 有快照 → 不 warm；关 + 无快照 → warm；开 + 新鲜快照 → 不 warm；开 + 过期快照 → warm。
- `AppSettingsRepository`：新键读写、默认 false、InMemory 实现同步更新。
- l10n 补齐 zh/en。

## 6. 范围外

- TTL 时长不做可配置项（固定 24h 常量）。
- 不做「首次使用引导弹窗」。
- 不改 Hub（TeamHub/ExpertHub）的 git clone 行为。
