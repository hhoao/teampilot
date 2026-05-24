# RTK（Rust Token Killer）集成设计方案

- 日期：2026-05-24
- 作者：hhoao + AI
- 状态：草案，待评审
- 参考：[rtk-ai/rtk](https://github.com/rtk-ai/rtk) · [hooks/claude/rtk-rewrite.sh](https://github.com/rtk-ai/rtk/blob/develop/hooks/claude/rtk-rewrite.sh)

## 1. 背景与目标

[RTK](https://github.com/rtk-ai/rtk) 是独立 Rust CLI，在 AI Agent 执行常见开发命令（`git status`、`cargo test`、`rg` 等）时压缩输出，宣称可节省 **60–90%** 的 LLM token。集成机制是 **PreToolUse Hook**：将 Bash 工具输入中的 `git status` 透明改写为 `rtk git status`，由 `rtk rewrite` 决策是否改写。

TeamPilot 通过 PTY 启动 `flashskyai` / `claude` / `codex`，并为每个成员隔离 `CONFIG_DIR`（`FLASHSKYAI_CONFIG_DIR`、`CLAUDE_CONFIG_DIR`）。`ConfigProfileService` 在每次会话启动时 **重新生成** `settings.json`。因此：

- 用户在本机执行 `rtk init -g` **不会** 自动作用于 TeamPilot 会话（路径为 `~/.claude`，且会被覆盖）。
- 必须在 TeamPilot 侧 **显式** 注入 hook，并与现有 provider settings、plugin hooks **合并**，而非覆盖。

**核心目标**：

1. 可选启用 RTK：设置页开关，默认关闭（YAGNI + 避免未安装时误导）。
2. 对 `flashskyai` 与 `claude` 成员级 `settings.json` 合并 RTK `PreToolUse` hook，不破坏已有 hooks。
3. 在成员 `CONFIG_DIR/hooks/` 部署 `rtk-rewrite.sh`，命令指向该路径（不依赖 `~/.claude`）。
4. 启动前检测 `rtk`、`jq` 可用性，通过 `LaunchPlan.warnings`  surfaced 到 UI。
5. **不** 在 v1 捆绑 RTK 二进制；仅检测 PATH 并引导用户安装。

**非目标（v1）**：

- 不集成 `rtk gain` 统计面板。
- 不修改 Agent 内置 `Read` / `Grep` / `Glob`（RTK 官方亦说明仅 Bash 工具可走 hook）。
- 不对 `codex` 做完整 hook（Codex 为 prompt 级集成；可留 Phase 3）。
- 不向 RTK 上游提交 `--agent teampilot`（可用 Claude Code 兼容 hook 格式）。

## 2. 架构总览

```
┌─────────────────────────────────────────────────────────────┐
│ UI Layer                                                    │
│  ConfigSettingsHubPage → RTK 区块（开关 / 状态 / 安装说明）   │
│       │                                                     │
│       └─ AppSettingsRepository (rtkEnabled)                 │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ Service Layer                                               │
│  RtkDetector              which rtk, --version, jq          │
│  RtkHookProvisioner       部署 hooks + 生成 settings 片段   │
│  ConfigProfileService     写 settings 时 merge RTK hook     │
│  SessionLifecycleService  prepareLaunch → warnings           │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│ Storage / Runtime                                           │
│  <teampilotRoot>/vendor/rtk/rtk-rewrite.sh  ← 随应用分发脚本 │
│  config-profiles/teams/.../members/.../flashskyai|claude/   │
│    hooks/rtk-rewrite.sh          ← 每成员拷贝（可执行）       │
│    settings.json                 ← 含合并后的 PreToolUse      │
│  PTY env: PATH 含 rtk 所在目录                                │
└─────────────────────────────────────────────────────────────┘
```

**数据流（会话启动）**：

```
用户启用 RTK
  → prepareLaunch()
  → ConfigProfileService.prepareTeamLaunchEnvironment()
  → RtkHookProvisioner.provision(memberToolDir)  // 若启用且 rtk 可用
  → _writeFlashskyaiSettings / _writeClaude*Settings
  → merge hooks.PreToolUse（保留 provider / plugin 已有项）
  → PTY 启动 CLI；Agent Bash 调用触发 hook → rtk rewrite → 压缩输出
```

## 3. 方案对比与选型

| 方案 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **A. Settings 合并 + 分发 hook 脚本（推荐）** | TeamPilot 拷贝 `rtk-rewrite.sh` 到成员 `hooks/`，在生成的 `settings.json` 中 merge `PreToolUse` | 与隔离 CONFIG_DIR 一致；不依赖 `rtk init`；可测 | 需维护脚本版本与 RTK 上游同步 |
| **B. 启动时调用 `rtk init`** | 对每个 `CONFIG_DIR` 执行 RTK 安装器 | 少维护 hook JSON | RTK 是否支持自定义 CONFIG_DIR 未保证；可能与写 settings 竞态 |
| **C. 仅文档 / PATH alias** | 用户自行安装，PTY 里 alias | 零开发 | Agent Bash 不走 alias；settings 仍被覆盖 |

**选定：方案 A。** 与 Plugin 管理的「TeamPilot 自维护投影目录」模式一致，且可单元测试 merge 逻辑。

## 4. RTK Hook 契约

### 4.1 settings.json 片段

与 [RTK Claude Code 集成](https://github.com/rtk-ai/rtk/blob/develop/hooks/README.md) 一致：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash \"/path/to/config-profiles/.../hooks/rtk-rewrite.sh\""
          }
        ]
      }
    ]
  }
}
```

`command` 必须使用 **成员目录内** 的绝对路径（`hooks/rtk-rewrite.sh`），避免依赖 `~/.claude/hooks/`。

### 4.2 Hook 脚本来源

- 将 RTK 仓库 `hooks/claude/rtk-rewrite.sh`（Apache-2.0）复制到 `client/assets/rtk/rtk-rewrite.sh`（或 `client/tool/rtk/`），构建时作为 asset 打包。
- `RtkHookProvisioner` 在 provision 时写入 `memberToolDir/hooks/rtk-rewrite.sh` 并 `chmod +x`（非 Windows；Windows 见 §8）。

### 4.3 合并规则

`RtkSettingsMerge.mergeHooks(base, rtkFragment)`：

1. 若 `base['hooks']` 不存在，设为 `rtkFragment['hooks']`。
2. 若已存在 `PreToolUse` 数组：
   - 若已有 matcher 为 `Bash` 且 command 含 `rtk-rewrite`，**跳过**（幂等）。
   - 否则 **prepend** RTK 条目（RTK 先执行，再交给其他 hook）。
3. 保留其他 event（`PostToolUse` 等）与其他 matcher 不变。
4. Provider 导入的 settings 在 `_claudeTeamSettings` 合并后再应用 RTK merge。

### 4.4 依赖

| 依赖 | 用途 | 缺失时行为 |
|------|------|------------|
| `rtk` ≥ 0.23.0 | `rtk rewrite` | 不注入 hook；warning `rtk_not_found` |
| `jq` | hook 解析 JSON | 不注入 hook；warning `rtk_jq_missing` |

## 5. 组件设计

### 5.1 `RtkDetector`

```dart
class RtkProbeResult {
  final bool found;
  final String? executablePath;  // resolved which rtk
  final String? version;         // e.g. 0.41.0
  final bool jqFound;
}

class RtkDetector {
  Future<RtkProbeResult> probe({Map<String, String>? environment});
  bool isVersionSupported(String version); // >= 0.23.0
}
```

实现：`Process.run(Platform.isWindows ? 'where' : 'which', ['rtk'])` + `rtk --version`；`which jq` / `where jq`。

### 5.2 `RtkHookProvisioner`

```dart
class RtkHookProvisioner {
  Future<void> provisionMemberToolDir(
    String memberToolDir, {
    required String hookScriptAssetPath,
    required Filesystem fs,
  });

  Map<String, Object?> rtkSettingsFragment(String hookScriptAbsolutePath);

  Map<String, Object?> mergeIntoSettings(Map<String, Object?> settings);
}
```

`provisionMemberToolDir`：创建 `hooks/`，写入脚本，返回 hook 绝对路径供 fragment 使用。

### 5.3 `ConfigProfileService` 变更

- 构造函数注入 `RtkHookProvisioner?`、`Future<bool> Function()? isRtkEnabled`（或从 `AppSettingsRepository` 读取的回调）。
- `_writeFlashskyaiSettings`、`_writeClaudeSettings`、`_writeClaudeMemberProfile` 在写入前：
  1. `probe()` RTK；
  2. 若 enabled && probe.ok → `provision` + `mergeIntoSettings`；
  3. 否则写原 settings（不加 RTK）。

### 5.4 `AppSettingsRepository` 扩展

```dart
Future<bool> loadRtkEnabled();           // default false
Future<void> saveRtkEnabled(bool value);
Future<String?> loadRtkPathOverride(); // optional; v1 可省略，仅预留
```

### 5.5 `SessionLifecycleService` / `LaunchPlan.warnings`

新增 warning 码（与现有 `claude_credentials_missing` 并列）：

| Code | 含义 |
|------|------|
| `rtk_enabled_not_found` | 用户开启 RTK 但 PATH 无 rtk |
| `rtk_enabled_jq_missing` | 开启但无 jq |
| `rtk_enabled_version_too_old` | rtk < 0.23.0 |

UI：在会话启动 toast 或设置页状态区展示（复用现有 warnings 管道，若无 UI 则 v1 仅日志）。

### 5.6 PTY 环境

`LaunchCommandBuilder.launchEnvironmentForProcess` 或 `buildPtyEnvironment`：当 RTK 启用且探测到 `executablePath` 时，确保其目录在 `PATH` 前部（通常已在 PATH，属防御性措施）。

## 6. UI 设计

在 `ConfigSettingsHubPage` → `_LayoutSettingsScroll` 内新增 **`_RtkSettingsSection`**（位于 Appearance 之前或之后）：

| 元素 | 行为 |
|------|------|
| 开关 | 绑定 `rtkEnabled` |
| 状态行 | `rtk 0.41.0 ✓` / `未安装` / `需要 jq` |
| 说明文案 | 链接 https://github.com/rtk-ai/rtk#installation |
| 限制提示 | 仅作用于 Agent **Bash** 工具；不影响终端手打命令 |

i18n：`app_en.arb` / `app_zh.arb` 增加 4–6 条字符串。

## 7. 平台与 CLI 范围

| 平台 | flashskyai / claude hook | 说明 |
|------|--------------------------|------|
| Linux | ✓ | 完整 |
| macOS | ✓ | 完整 |
| Windows WSL | ✓ | PTY 走 WSL 时与 Linux 相同 |
| Windows 原生 | △ | 无 bash hook；v1 显示「仅 WSL 支持自动改写」，不注入 hook |

| CLI | v1 | 说明 |
|-----|-----|------|
| `flashskyai` | ✓ | Claude Code 兼容 settings |
| `claude` | ✓ | 含 member `--settings` 文件 |
| `codex` | ✗ | Phase 3：可选写入 `AGENTS.md` RTK 指引 |

## 8. 安全与隐私

- RTK 可选遥测（GDPR opt-in）：TeamPilot **不** 代为启用；文档中提示用户自行 `rtk telemetry status`。
- Hook 脚本来自上游固定版本，升级时需审查 diff。
- `rtk rewrite` 不将命令参数发往 TeamPilot；仅本地子进程。

## 9. 测试策略

| 层级 | 内容 |
|------|------|
| 单元 | `RtkSettingsMerge` 合并/幂等；`RtkDetector` mock Process |
| 单元 | `RtkHookProvisioner` 写文件 + fragment 路径 |
| 单元 | `ConfigProfileService` 启用 RTK 时 settings 含 PreToolUse |
| 集成 | 可选：fake `rtk` 脚本在 PATH，启动会话后读 settings.json |

不依赖真实 RTK 二进制跑 CI。

## 10. 分阶段交付

| 阶段 | 交付物 |
|------|--------|
| **Phase 1** | `RtkDetector`、`RtkHookProvisioner`、`RtkSettingsMerge`、`ConfigProfileService` 集成、单元测试 |
| **Phase 2** | `AppSettingsRepository` + 设置 UI + warnings + l10n |
| **Phase 3（可选）** | Codex AGENTS.md；`rtk gain` 只读展示；向 RTK 提 PR `--agent teampilot` |

## 11. 风险与缓解

| 风险 | 缓解 |
|------|------|
| TeamPilot 覆盖用户手工加的 RTK hook | merge 而非 replace；幂等检测 |
| Plugin 自带 PreToolUse 冲突 | prepend RTK；文档说明顺序 |
| RTK 脚本与二进制版本漂移 | asset 标注 `# rtk-hook-version: N`；发布说明要求 rtk ≥ 0.23 |
| 用户以为 Read/Grep 也会压缩 | UI 明确仅 Bash |
| Windows 原生无 hook | 平台检测 + 禁用开关或降级文案 |

## 12. 成功标准

1. 开启 RTK 且本机已安装 `rtk`+`jq` 时，成员 `settings.json` 含正确 `PreToolUse` 且 `hooks/rtk-rewrite.sh` 存在。
2. 关闭 RTK 时，生成 settings **不含** RTK hook（与现行为一致）。
3. Provider 自带 hooks 在 merge 后仍保留。
4. `flutter test` 全通过，无新增 integration 硬依赖。

---

**评审后下一步**：按 [`docs/superpowers/plans/2026-05-24-rtk-integration.md`](../plans/2026-05-24-rtk-integration.md) 实施。
