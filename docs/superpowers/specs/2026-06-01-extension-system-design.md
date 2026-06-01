# 扩展系统（Extension System）设计

状态：已评审通过，待写实现计划
日期：2026-06-01
相关：[multi-agent-bus-roadmap.md](../../multi-agent-bus-roadmap.md)

## 1. 背景与目标

TeamPilot 当前已有四套"扩展类"机制，彼此部分重叠，且 **rtk 是硬编码集成的**：

| 现有机制 | 代码位置 |
|---------|---------|
| MCP 服务器 | `mcp_repository.dart`、`services/mcp/team_mcp_linker_service.dart`、`config/mcp_presets.dart` |
| Hook / settings 合并 | `services/team/rtk_settings_merge.dart`、`services/host/script_file_hook_provisioner.dart` |
| Plugins / Skills | `services/plugin/`、`services/skill/` 两套 linker |
| 主机二进制探测 | `services/team/rtk_detector.dart` → `services/host/host_execution_environment.dart` |

每接入一个外部工具就要手写一份 bespoke Dart service（rtk 就是 `rtk_detector.dart` + `rtk_settings_merge.dart` + `config_profile_service` 里的 `_maybeApplyRtk`/`_collectRtkWarnings`）。

**目标**：建立一个统一的"描述 + 引擎"层，把"获取/探测一个外部工具 + 用一种或多种方式接进 agent CLI 的 config-profile"这件事**声明式化**。验证标的为两个参考扩展：

- **codegraph**（<https://github.com/colbymchenry/codegraph>）：TypeScript/Node，语义代码索引，以 stdio **MCP server**（`codegraph serve --mcp`）暴露给 agent。
- **rtk**（<https://github.com/rtk-ai/rtk>）：Rust 单二进制，token 压缩代理，以 **Claude-Code `PreToolUse` hook** 透明改写 Bash 命令。

成功标准：codegraph 与 rtk 都**完全经由新系统**端到端跑通（安装 → 探测 → 落地 → agent 生效），rtk 的全部 bespoke 代码被通用引擎吸收；新增第三个扩展在常见情况下**只需写一份 manifest JSON，零 Dart 代码**。

## 2. 范围决策

| 维度 | 决定 |
|------|------|
| 抽象层级 | **声明式 manifest 为主 + 有类型 Dart effect applier 逃生舱** |
| 获取方式 | **一键安装 + 配置**（系统能代跑安装） |
| 启用层级 | **全局默认 + 可按 team 覆盖**（镜像现有 app→team→member 继承） |
| 目标 CLI | **claude + flashskyai**（两个 `isLaunchSupported` 主力，共用 Claude 兼容配置 flavor） |
| 运行环境 | **桌面优先（本地 PTY + WSL）保证一键装；探测跨全传输（含 SSH/Android），但远程不保证一键装** |

## 3. 非目标（YAGNI / v1 范围外）

- SSH / Android 远程主机的一键安装（远程只做探测 + 配置 + 引导用户自己装）。
- codex / opencode 的配置 flavor 映射。
- 常驻进程型扩展（需 TeamPilot 管生命周期 / 健康检查 / OAuth）——保留 `dart:` 逃生舱接口，但 v1 不实现具体 applier（两个参考扩展都不需要）。
- 远程 marketplace 扩展目录——v1 只内置 codegraph + rtk 两份 manifest。

## 4. 架构总览

扩展系统**不是第五个并列子系统**，而是一个坐在现有子系统之上的"描述 + 引擎"层，复用 MCP linker、settings-merge、host 探测、CLI installer：

```
                    Extension Manifest (声明式)
                    ├── acquire   (怎么把底层工具装到主机)
                    ├── detect    (怎么验证它在 & 可用，跨传输)
                    └── effects[] (怎么接进 agent CLI 的 config-profile)
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
  AcquisitionEngine     DetectionEngine       EffectApplier registry
  (复用 cli_installer)  (复用 HostExec…)       ├─ mcp-server   → 喂给 TeamMcpLinkerService 的 servers.json
                                              ├─ settings-hook → 泛化现 RtkSettingsMerge
                                              ├─ env           → 注入启动环境
                                              └─ dart:<id>     → 有类型逃生舱(罕见: 进程生命周期/OAuth)
                              │
                              ▼
        apply 点 = ConfigProfileService.prepareTeamLaunch
        (现在 _maybeApplyRtk / 团队 MCP 落地的同一处)
```

## 5. 数据模型

### 5.1 Extension manifest

新扩展主要就写这份数据。两份内置 manifest 以 bundled asset 放 `extensions/catalog/`。

```jsonc
// codegraph
{
  "id": "codegraph", "name": "CodeGraph", "version": "1.x",
  "homepage": "https://github.com/colbymchenry/codegraph",
  "acquire": { "kind": "node-package", "package": "@colbymchenry/codegraph",
               "binary": "codegraph", "allowNpx": true },
  "detect":  { "executable": "codegraph", "versionArgs": ["--version"],
               "minVersion": null, "requires": [] },
  "effects": [
    { "kind": "mcp-server", "appliesTo": ["claude", "flashskyai"],
      "name": "codegraph", "server": { "command": "codegraph", "args": ["serve", "--mcp"] } }
  ]
}
```

```jsonc
// rtk —— 现 rtk_detector + rtk_settings_merge 两份手写代码压成这一份数据
{
  "id": "rtk", "name": "RTK (Rust Token Killer)", "version": "0.x",
  "homepage": "https://github.com/rtk-ai/rtk",
  "acquire": { "kind": "cargo", "package": "rtk", "binary": "rtk",
               "alternatives": ["brew:rtk", "script:https://…/install.sh"] },
  "detect":  { "executable": "rtk", "versionArgs": ["--version"],
               "minVersion": "0.23.0", "requires": ["jq"] },
  "effects": [
    { "kind": "settings-hook", "appliesTo": ["claude", "flashskyai"],
      "event": "PreToolUse", "matcher": "Bash",
      "scriptAsset": "rtk-rewrite", "marker": "rtk-rewrite" }
  ]
}
```

字段约定：

- `acquire.kind` ∈ `node-package | cargo | brew | script | none`；`allowNpx`（仅 node-package）为真时可不全局安装、在 mcp command 内用 `npx`。`alternatives` 是按序兜底的安装方式（`"<kind>:<arg>"`）。
- `detect.requires[]` 是伴生二进制（rtk → `jq`）；`minVersion` 为 `null` 表示不校验。
- `effects[].appliesTo` 限定生效的 CLI；`kind` 决定由哪个 applier 处理。

### 5.2 v1 effect kind（前 3 内置覆盖两扩展，第 4 为逃生舱）

| kind | 落地方式 | 幂等键 | 谁用 |
|------|---------|--------|------|
| `mcp-server` | 产出一个 `McpServer`（`server` 即 `{command,args,env…}` map），并入团队 `config-profiles/teams/{teamId}/mcp/servers.json`（复用 `TeamMcpLinkerService`），与用户手选 MCP 并排 | `McpServer.configKey`（= name） | codegraph |
| `settings-hook` | 复用 `script_file_hook_provisioner` 写 hook 脚本到 member tool dir + `SettingsHookMerge`（由 `RtkSettingsMerge` 泛化）并入 member settings.json | `marker` 字符串 | rtk |
| `env` | 返回 env map，并入启动环境（两扩展暂不用，先留） | env key | — |
| `dart:<capabilityId>` | 委派给注册的有类型 applier，处理 exotic 逻辑（常驻进程、OAuth）。**v1 不实现具体 applier** | applier 自定 | — |

### 5.3 启用与安装状态 `state.json`

```jsonc
// {teampilotRoot}/extensions/state.json
{
  "installed":      { "rtk": {"version":"0.24.1"}, "codegraph": {"version":"1.4.0"} },
  "globalEnabled":  ["rtk"],                              // app 级默认开
  "teamOverrides":  { "team-abc": { "codegraph": true, "rtk": false } }
}
```

解析规则（镜像 app→team 继承）：

```
effective(team, ext) = teamOverrides[team][ext] ?? globalEnabled.contains(ext)
```

## 6. 三个引擎

### 6.1 AcquisitionEngine（获取）

复用 `services/cli/cli_installer_service.dart` 与 installer registry。`acquire.kind → 安装策略` 是一张数据驱动映射表，新增包管理器=加一行：

| kind | 动作 |
|------|------|
| `node-package` | `npm i -g <pkg>`；`allowNpx` 时跳过全局装、改在 MCP command 用 `npx <pkg>` |
| `cargo` | `cargo install <pkg>` |
| `brew` | `brew install <pkg>` |
| `script` | 执行安装脚本 |
| `none` | 不装，纯探测 |

仅在本地 PTY + WSL 保证安装；SSH/Android 跳过安装、走"引导用户自己装"，探测照常。`alternatives` 按序兜底。

### 6.2 DetectionEngine（探测）

把现有 `RtkDetector` 泛化为通用 `ExtensionDetector`（参数化 rtk_detector 现有逻辑）：

- 复用 `HostExecutionEnvironment` / `HostExecutableLocator` 跨传输 `which(detect.executable)`；
- 跑 `versionArgs` 解析版本并与 `minVersion` 比较；
- 逐个检查 `requires[]` 伴生二进制；
- 产出 `ExtensionProbe { found, executablePath, version, satisfiesMinVersion, missingRequires }`。

`RtkDetector` / `RtkProbeResult` 整个被取代（rtk 的 `0.23` 版本逻辑变成 manifest 的 `minVersion`，`jq` 变成 `requires`）。沿用 rtk_detector 的 `ProcessRunner` 注入与 `FLUTTER_TEST` 跳过模式以便测试。

### 6.3 EffectApplier registry（落地）

新增 `ExtensionProvisioner`，在 `ConfigProfileService.prepareTeamLaunch`（现 `_maybeApplyRtk` + 团队 MCP 落地处）接管。member 启动时：

1. 解析"本 team + 本 tool 启用了哪些扩展"（§5.3）。
2. 对每个启用扩展跑 DetectionEngine——未就绪则**跳过 + 收集 warning**（沿用现 `rtkWarningEnabled*` 体验）。
3. 按 `effect.kind` 分发给 applier registry：
   - `mcp-server` applier 贡献的 `McpServer` 条目，**并入** `TeamMcpLinkerService.syncForTeam` 写出的 `mcp/servers.json`（与用户手选条目并排，`configKey` 去重，扩展条目优先/幂等）。
   - `settings-hook` applier 复用 `script_file_hook_provisioner` 写脚本 + `SettingsHookMerge`（按 `marker` 幂等）。
   - `env` applier 返回 env map 并入启动环境。

`_maybeApplyRtk` / `_collectRtkWarnings` / `RtkSettingsMerge` / `RtkDetector` 这四处 bespoke 逻辑全部被引擎吸收。

## 7. 状态管理

新增 `ExtensionRepository`（读写 `extensions/state.json` 与 `extensions/catalog/`）+ `ExtensionCubit`，与 MCP/plugin 的 repo+cubit 同构，挂进 `app_shell.dart` 的 DI。

## 8. 两个参考扩展端到端

### codegraph

```
Extensions 页点「安装」
  → AcquisitionEngine(node-package): npm i -g @colbymchenry/codegraph (本地/WSL)
  → DetectionEngine: which codegraph → codegraph --version → installed["codegraph"]={version}
全局或某 team 开启
  → prepareTeamLaunch: effective==true 且 probe.found
       → mcp-server applier 把 {command:"codegraph",args:["serve","--mcp"]}
         以 configKey "codegraph" 并入 teams/{teamId}/mcp/servers.json
  → claude/flashskyai 启动时自行以 stdio 拉起 codegraph serve --mcp（TeamPilot 不管进程）
```

### rtk

```
Extensions 页点「安装」
  → AcquisitionEngine(cargo): cargo install rtk（失败按 alternatives 试 brew/script）
  → DetectionEngine: which rtk + which jq + 版本≥0.23.0
全局开启（默认即开，迁移自老开关）
  → prepareTeamLaunch: probe.isReady 否则收 warning（沿用现文案）
       → settings-hook applier: provision rtk-rewrite 脚本到 member tool dir
         + SettingsHookMerge 注入 PreToolUse/Bash hook（marker 幂等）
  → claude/flashskyai 每条 Bash 命令被 rtk 透明改写
```

两条链路落到的文件、幂等 marker、跨传输探测与今天 rtk 行为一致，仅驱动来源从手写 Dart 变为 manifest。

## 9. 管理 UI 与路由

- 新增全局页 `/extensions`（`pages/extension_management_page.dart`，仿 `mcp_management_page.dart`）：列出 catalog、显示安装状态与探测状态（codegraph 版本、rtk 的 jq+版本告警）、安装/卸载、全局开关。**把 `config_workspace.dart` 现有 rtk 探测块迁移到此页**。
- 按 team 覆盖：`team_config_page.dart`（`/team-config/*`）加 "Extensions" 小节，每扩展三态：跟随全局 / 强制开 / 强制关 → 写 `teamOverrides`。
- `app_router.dart` 注册 `/extensions`（桌面侧栏 + Android drawer）。

## 10. 迁移与清理

- 删除 `services/team/rtk_detector.dart`、`services/team/rtk_settings_merge.dart`；移除 `config_profile_service.dart` 的 `_maybeApplyRtk` / `_collectRtkWarnings` / rtk 字段，改调通用 `ExtensionProvisioner`。
- `config_workspace.dart`（约 L371 的 `RtkDetector().probe()`）的 rtk 探测 UI 迁到 Extensions 页。
- 老 rtk 开关值 → `state.json.globalEnabled:["rtk"]`，老用户无感。
- l10n 复用现有 `rtkWarning*` 键，新增 key 只改 `client/lib/l10n/app_en.arb` + `app_zh.arb`。

## 11. 测试策略

- 单元：manifest 解析/校验；`ExtensionDetector`（注入 `ProcessRunner`，沿用 rtk_detector fake 模式）；各 effect applier（mcp 合并去重 / settings-hook marker 幂等 / env）；`effective()` 解析；`state.json` round-trip。
- 集成（`@Tags(['integration'])`，`package:test`）：跑一次 `prepareTeamLaunch`，断言 `servers.json` 含 codegraph 条目、member `settings.json` 含 rtk hook。
- 门禁：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`。

## 12. 新增 / 改动文件清单（预估）

新增：

- `client/lib/models/extension_manifest.dart`（manifest + effect 模型）
- `client/lib/models/extension_state.dart`（installed / enabled 状态）
- `client/lib/services/extension/extension_detector.dart`
- `client/lib/services/extension/extension_acquisition_engine.dart`
- `client/lib/services/extension/effect/effect_applier.dart`（registry + 接口）
- `client/lib/services/extension/effect/mcp_server_effect_applier.dart`
- `client/lib/services/extension/effect/settings_hook_effect_applier.dart`（含泛化后的 `SettingsHookMerge`）
- `client/lib/services/extension/effect/env_effect_applier.dart`
- `client/lib/services/extension/extension_provisioner.dart`
- `client/lib/repositories/extension_repository.dart`
- `client/lib/cubits/extension_cubit.dart`
- `client/lib/pages/extension_management_page.dart`
- `client/assets/extensions/catalog/codegraph.json`、`rtk.json`

改动：

- `client/lib/services/provider/config_profile_service.dart`（替换 rtk 逻辑为 `ExtensionProvisioner`）
- `client/lib/services/mcp/team_mcp_linker_service.dart`（接受扩展贡献的 MCP 条目并并入）
- `client/lib/app/app_shell.dart`（DI）、`client/lib/router/app_router.dart`（路由）、`client/lib/pages/team_config_page.dart`（team 覆盖）、`client/lib/pages/config_workspace.dart`（迁出 rtk 块）
- `client/lib/l10n/app_en.arb`、`app_zh.arb`

删除：

- `client/lib/services/team/rtk_detector.dart`、`client/lib/services/team/rtk_settings_merge.dart`

## 13. 风险与开放问题

- **MCP 合并接口**：`TeamMcpLinkerService.syncForTeam` 目前只吃 `List<McpServer> catalog` + `mcpServerIds`。需扩成可额外接收"扩展贡献的 McpServer 列表"，或由 `ExtensionProvisioner` 在其写出后做二次合并——实现计划阶段二选一（倾向前者，单写入点更稳）。
- **安装权限/网络**：cargo/npm 安装耗时且可能失败；UI 需异步进度 + 失败回退到 `alternatives` + 明确报错。
- **flashskyai hook flavor**：确认 flashskyai 消费 Claude-Code 格式 settings.json hook（现 `_maybeApplyRtk` 已对 member tool dir 通用应用，推断成立；实现前以一次真机/集成验证兜底）。
