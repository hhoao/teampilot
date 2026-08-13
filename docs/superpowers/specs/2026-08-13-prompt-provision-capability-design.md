# PromptProvisionCapability：统一成员 prompt 注入 — 设计

Date: 2026-08-13
Status: Draft (brainstorming)

## 问题

五个 CLI 的"成员角色 prompt / 规则注入"没有统一架构。内容组合已共享（`MemberRoleProvision.composeRolePrompt`），但**写入目标与传输方式**每个 CLI 各写各的：

| CLI | 写入 | 传输 |
|---|---|---|
| claude / flashskyai | `syncRolePromptFile` → `{toolDir}/prompts/{slug}/role.md`（共享） | env `TEAMPILOT_APPEND_SYSTEM_PROMPT_FILE` → `--append-system-prompt-file` |
| codex | `config_profile.dart:189` **inline** `$CODEX_HOME/AGENTS.md` | AGENTS.md 自动发现 |
| opencode | `_writeMemberIdentity` **inline** `$CONFIG_DIR/AGENTS.md`（+ workspace dirs 章节） | AGENTS.md 自动发现 |
| cursor | `CursorRoleRuleWriter`（`cursor_home_provisioner.dart` 内部）→ `~/.cursor/rules/role.mdc` | .mdc 自动加载 |

后果：

1. **新内容层要改 N 处**：workspace 附加目录章节、未来安全规则、扩展规则——每加一层，claude/flashskyai/codex/opencode/cursor 的装配点各改一遍（opencode 章节是首个实例）。
2. **写入逻辑双份 inline**：codex 与 opencode 各有一份 `composeRolePrompt → atomicWrite AGENTS.md` 拷贝。
3. **双读**：claude/flashskyai 写完 role.md 后 `resolveAppendSystemPromptPath` 再读一次文件才拿路径。
4. **无 registry 可发现性**：装配点之间靠各 config_profile 自己拼，新 CLI 加入时无从知道"prompt 注入"是必须能力。

根因：**"prompt 内容"与"CLI 如何落地 prompt"耦合**，且没有 per-CLI 能力抽象。

## 架构

**每 CLI 一个 `PromptProvisionCapability` 实现（全权拥有：内容组合 + 写入 + 传输贡献）；装配点只调 `provision()` 并合并贡献。**

```
registry/capabilities/prompt_provision_capability.dart
  abstract interface class PromptProvisionCapability implements CliCapability
    Future<PromptProvisionContribution> provision(PromptProvisionContext ctx)

  class PromptProvisionContext {
    ConfigProfileDelegate paths
    LaunchProfileScope scope          // 实现自己算 sessionToolDir（claude mixed 用 slug 段）
    TeamMemberConfig? member
    bool forceTeamLeadDelegateMode
    bool mixed
    bool pushDelivery                // cursor 专用
    List<String> additionalDirectories  // 已 normalize 的工作面路径
    String? memberHome               // cursor 专用：fake HOME 由装配点解析后传入
  }

  class PromptProvisionContribution {
    Map<String, String> environment  // 传输 env（claude/flashskyai 的 append 键）
    bool written                     // 装配点借此并入 changed
  }
```

```
组合层（共享，MemberRoleProvision）
  composeRolePrompt(..., List<String> additionalDirectories = const [])
    → 非空时追加 "## Workspace directories" 章节（自 opencode config_profile 迁入）
  syncRolePromptFile(..., additionalDirectories)      // claude/flashskyai 用，参数透传
  CursorRoleRuleWriter.sync(..., additionalDirectories) // cursor 用，参数透传

每 CLI 实现（cli/{cli}/capabilities/prompt_provision.dart）
  ClaudePromptProvisionCapability / FlashskyaiPromptProvisionCapability
    syncRolePromptFile → contribution.environment{appendKey: path}，written=path!=null
  CodexPromptProvisionCapability
    composeRolePrompt → atomicWrite $CODEX_HOME/AGENTS.md
  OpencodePromptProvisionCapability
    composeRolePrompt(+dirs) → atomicWrite $CONFIG_DIR/AGENTS.md
  CursorPromptProvisionCapability（包装 CursorRoleRuleWriter）
    sync(memberHome, ..., +dirs) → frontmatter / 空删

装配点
  config_profile.contributeLaunch → promptProvision.provision(ctx)
    → environment 并入贡献 env；written 并入 changed
  cursor 特例：impl 注入 CursorHomeProvisioner（构造），_syncRoleRule 改为调 capability
    —— 保持 simple/mixed 两个路径的写入时机与 pushDelivery 语义原样
```

### 职责分区

| 单元 | 职责 | 依赖 |
|---|---|---|
| `PromptProvisionCapability`（接口） | 声明 per-CLI prompt 落地契约 | `CliCapability` |
| `PromptProvisionContext` / `Contribution` | 装配点 ↔ 实现的数据传递 | — |
| `MemberRoleProvision` | 内容层组合（role body + mode addenda + workspace dirs） | team 模型 |
| 各 CLI 实现 | 组合 + 写入目标 + 传输贡献 | 各自的 writer / home 约定 |
| 各 config_profile | 只做装配：调 provision、合并 env/written | capability 实例 |

### 数据流

```
contributeLaunch
  → promptProvision.provision(ctx)
      → MemberRoleProvision.composeRolePrompt(member, flags, additionalDirectories)
      → 写入 CLI 目标（role.md / AGENTS.md / role.mdc）
      → 返回 {environment, written}
  → config_profile 合并 environment 到贡献 env；written 并入 changed
```

### 关键决策

1. **能力全权拥有**（组合+写入+传输）：传输是 per-CLI 变体（env→flag vs 自动发现），属能力职责；装配点零 prompt 逻辑。
2. **`ConfigProfileDelegate.resolveAppendSystemPromptPath` 删除**：capability 写完直接返回路径，去掉双读。接口方法、service 转发、infrastructure 实现一并移除。
3. **addDirs → prompt 章节只 opencode 启用**：claude/codex/cursor 有 `--add-dir`/trust 让目录一等公民，章节是噪音；参数透传保留扩展点。
4. **`permission.external_directory` 合并留在 opencode config_profile**：那是配置不是 prompt，不进能力。
5. **cursor 落点在 home provisioner 内**：`_syncRoleRule` 与 dirs 就绪、bus overlay 的先后顺序是行为的一部分，能力注入 provisioner 保持时序不变。
6. 不做向下兼容。

## 改动清单

- 新增 `registry/capabilities/prompt_provision_capability.dart`（接口 + ctx + contribution）
- `MemberRoleProvision`：`composeRolePrompt` / `syncRolePromptFile` 加 `additionalDirectories`；`composeOpencodeWorkspaceDirectoriesPrompt` 迁入
- 新增 5 个 `cli/{cli}/capabilities/prompt_provision.dart`
- 5 个 config_profile：删 prompt 拼接，改为调 capability；cursor 的 home provisioner 注入 capability
- 5 个 tool definition：注册 `PromptProvisionCapability`（仿 `SkillInvocationSyntaxCapability`）
- 删除 `ConfigProfileDelegate.resolveAppendSystemPromptPath`（接口 + service + infrastructure）
- opencode config_profile：保留 `mergeOpencodeExternalDirectories`，删 `_writeMemberIdentity`/章节组合

## 测试

- registry wiring：五个 launch CLI 均暴露 `PromptProvisionCapability`（仿 `all_cli_effort_capability_test.dart` / skill 测试）
- 每 CLI 实现单测：
  - claude / flashskyai：role.md 写入 + env 贡献
  - codex / opencode：AGENTS.md 内容（opencode 含 dirs 章节）、空成员不写
  - cursor：frontmatter `alwaysApply: true`、空删、pushDelivery 透传
- 组合层：`composeRolePrompt` 的 dirs 章节（非空追加 / 空不追加 / 与 role body 拼接）
- 迁移后既有测试保持通过（`opencode_idle_plugin_test.dart`、`opencode_external_directories_test.dart` 断言不变，章节组合测试迁往组合层测试）

## 边界

- 能力只覆盖"常驻 prompt/规则注入"（role + 目录章节 + 未来规则层）；skill 是另一通道（`SkillInvocationSyntaxCapability`），不动
- 各 CLI 的 settings/config 写入（provider、mcp、permission）不进能力
- workspace dirs 章节文案沿用现实现（英文、绝对路径清单 + 用法提示）
