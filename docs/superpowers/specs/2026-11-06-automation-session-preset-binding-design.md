# 绑定会话的定时任务：预设与会话 CLI 对齐 + 切换/解绑会话

## 背景

「启动提示词 + 复用会话」类型的定时任务把选中的 CLI 预设存在
`Automation.presetId`（`models/automation.dart:152`）。编辑器里用的是
`CliPresetDropdownField`，它把**所有 CLI 的全局预设**都列出来
（`widgets/cli/cli_preset_dropdown_field.dart:50`），因此可以自由地跨 CLI 切换。

但会话一旦创建，CLI 就固定了：`SimpleLaunchIdentity.resolve` 用 `preset.cli`
定下会话的 CLI（`models/simple_launch_identity.dart:47`），会话内切换预设时
`session_chat_compose_section.dart:234` 只用 `presetsForCli(presets, lockedCli)`
列出同一 CLI 的预设。而派发时，一旦 `reuseSession` 绑定了会话，
`AutomationDispatcher._resolveOrCreateSession` 直接复用旧会话
（`services/automation/automation_dispatcher.dart:259`），新选的 `presetId`
根本不生效。结果就是「任务能随便切预设、实际绑定的会话只能用一个 CLI 的预设」，
跨 CLI 切换是无效且误导的。

此外，当前绑定信息只是「复用会话」开关下的一行副标题
（`automationsReuseSessionSubtitleBound`，显示裸 `sessionId`），没有任何
切换/解绑入口；用户想把任务挪到另一个会话、或让下次运行换一个会话重新开始，
都做不到。

## 目标

- 已绑定会话时，预设下拉**只列出该会话 CLI 的预设**，并标明当前 CLI，
  不允许跨 CLI 乱选，让配置与会话能力一致。
- 提供「切换会话」：从工作区现有会话里另选一个重新绑定
  （只列与任务身份兼容的会话）。
- 提供「解绑」：清空绑定但**保持「复用会话」开启**，下次运行新建会话并
  重新绑定（相当于重置）。预设下拉随绑定态变化。
- 想换 CLI 时，走「解绑/切换」让下次按新预设新建会话，形成自洽的操作路径。

## 非目标

- 不改 `Automation` 模型 / 序列化、`AutomationRepository`、`AutomationCubit`、
  `AutomationDispatcher`，不碰 `scheduledMessage` 编辑器。
- 不引入带搜索的会话选择器（保持轻量选择弹层）。
- **不实现「切换预设即同步运行中会话」**：绑定期间切换同 CLI 预设不会去改
  运行中会话的 provider/model（那要接 `session_preset_follow_sync`，列为后续）。
  预设值只用于保证配置合法，并在解绑后作为下次新建会话的启动身份。
- 本次只对齐预设。其他仅在新建会话时生效的字段
  （`projectFolderPath` / `workingDirectoryPath` / `expertKey`）在绑定态下的
  展示不处理；`teamId` / `targetMemberId` 在绑定态下仍参与派发，保持不变。
- 不加兼容层 / 特性开关。

## 关键前提：后端零改动

现有 dispatcher 已天然支持两种语义，无需任何修改：

- **解绑** = `sessionId == null` 且 `reuseSession == true`。
  `_resolveOrCreateSession`（`automation_dispatcher.dart:259`）找不到会话 →
  `_createSessionForLaunchPrompt`（`:267`）按当前 `presetId` 新建 →
  `applyAfterSuccessfulDispatch`（`:473`）重新写回 `sessionId`。
- **切换** = `sessionId` 指向另一已存在会话。
  `_resolveSession`（`:246`）用 `automation.matchesSession(session)` 校验通过后复用。
  personal 模式要求 `session.isSimple`，与候选过滤规则一致。

因此改动全部集中在「自动化服务层纯函数 + 编辑器 UI」。

## 行为

### 1. 预设约束（方案 A）

- 仅作用于 `isPersonal`（simple）模式的启动提示词；team 模式没有预设选择器
  （`presetId` 为 null），无需过滤，也不显示 CLI 约束。
- `CliPresetDropdownField` 新增可选 `CliTool? cliFilter`。非 null 时内部用
  `presetsForCli(presets, cliFilter)` 过滤，`_resolveInitialId` 基于过滤后的列表；
  过滤后为空时显示空态提示。
- 预设字段增加 `description` 提示「已绑定会话，仅显示该会话 CLI 的预设」。
- 绑定会话行显示 `CliBrandIcon` 徽标 + CLI 文字（`cli.value`）标明当前 CLI。

### 2. 切换 / 解绑会话（语义 1）

- 「绑定会话」行仅在 `kind == launchPrompt && reuseSession == true` 时显示：
  会话名（`sessionListDisplayTitle`）+ CLI 徽标（simple 模式）+「切换会话」
  +「解绑」。
- **切换**：打开轻量选择弹层，列出可绑定会话；选中后写本地 `_boundSessionId`。
- **解绑**：清空本地 `_boundSessionId`，`reuseSession` 保持不变。
- 关闭「复用会话」开关时同步清空 `_boundSessionId`（与
  `stripWhenReuseDisabled` 语义一致）；重新开启时保持空（pending，首次运行后绑定）。
- 切换会话时若当前 `presetId` 为空、或其预设的 CLI 与新会话 CLI 不同，自动改选
  `presetsForCli(presets, newCli).firstOrNull?.id`；该 CLI 无预设则保留原值，
  交给保存校验报错。

### 3. 保存

- `AutomationEditorDialog._save` 把 `_boundSessionId` 写入 `Automation.sessionId`
  （替换原 `widget.initial?.sessionId` 的 launchPrompt 分支）；`reuseSession` 不被解绑改变。
  构造完成后仍调用现有 `stripWhenReuseDisabled`（关 reuse 时兜底清绑定）。
- 保存前一致性校验：`_boundSessionId != null` 且 `isPersonal` 时，
  `presetId` 对应预设的 `cli` 必须等于绑定会话的 `cli`，否则
  `form.setFieldError('presetId', ...)` 拦截（覆盖历史脏数据）。
  绑定会话不在 `state.sessions` 时跳过该校验（无法解析 CLI），交由派发阶段兜底。

## 组件与文件清单

绑定态的「切换 / 解绑」是纯编辑器本地状态，落盘时直接写 `Automation.sessionId`
即可，无需新增 `rebindTo` / `unbind` 之类的策略方法（`Automation.copyWith` 已覆盖），
也不改动 `automation_launch_session_binding.dart`。

| 文件 | 改动 |
|---|---|
| `services/automation/automation_session_binding_resolver.dart`（新） | 纯函数，入参为调用方已按 workspace 过滤好的 `sessions`：`findBoundSession(String? sessionId, List<AppSession> sessions)`；`bindingCliFilter(AppSession? bound)` → simple 返回 `bound.cli ?? CliTool.claude`，team / null 返回 null；`bindableSessionsFor({required Automation automation, required List<AppSession> sessions})` → `activeSessions` + `purpose == SessionPurpose.normal` + `automation.matchesSession`（已含 workspace 校验）+ `sortAppSessions(sort: recentlyUpdated)` |
| `widgets/cli/cli_preset_dropdown_field.dart` | 加 `CliTool? cliFilter`，用 `presetsForCli` 过滤；空态提示；`_resolveInitialId` 基于过滤后列表 |
| `pages/automations/automation_editor_launch_section.dart` | 透传 `cliFilter`；预设字段加 `description` |
| `pages/automations/automation_editor_form_body.dart` | 「复用会话」下加「绑定会话」行：会话名 + CLI 徽标 +「切换会话」「解绑」；接收 `boundSession` / `boundCli` / `onSwitchSession` / `onUnbindSession` |
| `pages/automations/automation_session_picker.dart`（新） | `showAutomationSessionPicker({context, sessions, selectedId})` → `Future<String?>`；`showTpDialog` 列表（`sessionListDisplayTitle` + `CliBrandIcon` + 选中态）+ 空态 |
| `pages/automations/automation_editor_dialog.dart` | 本地 `late String? _boundSessionId`（初值 `initial?.sessionId`，仅 launchPrompt）；从 `ChatCubit.state.sessions` 解析 bound / cli / 候选；切换、解绑、reuse 开关联动；`_save` 用 `_boundSessionId` + preset/CLI 一致性校验 |

## 数据流

```
编辑态  ChatCubit.state.sessions
          └─ resolver → boundSession / bindingCliFilter / bindableSessions
                          └─ cliFilter 下传 → 预设下拉按 CLI 过滤
        切换/解绑 → 仅改本地 _boundSessionId（不落盘）

保存    _boundSessionId → Automation.sessionId
        （reuseSession 不变；关 reuse 开关时清空 boundSessionId）

派发    sessionId 为空 → 按 presetId 新建会话并重绑
        sessionId 非空 → matchesSession 校验通过后复用
        （现有 dispatcher 逻辑，无改动）
```

## 边界与错误处理

- 绑定会话不在 `state.sessions`（归档 / 删除 / 未加载）：绑定行显示
  「不可用，请切换或解绑」，**不拦截保存** —— dispatcher 的 `_resolveSession`
  会回退 `loadSessionsForWorkspace`，最坏情况自动新建并重绑，安全。
- 绑定会话 CLI 与 `presetId` 预设 CLI 不一致（含历史数据）：保存前拦截并报错。
- 目标 CLI 无任何预设：下拉显示空态（`automationsPresetEmptyForCli`）；此时
  `presetId` 仍指向旧 CLI，保存被一致性校验拦下（`automationsPresetCliMismatch`），
  提示先建该 CLI 预设、或改选会话 / 解绑。若 `presetId` 本就为空，则由
  `validate()` 拦下。
- 候选为空：picker 显示空态；「切换会话」仍可点开看到提示。
- team 模式：无预设选择器 → 不过滤、不显示 CLI 徽标约束；切换 / 解绑照常可用。

## 测试

- 新 `test/services/automation/automation_session_binding_resolver_test.dart`：
  候选过滤（跨 workspace / archived / `teamGeneration` / team 不匹配 / simple 命中）、
  `bindingCliFilter`、`findBoundSession`。
- `test/pages/automations/automation_editor_dialog_test.dart`：注入两个不同 CLI 的
  preset + `ChatCubit.state.sessions` 带 simple 会话，覆盖：
  绑定时下拉只含该 CLI 预设；解绑后 `sessionId == null && reuseSession == true`；
  切换后 `sessionId` 与 `presetId` 对齐新 CLI；CLI 不一致时保存被拦；
  team 模式可切换 / 解绑。
- 遵循 `AGENTS.md`：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
  + `dart run tool/run_tests.dart <paths>`；不直接调用 `flutter test`。

## l10n

只改 `lib/l10n/app_en.arb` / `app_zh.arb`（约 10 条，无 placeholder）：
`automationsBoundSession`、`automationsBoundSessionPending`、
`automationsBoundSessionUnavailable`、`automationsSwitchSession`、
`automationsUnbindSession`、`automationsSessionPickerTitle`、
`automationsSessionPickerEmpty`、`automationsPresetScopeHint`、
`automationsPresetCliMismatch`、`automationsPresetEmptyForCli`。
CLI 名直接用 `cli.value` 显示，不进 l10n。改完运行 l10n 生成。
