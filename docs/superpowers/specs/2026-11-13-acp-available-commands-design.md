# ACP 可用命令接入组合斜杠菜单 设计文档

日期：2026-11-13

## 目标

让 ACP 会话消费 agent 通过 `available_commands_update` 下发的命令列表，并把它作为该会话斜杠菜单的事实来源。ACP 会话在 agent 下发非空列表后，菜单显示 agent 声明的命令；未下发时回退到按 CLI 静态注册的 `NativeCommandCapability`。PTY 会话、landing（未绑定会话）compose 行为不变。

## 背景与已确认事实

- 协议层已经具备完整能力：`client/packages/acpd/packages/acpd/lib/src/schema/updates.dart:197-273` 定义了 `AvailableCommand {name, description, input?}` 与 `AvailableCommandsUpdate {availableCommands}`；`session_update.dart:15-59,182-202` 解析 `available_commands_update` 变体。无需改 wire schema。
- 应用层在 `client/lib/services/acp/acp_session.dart:1211` 的 `_mapUpdate` default 分支丢弃该更新，注释明确写着 "Available-commands, mode, and session-info updates have no chat-layer representation yet"。
- 模型选择器（`modelState`）是现成的端到端先例：
  - `AcpAgentSession` 内部状态 → `AcpModelStateUpdate`（`acp_session.dart:348,611-616`）
  - `AcpChatRuntimeState.modelState`（`client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart:123`）
  - `AcpRuntimeUiState`（`client/lib/pages/chat/acp_runtime_scope.dart:14-40`）
  - `SessionChatComposeSection` 消费（`client/lib/pages/chat/session_chat_compose_section.dart:208`）
- 斜杠菜单当前完全静态：`SessionChatComposeSection:237-239` 从 `CliToolRegistry` 读取 `NativeCommandCapability.commands`，作为普通 prop 传给 `WorkspaceComposeCard` → `ComposeTriggerField`；没有任何运行时状态或 notifier。
- `NativeCommand` 的描述是 4 个本地化枚举值（`client/lib/services/cli/registry/capabilities/native_command_capability.dart:3-16`），无法承载 agent 下发的任意英文描述。
- 存量缺陷：Grok 的静态命令名自带 `/`（`client/lib/services/cli/grok/capabilities/native_commands.dart`），而 `NativeCommand.insertText` 会再拼一个 `/`，实际插入 `//compact`。`compose_slash_catalog.dart:76-89` 也直接用 `command.name` 作 label。
- ACP 命令名按规范不带 `/`，但实现可能有偏差；同一套归一化应覆盖静态和动态两个来源。

## 协议依据

- `available_commands_update` 是 `session/update` 的一个通知变体（agent → client），客户端应整体替换命令列表，不做增量。
- `AvailableCommand.name` 是裸名（如 `create_plan`），`description` 为人类可读文本，`input.hint` 为参数提示（可选）。
- 没有独立的“执行命令”RPC：用户选择后仍以普通文本 `session/prompt` 发送，命令名后输入的所有文本作为参数。
- 协议没有 `initialize` 能力开关，agent 可随时重发。

## 已确认的决策

1. **完全替换**：ACP 会话以 agent 下发的列表为唯一事实来源；静态表仅在 agent 尚未下发非空列表时兜底；PTY 会话继续使用静态表。
2. **空列表忽略**：空数组视为“agent 尚未就绪”，不覆盖当前菜单；只有非空列表才生效。
3. **状态落点**：复用 `modelState` 链路（cubit state → `AcpRuntimeScope` → compose），不新增旁路接口。
4. **顺带修复 Grok 双斜杠**：在 `NativeCommand` 层归一化，不改 Grok 数据。

## 非目标

- 不实现客户端本地命令（如 `/clear`），不做 `startsWith('/')` 拦截。
- 不改命令的提交语义：仍作为 `session/prompt` 文本发送。
- 不做命令列表持久化；重新连接时由新 cubit 从空状态开始，等待 agent 重新下发。
- 不处理其余未映射的 `session/update` 变体（`current_mode_update`、`session_info_update`）。
- 不改菜单的 20 条上限与命令配额策略。

## 架构与数据流

```
acpd.AvailableCommandsSessionUpdate
  └─ AcpAgentSession._onSessionUpdate（绕过 bootstrap 抑制）
       └─ _mapUpdate → AcpAvailableCommandsUpdate(List<AcpAvailableCommand>)
            └─ AcpChatRuntimeCubit._onUpdate
                 └─ AcpChatRuntimeState.availableCommands（List<NativeCommand>）
                      └─ AcpRuntimeUiState.availableCommands
                           └─ SessionChatComposeSection
                                └─ nativeCommands = 动态非空 ? 动态 : 静态注册表
                                     └─ buildComposeSlashCandidates（现有逻辑）
```

### 1. 内部类型与映射（`services/acp/acp_session.dart`）

新增两个类型，紧邻 `AcpModelState`：

```dart
final class AcpAvailableCommand {
  const AcpAvailableCommand({
    required this.name,
    required this.description,
    this.inputHint,
  });

  final String name;
  final String description;
  final String? inputHint;
}

final class AcpAvailableCommandsUpdate extends AcpSessionUpdate {
  const AcpAvailableCommandsUpdate(this.commands);

  final List<AcpAvailableCommand> commands;
}
```

`_mapUpdate` 新增分支（放在 default 之前）：

```dart
case acpd.AvailableCommandsSessionUpdate():
  final commands = <AcpAvailableCommand>[];
  for (final command in update.availableCommands) {
    final name = command.name.trim();
    if (name.isEmpty) continue;
    final hint = command.input?.hint.trim();
    commands.add(
      AcpAvailableCommand(
        name: _stripSlash(name),
        description: command.description.trim(),
        inputHint: (hint == null || hint.isEmpty) ? null : hint,
      ),
    );
  }
  return commands.isEmpty ? null : AcpAvailableCommandsUpdate(commands);
```

`_stripSlash` 去掉一个前导 `/`（`/compact` → `compact`）。

### 2. Bootstrap 抑制旁路

`_onSessionUpdate:935` 目前在解析前就丢弃 load/resume 期间的全部更新。命令列表属于会话元数据而非 transcript；agent 可能只在 `session/new` / `session/load` 期间发一次，若被抑制将永远丢失。

修改为：对该变体放行，且收集历史时不进 `_historyBuffer`。

```dart
final collecting = _collectingHistory;
if (_suppressBootstrap && !collecting && !_isAvailableCommandsUpdate(params)) {
  return;
}
```

`_isAvailableCommandsUpdate` 只检查 raw map 的 `update.sessionUpdate == 'available_commands_update'`。

映射成功后：

```dart
final mapped = _mapUpdate(update);
if (mapped == null) return;
if (collecting && mapped is! AcpAvailableCommandsUpdate) {
  _historyBuffer?.add(mapped);
  return;
}
_emit(mapped);
```

`available_commands_update` 始终走 `_emit`：cubit 是常驻订阅者，与当前是否在收集历史无关。

### 3. 命令模型（`services/cli/registry/capabilities/native_command_capability.dart`）

```dart
final class NativeCommand {
  const NativeCommand({
    required this.name,
    this.description,
    this.descriptionText,
    this.argumentHint,
    this.availability = NativeCommandAvailability.stable,
  });

  final String name;
  final NativeCommandDescription? description; // 静态命令使用
  final String? descriptionText;               // agent 原文，优先展示
  final String? argumentHint;
  final NativeCommandAvailability availability;

  String get slashName =>
      name.startsWith('/') ? name.substring(1) : name;

  bool get acceptsArgument => argumentHint != null;

  String get insertText => acceptsArgument ? '/$slashName ' : '/$slashName';
}
```

- 现有静态命令全部继续传 `description`，调用点无需改动。
- Grok 的 `/compact` 经 `slashName` 归一化后插入 `/compact`，不再产生 `//compact`。
- `description` 由必填改为可空是源兼容变更；两个字段均为空时菜单只显示来源标签。

### 4. Catalog（`services/chat/conversation/compose/compose_slash_catalog.dart`）

- `ComposeSlashCandidate` 增加 `String? descriptionText`。
- 原生命令分支：

```dart
for (final command in nativeCommands) {
  final name = command.slashName.trim();
  if (name.isEmpty) continue;
  add(
    ComposeSlashCandidate(
      insertText: command.insertText,
      label: name,
      kind: ComposeSlashCandidateKind.command,
      source: ComposeSlashCandidateSource.native,
      description: command.description,
      descriptionText: command.descriptionText,
      availability: command.availability,
      insertionSuffix: '',
    ),
  );
}
```

- `add` 的查询过滤同时匹配 `descriptionText`：

```dart
final searchable = [
  candidate.description?.searchTerms,
  candidate.descriptionText,
].whereType<String>().join(' ').toLowerCase();
```

### 5. Cubit（`cubits/session/acp/acp_chat_runtime_cubit.dart`）

- `AcpChatRuntimeState` 新增 `List<NativeCommand> availableCommands`，默认 `const []`，纳入 `copyWith`。
- `_onUpdate` 新增：

```dart
case AcpAvailableCommandsUpdate():
  if (update.commands.isEmpty) break;
  emit(state.copyWith(
    availableCommands: [
      for (final command in update.commands)
        NativeCommand(
          name: command.name,
          descriptionText:
              command.description.isEmpty ? null : command.description,
          argumentHint: command.inputHint,
        ),
    ],
  ));
```

- `start()` 进入 `ready` 时初始 state 为空（新 cubit），无需显式清理；若同一 cubit 被重新 `start()`，在启动处显式 `availableCommands: const []`，避免显示上一次连接的命令。
- 与 `modelState` 一致：命令更新不属于 turn 内容，取消/失败后保留。

### 6. UI 投影与消费

`AcpRuntimeUiState` 增加 `availableCommands`，纳入 `of`、`==`、`hashCode`；`AcpRuntimeScope` 的 equality gate 保证只在命令真正变化时重建。

`SessionChatComposeSection.build`：

```dart
final agentCommands = acpRuntime == null
    ? const <NativeCommand>[]
    : (acpUi?.availableCommands ?? const <NativeCommand>[]);
final nativeCommands = agentCommands.isNotEmpty
    ? agentCommands
    : registry.capability<NativeCommandCapability>(lockedCli)?.commands ??
          const <NativeCommand>[];
```

混合会话无需额外处理：`acpRuntime` 由 `_acpRuntimeForSelectedSeat` 按当前选中成员解析，命令随座位切换。landing/unbound compose 没有 ACP runtime，继续走静态表。

`ComposeTriggerField._commandDetails` 优先展示 `descriptionText`，为空时才回退 `description.localized(context)`。

## 边界与错误处理

- **条目清洗**：`name.trim()` 为空丢弃；`description.trim()` 为空按无描述处理；`input` 缺失则无参数提示、插入不带尾随空格。
- **重复名**：catalog 的 `seen` 按 `insertText` 去重，先到先得；agent 列表内部重复同样被吸收。命令与 skill 同名时沿用同一既有规则。
- **整表替换**：每条非空更新都是完整列表，最后一次生效。
- **turn 取消**：`_isTurnContentUpdate` 不包含该更新，取消后命令列表保留。
- **列表过长**：菜单仍是 20 条上限 + 命令固定配额，agent 下发大量命令时按现有排序截断。
- **无 l10n**：agent 描述按英文原文展示，不新增翻译键；为空时只显示来源标签。
- **安全**：命令仍以纯文本进入 `session/prompt`，不新增本地执行路径。
- **畸形帧**：`SessionUpdateNotification.fromJson` 解析失败沿用现有 malformed 日志与丢弃路径。

## 测试

| 层 | 文件 | 用例 |
|---|---|---|
| 映射 | `test/services/acp/acp_session_test.dart` | 字段完整映射；空列表不 emit；load/resume bootstrap 期间仍收到；空名条目跳过；前导 `/` 被去除 |
| cubit | `test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart` | 更新写入 state 并完成类型转换；空列表不改 state；重新 start 后清空 |
| 投影/组件 | `test/pages/chat/session_chat_view_acp_test.dart`、`test/widgets/compose/compose_trigger_field_test.dart` | 动态命令替换静态表；无动态时回退；座位切换跟随对应 runtime；`descriptionText` 展示与搜索 |
| 模型 | `test/services/cli/registry/native_command_capability_test.dart` | `name: '/compact'` 时 `slashName == 'compact'`、`insertText == '/compact'` |
| catalog | `test/services/chat/conversation/compose/compose_slash_catalog_test.dart` | label 不带 `/`；`descriptionText` 参与过滤 |

## 验证

```bash
cd client && flutter analyze
cd client && dart run tool/run_tests.dart \
  test/services/acp/acp_session_test.dart \
  test/cubits/chat/acp/acp_chat_runtime_cubit_test.dart \
  test/pages/chat/session_chat_view_acp_test.dart \
  test/widgets/compose/compose_trigger_field_test.dart \
  test/services/cli/registry/native_command_capability_test.dart \
  test/services/chat/conversation/compose/compose_slash_catalog_test.dart
```

不跑全量；若最终改动跨 ACP 映射与 UI 两层，交付前按 `docs/DEVELOPMENT.md` 的变更→验证表决定是否需要全量。

## 风险与兼容性

- **抑制旁路**是唯一改变既有管道语义的改动，影响面限定在 `available_commands_update` 一个变体；其余 load/resume 更新仍被抑制。
- **`NativeCommand.description` 可空化**会触及所有读取该字段的代码；仓库内消费点只有 catalog 与 `_commandDetails`，均在本设计内更新。
- **agent 下发英文描述**导致菜单语言混排；这是按 A 方案完全替换的预期结果。
- **命令名归一化**只去一个前导 `/`，不改变大小写、不去空格以外的字符。

## 改动清单

- `client/lib/services/acp/acp_session.dart`
- `client/lib/services/acp/acp_frame_logger.dart`（把命令帧从“纯噪声”注释中移除；可选）
- `client/lib/cubits/session/acp/acp_chat_runtime_cubit.dart`
- `client/lib/pages/chat/acp_runtime_scope.dart`
- `client/lib/pages/chat/session_chat_compose_section.dart`
- `client/lib/services/cli/registry/capabilities/native_command_capability.dart`
- `client/lib/services/chat/conversation/compose/compose_slash_catalog.dart`
- `client/lib/widgets/compose/compose_trigger_field.dart`
- 对应测试文件（上表）
