# CLI 能力接口合并:按功能组收敛 — 设计

Date: 2026-08-14
Status: Done

## 问题

`client/lib/services/cli/registry/capabilities/` 现有 **46 个能力接口**,大量是单方法/单布尔的小接口,每个只有 1-3 处消费。开发者接入新 CLI 时面对一堆孤儿接口,不知道哪些是必须实现的、它们之间是什么关系。同时 `ConfigProfileCapability` 是"模糊的巨型编排器"——5 个实现各有一份 300~1100 行的相同编排(解析 provider → 装 home → 渲染 hooks → 凭证桥 → prompt → 返回 env),职责没有按功能域归属。

## 概念:Hub 功能 + 虚拟实例 + 物化

**Hub 功能** = 主窗口可见的功能库(Skills / Plugins / MCP / Hooks / Providers 页面)。每个 Hub 功能都要对接所有 5 个 CLI,因此**每个 CLI 为每个 Hub 注册一个能力实现**;该能力是"物化器契约"——Registry 查询时返回**虚拟实例**(纯数据声明,零 IO),Session 启动前统一**物化**成该 CLI 的原生配置。

```
共享注册器(领域服务)                每 CLI 能力契约(物化器)
  Plugin 服务 ──收集虚拟实例──▶  PluginCapability.provision()
  MCP 快照服务 ──McpServerSpec──▶  McpCapability.write()
  Hook 服务   ──HookEntry──────▶  HookCapability.render()
  Prompt 源   ──PromptSpec─────▶  PromptCapability.materialize()
  会话流程     ──provider 选择──▶  ProviderCapability.materializeSessionHome()
```

原则:**能力接口 = 物化器契约(声明式)**;**注册器 = 共享领域服务(收集虚拟实例 + 编排)**;**启动时统一物化**。虚拟实例是纯数据,可跨 CLI 共享(McpServerSpec/HookEntry/Plugin 已是),可缓存、可预览、可跨机传输(SSH:传虚拟实例 + 远端物化)。

三个作用域沿用同一模式(本次只落地 CLI 级,workspace/member 级作为扩展,见下文"范围外"):

| 作用域 | 注册器 | 内容来源 |
|---|---|---|
| CLI 级 | `CliToolRegistry` | 工具定义声明的能力 |
| 工作区级(后续) | Workspace 资源绑定 | `project-config.json` 的 skills/plugins/mcp/hooks |
| 成员级(后续) | Member 配置 | `TeamMemberConfig`(agent 预设、成员 MCP、effort) |

## 目标:46 → 14 个接口

### Hub 功能契约(每 CLI 一个实现)

| 接口 | 吸收的旧接口 | 新增 |
|---|---|---|
| `ProviderCapability` | ProviderCatalog, ProviderForm, ProviderModel(+Refreshable/Catalog 基类), ProviderDisplay, ProviderCredential, CredentialBinding, CredentialExport, CliEffort | `materializeSessionHome(ctx) → SessionHomeContribution(environment, warnings)`(来自 ConfigProfileCapability.contributeLaunch 的 provider/凭证/home 材料化部分) |
| `SkillCapability` | ResourceCapability(skill 部分), SkillInvocationSyntaxCapability | — |
| `PluginCapability` | PluginProvisioner, MarketplaceConsumer, RemoteAppData | — |
| `McpCapability` | McpConfigWriter | — |
| `HookCapability` | HookWriter | managed hooks(busIdle/agentStatus)编排从 5 个 config_profile 实现提取为共享流程 |
| `PromptCapability` | PromptProvision(2026-08-13 设计升级) | 多源虚拟实例收集 + 物化(见下) |

### 基础设施(非 Hub,保留领域名)

| 接口 | 吸收的旧接口 |
|---|---|
| `CliSessionCapability` | CliSessionLifecycle, PostManifestFlush, LaunchArgs, CliConfigLayout |
| `TeamBehaviorCapability` | NativeTeam, BusTransport, TurnCompletion, WaitBeforeStop, Presence, MemberAgentPreset |
| `ChatInteractionCapability` | AgentStatusNormalizer, AskUserQuestion, ExitPlanMode |
| `TerminalBehaviorCapability` | TerminalBehavior(原), TurnInterrupt, TitleAttention |
| `HeadlessCapability` | HeadlessProvision, HeadlessRun |
| `AiHistoryCapability` | AiHistory(原), AiTranscriptIncremental, HistoryContextEnv, SessionResume, ToolCallResolvers |
| `CliExecutableCapability` | Display, ExecutableResolver, RemoteCliLocator, Installer, CliConfigUi |
| `MemberConfigInspectionCapability` | **(保持不动)** |

### 解散:`ConfigProfileCapability`

`ensureSessionProfile` / `contributeLaunch` 的职责按功能域分配:

| 原职责 | 归属 |
|---|---|
| provider 解析 + home 装配(auth.json/config.toml/settings.json/llm_config/metadata 脚手架) | `ProviderCapability.materializeSessionHome` |
| managed hooks(busIdle/agentStatus)+ 用户 hooks 渲染 + 脚本落盘 | `HookCapability`(共享 managed-hooks 装配流程) |
| 跨机凭证桥(CrossMachineCredentialBridge) | `ProviderCapability`(凭证部分) |
| prompt 注入 | `PromptCapability`(物化器角色) |
| workspace trust | `CliSessionCapability` 会话流程(共享工具,已是) |
| 最终 env 贡献(CODEX_HOME 等) | `CliSessionCapability` — 由子能力结果汇总 |

会话编排流程(`config_profile_service.dart` / `session_bootstrap_coordinator.dart`)保留为共享服务,调用各子能力、按序执行、汇总 env/warnings。claude 的 config_profile.dart(1100 行)随之拆解为 provider / hook / prompt 三块。

## `PromptCapability`:多源 prompt 虚拟实例

Prompt 是**独立的第 6 个 Hub 契约**(升级 2026-08-13 的 PromptProvisionCapability,不再并入 CliSessionCapability)。核心区别:prompt 的**源**不只有"CLI 写成员角色 prompt"——很多功能都能提供 prompt,且未来用户需要自定义 prompt。

```
PromptSpec (虚拟实例, 纯数据)
  id/slug, 名称
  content (markdown)
  scope: cli / member / team / expert / workspace / global
  合并角色: 替换 / 追加 / 章节(如 "Workspace directories")

PromptCapability (一个接口, 双角色, 类似 SkillCapability)
  // 源角色: 声明我提供哪些 prompt 虚拟实例 (纯函数, 无 IO)
  List<PromptSpec> virtualize(PromptVirtualizeContext ctx);

  // 物化器角色: 把收集合并后的 PromptSpec 列表写入 CLI 原生位置
  Future<PromptMaterializeResult> materialize(PromptMaterializeContext ctx);
  // 非 CLI 的源(team/expert/workspace/user)默认 no-op materialize
```

**多源收集流程**(会话启动前):

```
各作用域的注册器扫描 PromptCapability 实现
  ├─ CLI 定义(每 CLI 的 prompt 物化器 + 成员角色 prompt)
  ├─ TeamHub 模板(团队 prompt)
  ├─ Expert 能力包(persona prompt)
  ├─ Workspace 绑定(未来用户自定义, 全 Workspace / 单 Workspace)
  └─ 其他功能(export 等)
        ↓ 收集 List<PromptSpec>
    按 scope 优先级合并: team > expert > workspace > user > CLI 默认
        ↓
    每 CLI 的 PromptCapability.materialize() 写入原生格式
      claude: prompts/{slug}/role.md + env
      codex/opencode: AGENTS.md
      cursor: ~/.cursor/rules/role.mdc
```

`CliSessionCapability` 只负责收集编排(遍历各作用域 virtualize + 合并 + 调物化),不持有 prompt 语义。

## 文件组织

- 接口文件:每个新接口一个 `registry/capabilities/<name>.dart`(纯接口 + 共享枚举/纯函数可同文件)
- 每 CLI 实现:按领域收敛——`cli/{cli}/capabilities/provider.dart`、`skill.dart`、`plugin.dart`、`mcp.dart`、`hook.dart`、`prompt.dart`、`session.dart`、`team_behavior.dart`、`chat_interaction.dart`、`terminal_behavior.dart`、`headless.dart`、`ai_history.dart`、`executable.dart`(不再每能力一个孤儿文件)
- 共享实现(ClaudeFamilyAgentStatusNormalizer、SharedToolCallResolvers、Default* 等)留在 registry 共享基础设施

## 测试策略

- **纯重构,零行为变更**:不引入新功能,只改名/换注册点/收敛文件
- `flutter analyze --no-fatal-infos --no-fatal-warnings` 全仓抓漏改(类型系统保证所有消费点同步)
- 每个合并一组小提交,便于 review 与回滚
- 更新测试中 `implements XxxCapability` 桩与 `capability<T>()` 类型参数;跑 `flutter test --exclude-tags integration`
- 消费点测试(703 个 CLI 测试)是行为回归基线

## 实施顺序(建议)

1. 简单吸收组(无行为变化):TerminalBehavior、TeamBehavior、ChatInteraction、Headless、CliExecutable、AiHistory
2. Hub 组:Skill、Plugin、Mcp、Hook、Prompt(含 PromptSpec 虚拟实例 + 多源收集)
3. ProviderCapability(8→1 + materializeSessionHome 迁移)
4. CliSessionCapability + ConfigProfile 解散(最大改动,claude 1100 行文件拆解)

## 风险

- `ProviderCapability` 与 `CliSessionCapability` 是最胖的两个接口,消费方多,分步实施
- ConfigProfile 解散涉及 5 个 CLI 的编排逻辑迁移,managed-hooks 流程去重要保证顺序与 warning 语义一致
- 测试桩同步量较大,但类型系统兜底

## 范围外(后续)

- workspace / member 作用域的注册器落地(本文档定义模式,CLI 级先行;PromptCapability 的多源收集预留 team/expert/workspace/user 源,接口先行、源后续逐个接入)
- `MemberConfigInspectionCapability` 保持不动(已是 default + 覆盖模式);其默认实现改从 `SkillCapability` / `PluginCapability` 读取布局声明(原 `ResourceCapability.subdirFor` 随 ResourceCapability 拆分而迁移,行为不变)
- 2026-08-13 的 `PromptProvisionCapability` 设计被本设计**升级取代**为 `PromptCapability`(保留其写入语义,新增 virtualize 源契约)
