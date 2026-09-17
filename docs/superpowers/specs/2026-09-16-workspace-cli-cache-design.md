# Workspace CLI runtime cache

- 日期：2026-09-16
- 状态：已批准
- 来源：Cursor 假 HOME 隔离，但 `plugins/cache` 链到 `~/.cursor/plugins/cache`，ApplyPlan 无法投影；账号插件缓存被所有 Cursor provider 串用。目标：CLI 运行时缓存在 TeamPilot 数据根下统一存放，按 CLI × provider 隔离，工作区层复用已有 `config/{tool}`。

## Goal

CLI 运行时缓存（解压树、npm `node_modules`、账号 marketplace 缓存）必须：

1. 落在 `teampilotRoot` 内（ApplyPlan 可投影，禁止链到操作系统 `$HOME`）。
2. 身份在 `providers/`，字节在 cache 根。`providers/{tool}/{id}/home` 只保留凭证。
3. 全局：`workspace/cache/cli/{tool}/{providerKey}/`。工作区层：**不**再开 `workspaces/{id}/cache`，用已有 `workspaces/{id}/config/{tool}/` inherit 全局缓存子树。会话 runtime / 假 HOME **只 ln**。
4. 键：有账号作用域的 CLI（Cursor）用 provider id；没有的用 `_shared`。

不把 TeamPilot **库**（`plugins/installed`、`plugins/marketplace-flavors`、`skills/installed`）搬进这棵树。

## Current state

| CLI | 今天 | 问题 |
|---|---|---|
| Cursor `plugins/cache` | 会话假 HOME ln → `~/.cursor/plugins/cache` | 出根；绑真实 home；多账号串缓存 |
| Cursor statsig / cli-config cache 字段 | 从 OS `$HOME` 暖拷进假 HOME | 同上 |
| OpenCode | `cli-defaults/opencode/{package.json,package-lock.json,node_modules}`，会话 inherit | 缓存在配置模板树里 |
| Codex `.tmp/plugins` | `cli-defaults/codex/.tmp/plugins` **不** inherit；每会话自建 | 位置分裂；远端故意不拷 |
| Codex `plugins/cache` | 会话 `CODEX_HOME` 下 | 未提升到全局 cache |
| Claude / FlashskyAI | 无此类运行时缓存；marketplace 走 flavor 库 | 不搬 |
| mixed Cursor 暖层 | `runtime/teams/{teamId}/cursor/plugins/…` | 团队配置，不搬 |

`cli-defaults/{tool}/` 是应用级 CLI **模板**（全应用一份底稿，主要 inherit `agents`）。大缓存不该放这里。`workspaces/{id}/config/{tool}/` 是工作区层 CLI 树：trust / `config.toml` 等派生配置 + inherit 下来的子目录。

## Layout

```text
<teampilotRoot>/workspace/
  cache/cli/{tool}/{providerKey}/
    …                                         # 全局运行时缓存
  workspaces/{workspaceId}/
    config/{tool}/                            # 工作区层：派生配置 + inherit 缓存子树
    sessions/{sessionId}/runtime/…            # 会话只 ln
```

`providerKey`：`providerId.trim()`，空则 `_shared`。

Inherit 与 `RuntimeLayout._ensureInheritedChild` 相同：

1. 全局根缺则 `ensureDir`：`workspace/cache/cli/{tool}/{key}/`。
2. 工作区 `config/{tool}/` 下对应 **相对名** inherit 全局（默认 ln；若已是实目录则保留为覆盖）。
3. 会话 CLI 期望路径 inherit 工作区 `config/{tool}/` 上同一相对名。

覆盖判定：工作区该节点已是实目录，而不是指向全局的 symlink。不要用「目录在不在」——inherit 总会创建节点。

### Cursor（账号 `acct-1`）

全局：`workspace/cache/cli/cursor/acct-1/plugins/cache`  
全局：`workspace/cache/cli/cursor/acct-1/statsig-cache.json`  
工作区：`config/cursor/plugins/cache`、`config/cursor/statsig-cache.json` inherit 上面。  
会话：`…/runtime/cursor/home/.cursor/plugins/cache` → ln 工作区那份。假 HOME 的 statsig 同理。

无 providerId 时 key=`_shared`。

### OpenCode

全局：`workspace/cache/cli/opencode/_shared/{package.json,package-lock.json,node_modules}`  
工作区 `config/opencode/` inherit 这三个名字。  
会话 `runtime/…/opencode/` inherit 工作区。

### Codex

全局：`workspace/cache/cli/codex/_shared/tmp-plugins/`  
全局：`workspace/cache/cli/codex/_shared/plugins-cache/`  
工作区 `config/codex/` inherit 时映射为 Codex 认识的相对名：`.tmp/plugins` ← `tmp-plugins`，`plugins/cache` ← `plugins-cache`。  
会话 `CODEX_HOME` 同样两个相对名 ln 到工作区。

cache 树内用 `tmp-plugins` / `plugins-cache`，避免全局 cache 目录名叫 `.tmp` 被 materializer 排除规则误伤。会话和工作区 `config/codex` 仍用 `.tmp/plugins`。

## What does not move

| 留下 | 原因 |
|---|---|
| `providers/{tool}/{id}/` | 账号、auth、probe |
| `cli-defaults/{tool}/agents` 及小配置 | 应用级模板 |
| `plugins/installed`、`marketplace-cache`、`marketplace-flavors` | TeamPilot 库 |
| `skills/installed`、`skills/repo-cache` | 技能库 |
| mixed `runtime/teams/{teamId}/cursor/` | 团队暖配置 |
| `config/{tool}/` 里的 trust、`config.toml`、MCP | 工作区派生配置，不是解压缓存 |
| 操作系统 `$HOME/.cursor` | 禁止再作为 staging 暖源 |

## Remote / ApplyPlan

路径都在 `teampilotRoot` 下，可投影、provided-link。

- **不要**把 `workspace/cache` 整树经 `WorkMachineMaterializer` 按文件 SFTP。ApplyPlan：work 上已有 → symlink；缺字节 → blob/tree。
- Codex：禁止恢复「materialize 整个 cli-defaults/.tmp」。首次由 native provision 写入 **全局 cache 根**，之后会话 ln。
- OpenCode `node_modules`：缺则在工作机 npm install（现有 `OpencodeSharedPluginDeps`），不要每会话 tar。

`RuntimeMaterializationPolicy.excludedSegments` 的 `.tmp` 继续排除 **cli-defaults** 下的 `.tmp`。新 `workspace/cache` 不走这条枚举。

## Session wiring

| CLI | 改动 |
|---|---|
| Cursor | 删除 `warmCacheHomeRoot`。`ensureDir` 全局 `plugins/cache`（空），inherit/ln 到假 HOME；不读 `$HOME`。statsig / `serverConfigCache` / `authInfo` 不再从真实 home 暖拷。 |
| OpenCode | `OpencodeSharedPluginDeps.sharedRoot` = 全局 cache 根；会话 inherit 经工作区 `config/opencode`。 |
| Codex | 不再「会话 rm+mkdir 空 `.tmp/plugins`」。ln 到 inherit 结果；native provision 写全局 `tmp-plugins`。 |
| Claude / FlashskyAI | 无运行时缓存可搬。 |

Inherit：会话 → `config/{tool}` → `workspace/cache/cli/{tool}/{key}`。缓存子树 **不**再从 `cli-defaults` inherit。

## First fill

TeamPilot **创建空目录并 ln**，不预填内容（OpenCode 除外，见下）。

| CLI | 第一份字节 |
|---|---|
| Cursor `plugins/cache`、statsig | `cursor-agent` 写入假 HOME（已 ln 到 cache）。第一次可慢。 |
| OpenCode `node_modules` | 仍由 `OpencodeSharedPluginDeps` 在 **全局 cache 根** `npm install`（不是从 `$HOME`）。 |
| Codex `.tmp/plugins`、`plugins/cache` | `codex` 插件命令写入（已 ln 到 cache）。 |

删除 `_seedWarmCaches` 对 OS home 的依赖。工具链 passthrough（`.cargo` / `.rustup`）不在本 spec，缓存路径禁止再引用 `ctx.paths.home`。

## Migration

- **禁止**再读操作系统 `$HOME` / `~/.cursor` 作为暖源（含 `plugins/cache`、`statsig-cache.json`、cli-config 里的 cache 字段）。全局 cache 根 `ensureDir` 空树，会话 ln 上去，由 CLI 自己写；第一次启动可以慢。
- OpenCode：`cli-defaults/opencode/node_modules` 若已完整，一次迁到全局 cache，会话改 inherit。
- Codex：`cli-defaults/codex/.tmp/plugins` 停止作为共享源；会话不再读它。
- 旧假 HOME 指向 `~/.cursor/...` 的 symlink：下次 staging `rm` 后接到 cache。

## Tests

- Cursor 假 HOME `plugins/cache` 的 target 在 `workspace/cache/cli/cursor/{id}/` 下（或经 `config/cursor` inherit），永不在 OS home。
- 两 provider id → 两棵全局 cache 树。
- 工作区 `config/{tool}/plugins/cache` 为实目录时，会话 ln 到工作区，不链全局。
- OpenCode 三个名字来自 cache 根（经 config inherit）。
- Codex 会话 `.tmp/plugins` 为 symlink（或 copy fallback）；native provision 写 cache 根。
- Projector：上述路径可投影。
- Materializer：`cli-defaults/codex/.tmp` 仍不出现在远端拷贝枚举。

## Phases

1. `WorkspaceCliCache` + Cursor 改源（去掉 `~/.cursor`）。
2. OpenCode deps 迁到 cache。
3. Codex `.tmp/plugins` 与 `plugins/cache` 迁到 cache。
4. 更新 `docs/workspace-storage-layout.md`。

## Out of scope

- TeamPilot marketplace git / flavor 搬家。
- mixed Cursor `runtime/teams/…` 搬家。
- `skills/repo-cache`、`mcp/discovery-cache` 收进 `workspace/cache`。
- `teampilot-apply` / CAS。
