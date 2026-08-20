# TeamPilot Catalog MCP：Agent 管理 Skill / Plugin / MCP

- Date: 2026-08-19
- Status: Approved
- Implementation: `client/lib/services/catalog/`

## 背景与目标

TeamPilot 的 skill / plugin / MCP 只存在应用目录里（`<teampilotRoot>/skills/installed`、`plugins/installed`、`mcp/mcp_servers.json`），再按 workspace / expert / team 绑定，启动时 `reconcile` 进隔离 `CONFIG_DIR`。

Agent 没有调用这条链路的入口。它们按 Claude Code 习惯往 `~/.claude/skills`、`.claude/skills`、`~/.claude.json` 写，或跑 `claude mcp add` / `npx`，结果：

1. 落在隔离 CONFIG_DIR 里，下次 connect 被 `ResourceMaterializer.reconcile` 清掉。
2. 进不了 Home 里的全局库，UI 与下次启动都看不见。
3. 社区 skill 经常是 npm / 脚本装完得到一个目录，现有 SCRIPT acquire 只认已经出现在 `skills/installed/` 下的结果，对不上这个习惯。

目标：会话里的 agent 能 **搜索、安装、导入、创建、修改、卸载** 与 UI 同一份全局库，并自动绑到当前工作区。下次启动（含团队会话，bundle 是 union）生效。

## 已锁定的产品契约

| 项 | 决定 |
|---|---|
| 生效时机 | 写入库 + 绑当前工作区；本次会话不热装。工具返回 `restart_required: true`。 |
| 数据层 | 全局库（与 Home → Skills / Plugins / MCP 同一份）+ `project-config.json` 绑定。 |
| 信任 | 走 CLI 对 MCP tool 的 Allow once / Always。不另做 TeamPilot 弹窗。skip-permissions 则直接执行。 |
| 发现 | 始终注入的 **skill** 用 description 触发（对齐 Claude Code 的安装-skill）；**MCP 做变异**。Prompt 只留一句指向该 skill。 |
| 纳入 | `install_*`（应用去拉）+ `import_*`（已有目录，含 npx/脚本产物）。 |
| Plugin 从零创建 | v1 不做（`supportsCreate = false`，不暴露 `create_plugin`）。 |
| Prompt 资源 | 不是可安装目录。人设仍走 Expert / Team。本设计不引入 Prompt catalog。 |

## 非目标（v1 行为；扩展点保留）

- 当前会话热生效（事件总线预留，见下文）。
- 绑到 team / expert profile（工具参数预留 `bind_to`，v1 只接受 `workspace`）。
- 从零创建 plugin 包。
- 把 CLI 原生命令（`claude mcp add`、`/plugin install`）拦截改写。
- 扩展 / hook 的 catalog CRUD（kind 模块可后续注册）。

## 总体架构

变异走应用进程，发现走 Claude Code 同款 skill 触发，传输走已有 loopback MCP。

```
用户：「帮我装 superpowers / 加个 context7 / npx 装完这个目录」
        │
        ▼
  teampilot-catalog skill（description 命中 → 加载正文）
        │
        ▼
  MCP server `teampilot`  （/catalog/mcp）
        │
        ▼
  CatalogKindRegistry.module(kind).handle(op, ctx)
        │
        ├── SkillCatalogModule    → SkillAcquisitionEngine / SkillInstallService
        ├── PluginCatalogModule   → PluginInstallService
        └── McpCatalogModule      → McpRepository / McpListingInstallService
        │
        ▼
  全局库 + WorkspaceProjectConfig.bundle
        │
        ▼
  CatalogMutationBus  → cubit 刷新 UI
  工具结果             → restart_required: true
```

三条原则：

1. **Kind 模块可插拔。** MCP 工具表由 registry 生成，不在 handler 里写死 20 个 `if (kind)`。后续 hook / extension 只加模块，不加第二套 MCP。
2. **不把 launch 侧的 Provider/Assembler 合成一个泛型 Resource。** 那套已经按 kind 分契约（2026-08-18）。Catalog CRUD 是另一条轴：应用目录的读写。两边只在「绑定 id 进入 `ConfigBundle` → 下次 provision」处汇合。
3. **Loopback gateway 按 path 挂应用 MCP。** Catalog 不塞进 `teammate-bus` 的 tool 列表（mixed 才有 bus；simple 没有）。SSH 隧道已经打到同一端口，新 path 自动可用。

## 组件

### 1. App loopback 路由

今天 `TeammateBusMcpGateway._onRequest` 在识别 path 之前就要求 session 已 `register()`（mixed TeamBus）。Simple 会话没有 delegate，不能复用 `/mcp`。

把 gateway 收成 **path 路由表**（可仍叫原类，内部拆 `LoopbackHttpRouter`）：

| Path | 何时可用 | 是否需要 TeamBus register |
|---|---|---|
| `/mcp` | mixed | 是 |
| `/idle` | mixed | 是 |
| `/catalog/mcp` | **所有会话** | **否** |
| `/agent-status` | 已有 | 否（已是 status-only） |
| `/ask-user-answer` | 已有 | 否 |

`/catalog/mcp` 认证：

- 必须 `X-Session`，且 `SessionRepository` 能解析到该 session（从而得到 `workspaceId`）。
- `X-Member` 可选（审计 / 日志）。
- 远端与 teammate-bus 相同：`X-Bus-Token` 或现有隧道握手。未注册 TeamBus 的 simple 本地会话不需要 token。

解析失败返回 MCP 错误，不返回会让 Claude Stop hook 重试死循环的 4xx（对齐 agent-status 的谨慎态度：JSON-RPC error 写在 200 体里，或 204/200 + isError）。

服务器广告名：`teampilot`（`mcpServers` key 与 Claude 权限名 `mcp__teampilot__<tool>`）。

### 2. 注入：每个会话都带 `teampilot` MCP

在 `ExtraMcpContributionProvider` / `extraMcpServers` 装配点，**simple 与 mixed、本地与 SSH 一律**加入：

```json
{
  "teampilot": {
    "type": "http",
    "url": "http://127.0.0.1:<port>/catalog/mcp",
    "headers": {
      "X-Session": "<sessionId>",
      "X-Member": "<memberId or sessionId for simple>"
    }
  }
}
```

CLI 若对 teammate-bus 走 stdio bridge，catalog 用同一套 bridge 策略（stdio 无 HTTP 6 分钟超时；install/import 可能超过 HTTP 超时）。具体：与 `resolveMemberBusMcpTransportConfig` 平行增加 `resolveCatalogMcpTransportConfig`，按 CLI 选 http vs stdio，stdio args 多一个 `--path /catalog/mcp`（或独立 `--catalog-url`）。

**不要**把 `mcp__teampilot` 整组加入 `mixedTeamSessionAllowTools`。只预授权只读工具（见权限）。

### 3. CatalogKindModule（扩展点）

```dart
enum CatalogOp { search, list, read, install, importPath, create, update, unbind, delete }

abstract interface class CatalogKindModule {
  String get kind; // 'skill' | 'plugin' | 'mcp'
  bool get supportsCreate;
  bool get supportsImport;
  bool get supportsInstall;
  CatalogToolSet advertise(); // 生成 tools/list 条目
  Future<CatalogResult> handle(CatalogOp op, CatalogRequest req);
}
```

v1 注册三个模块。`supportsCreate == false` 的 kind 不出现 `create_<kind>`。工具名稳定为 `<op>_<kind>`（`install_skill`、`import_plugin`）。

通用参数（写操作）：

| 字段 | v1 | 扩展 |
|---|---|---|
| `bind_to` | 只允许 `"workspace"`；缺省即 workspace | 以后加 `team` / `expert` |
| `overwrite` | import/install 冲突时 | — |

写成功统一结果：

```json
{
  "ok": true,
  "kind": "skill",
  "ids": ["owner/repo:name"],
  "bound_to": "workspace",
  "workspace_id": "...",
  "restart_required": true,
  "message": "Installed and bound to this workspace. Reconnect the session to use it."
}
```

失败为 `isError` + 机器可读 `code`（`not_found`、`already_exists`、`unsupported_op`、`unsafe_path`、`unsafe_script_url`、`bind_scope_unsupported`、`no_skill_md`、`wrong_kind`）。

内部不要调 cubit。模块调 repository / acquisition engine；成功后 `CatalogMutationBus.emit`。`app_shell` 订阅 bus，转 `SkillCubit.loadAll` / `PluginCubit` / `McpCubit` / `WorkspaceProjectConfigCubit`。以后若要热装，只加订阅者（`SessionResourceRematerializer`），不改 MCP 契约。

### 4. Skill 模块

| 工具 | 行为 |
|---|---|
| `search_skills` | 复用现有 registry 统一搜索（skills.sh / git / SkillsMP）。 |
| `read_skill` | 返回 id、name、description、`SKILL.md` 正文、相对文件列表。 |
| `install_skill` | git（owner/name/directory/branch）、marketplace key、或 `script_url`（现有 `SkillAcquisitionEngine`，含 URL 安全检查）。成功则 bind。已安装则只 bind（幂等）。 |
| `import_skill` | 见「导入」。 |
| `create_skill` | 在 `skills/installed/<dir>/` 写入 `SKILL.md` 及可选 `files{}`，manifest id `local:<dir>`，bind。 |
| `update_skill` | 按 id 改库内文件（patch 或整文件替换）。 |
| `unbind_skill` | 只从当前 workspace bundle 去掉 id，不删库。 |
| `delete_skill` | 与 UI 卸载相同：删库 + 已有 `onSkillUninstalled` 从所有 team/workspace 清引用。 |

跨 kind 只有 `list_installed({kind})`（kind 必填）。search / read / 变异工具按 kind 分名，便于 description 触发和 CLI 权限「只允许装 skill、不允许删 MCP」。

### 5. Plugin 模块

与 skill 对称：`search_plugins`、`read_plugin`、`install_plugin`、`import_plugin`、`update_plugin`（覆盖安装 / 已有更新检查）、`unbind_plugin`、`delete_plugin`。无 `create_plugin`。

导入识别：目录含 `plugin.json` 或 `.claude-plugin/plugin.json`（及现有 PluginInstallService 所认的包布局）。对 skill 目录误调 `import_plugin` 返回 `wrong_kind` 并提示 `import_skill`。

### 6. MCP 模块

没有「目录包」语义。

| 工具 | 行为 |
|---|---|
| `search_mcp` | 现有 MCP registry / Smithery listing。 |
| `read_mcp` | 返回 spec，**剥离 env/header 里的密钥**（只留 key 名）。 |
| `install_mcp` | listing id → `McpListingInstallService.draftFromListing` → upsert → bind。 |
| `create_mcp` | 直接 upsert `McpServerSpec`（stdio / http）。`npx -y pkg` 是 spec 的 `command/args`，不是 import 目录。 |
| `import_mcp` | 工作 fs 上的 `.mcp.json` 或 `mcpServers` JSON 片段 → upsert + bind。 |
| `update_mcp` | 改 spec。 |
| `unbind_mcp` / `delete_mcp` | 同 skill。 |

### 7. 导入（社区 npm / 脚本 / clone）

这是相对 Claude Code 多出来的一步：Claude 装完目录会被自己扫到；TeamPilot 必须 **收进应用库**。

`import_skill` / `import_plugin`：

1. `path` 是当前会话 **工作文件系统** 上的路径（本地 = 本机；SSH = SFTP `workFs`）。控制面用工作 fs **读**，写入 **home** 的 `skills/installed` 或 `plugins/installed`（拷贝，不符号链接 `node_modules` / `~/.claude/skills`）。
2. 发现规则（skill）：
   - `path/SKILL.md` 存在 → 导入该目录；
   - 否则扫描 `path` 下一层子目录的 `SKILL.md`；
   - 再否则扫描 `path/skills/*`（常见 pack 布局）；
   - 都没有 → `no_skill_md`。
3. 每个命中目录 copy 到 `skills/installed/<basename>`，manifest `local:<basename>`（若来源能解析 git remote 则用 `owner/repo:basename`）。`overwrite=true` 时覆盖。
4. 全部 bind 到当前 workspace。

路径沙箱（`unsafe_path`）：

- 允许：该 session 的 working directory、`additionalDirectories`、以及这两棵树下的子路径。
- 拒绝：`<teampilotRoot>` 下除 `skills/installed`/`plugins/installed` 以外的配置与凭证；`/etc`、他人 home；跟随指向沙箱外的 symlink。

SCRIPT / npx 由 **agent 自己用 Bash 跑**（Claude Code 习惯，且安装器会写到各种各样的目录）。TeamPilot 不在 v1 里代跑任意 `npx`（输出目录不确定）。`install_skill({script_url})` 只保留现有、已约束的 HTTPS 脚本通道。MCP 的 JSON 文件走 `import_mcp`，同样受工作 fs + 路径沙箱约束。

### 8. 绑定

`LayeredConfigBundle.merge` 是 **union**（team ∪ expert ∪ workspace）。绑到 workspace 后，该 workspace 里下次启动的 simple **和** 团队会话都会带上。

v1 只改 `WorkspaceProjectConfig.bundle`。`bind_to != workspace` → `bind_scope_unsupported`。

### 9. 触发 skill + 一句 prompt

#### 始终注入的 skill

- **id / invocation name:** `teampilot-catalog`
- **来源:** `SkillContributionProvider`，`ResourceOriginKind.managed`，`providerId: teampilot-catalog`
- **不进** 用户 `skills/installed` 清单，用户不能卸载。每次 provision 都链进 CLI `skills/` 目录。
- **仓库内源文件:** `client/lib/services/catalog/managed_skills/teampilot-catalog/SKILL.md`（随应用分发，写入一个 managed 源目录再当 `SkillDirectoryArtifact`）。

**description** 对齐 Claude Code「安装 skill」那类 skill 的触发写法（实现时对照当时官方 / marketplace 正文，把落点换成 TeamPilot MCP）。必须覆盖中英口语：

> Install, import, create, update, or remove TeamPilot skills, plugins, and MCP servers. Use when the user wants to add, install, find, or import a skill, plugin, or MCP; search skills.sh or a marketplace; run npx or an install script; or mentions superpowers, context7, or community agent skills. Never write to ~/.claude/skills, .claude/skills, or ~/.claude.json — those paths are wiped on the next TeamPilot session start.

**正文结构**（与 Claude Code 安装 skill 相同：先搜再装；禁止私自改 Claude 目录）：

1. 先 `search_*`，对上再装，不要猜 git URL。
2. 远程源 / marketplace / `script_url` → `install_*`。
3. Agent 已经用 Bash/`npx`/脚本得到目录 → `import_*`。
4. 从零写 → `create_skill`；改文件 → `update_*`；只从本工作区拿掉 → `unbind_*`；从应用卸掉 → `delete_*`。
5. 成功后用返回的 `message` 告诉用户 **重连会话**。
6. 禁止：`git clone` 到 `~/.claude`、写 `.mcp.json` 当「已装进 TeamPilot」、`claude mcp add` 当完成态。

#### Prompt

`PromptContributionProvider`（managed，所有 CLI、simple 与 mixed）只追加一句，避免长 prompt 沉底：

> To install or manage TeamPilot skills, plugins, or MCP servers, load the `teampilot-catalog` skill and use the `teampilot` MCP. Do not install into ~/.claude.

### 10. 权限

| 类 | 工具 | 预授权 |
|---|---|---|
| 只读 | `search_*`、`list_installed`、`read_*` | 是（所有 CLI 的 allow 列表，类似 bus 但按 tool 名不是整 server） |
| 变异 | `install_*`、`import_*`、`create_*`、`update_*`、`unbind_*`、`delete_*` | 否 |

实现：`CatalogMcpPolicy.readToolNames` / `mutateToolNames` 由 registry 生成，launch 时写入各 CLI 的 allow。用户对变异 tool 点 Always 之后，与 Claude Code 批准 `git clone` 的体验相同。

## 数据流（安装 git skill）

```
install_skill({ repo, directory, bind_to: workspace })
  → SkillCatalogModule
  → SkillAcquisitionEngine.installGitDir / install(ref)
  → skills/installed/<dir> + manifest
  → WorkspaceProjectConfig.bundle.skillIds += id
  → CatalogMutationBus
  → { restart_required: true }
下次 connect
  → LayeredConfigBundle union
  → SkillCapability.materializeSkills（symlink 进 CONFIG_DIR）
```

导入 npx 目录：agent Bash 安装 → `import_skill({path})` → workFs 读 → home catalog copy → 同上 bind。

## 错误处理

- 模块抛 `CatalogException(code, message)`，MCP 层转 `isError` 文本，含 `code=` 前缀便于 skill 指导重试。
- `import` 部分成功（5 个 skill 导入 3 个）：`ok: false` 仍给 `ids` + `failed: [{path, code}]`，已成功的照样 bind。
- `script_url` 沿用 `SkillAcquisitionEngine` 的 HTTPS 校验；失败 `unsafe_script_url`。
- SSH 上 workFs 读失败：`not_found`（远端路径）不要说成本地缺失。

## 测试

- Kind registry：注册三个模块；`supportsCreate` 为 false 时 tools/list 无 `create_plugin`。
- Gateway：simple 无 TeamBus register 也能 `tools/list` catalog；缺 X-Session → 错误；mixed 同时存在 `/mcp` 与 `/catalog/mcp`。
- Skill install：git ref → manifest + workspace skillIds；已存在 → 只 bind。
- Import：临时目录含 `SKILL.md` → copy 进测试 `skills/installed`；沙箱外路径 → `unsafe_path`；无 SKILL.md → `no_skill_md`。
- MCP create：upsert + bind；read 不含 secret 值。
- Delete：库行消失且 workspace/team 引用被清（复用现有 uninstall 回调）。
- Provision：simple 与 mixed 的 extra MCP 都含 `teampilot`；managed skill artifact 出现在 skill materialize 的 desired 集合里。
- Policy：read tools 在 allow 列表；mutate tools 不在。
- 回归：`teammate-bus` mixed 行为不变。

## 文件落点（指导实现，非逐文件清单）

```
client/lib/services/catalog/
  catalog_kind.dart
  catalog_kind_registry.dart
  catalog_mutation_bus.dart
  catalog_mcp_handler.dart
  catalog_mcp_policy.dart
  catalog_mcp_transport.dart
  modules/skill_catalog_module.dart
  modules/plugin_catalog_module.dart
  modules/mcp_catalog_module.dart
  managed_skills/teampilot-catalog/SKILL.md
  providers/managed_catalog_skill_provider.dart
  providers/catalog_prompt_provider.dart
```

Gateway 路由改动放在现有 `teammate_bus/mcp/`（或抽出 `loopback/`）。Launch extra-server 装配只加 `teampilot` 条目，不复制一套 provision 管道。

## 以后怎么加 kind

1. 实现 `CatalogKindModule`。
2. `CatalogKindRegistry.register`。
3. 工具、权限、list/search 自动出现。
4. 若该 kind 也要进 session runtime，另接 2026-08-18 的 ContributionProvider（与本 MCP 无关）。

`bind_to` 扩展时：校验枚举，写入 `TeamProfile.bundle` 或 expert pack，不必改工具名。

热装：订阅 `CatalogMutationBus`，对当前 session 再跑一遍 `CliResourceProvisioner`；MCP 已有 `restart_required`，热装成功后可改为 `false` 而不改工具名。
