# 移动端消息交互：长按菜单与点击编辑 设计文档

日期：2026-11-11

## 目标

移动端（Android / iOS）聊天界面目前无法显示消息气泡下方的功能按钮，导致相应功能不可用。补充两个移动端手势交互，让这些功能重新可达，并提供移动端更好用的编辑入口：

1. **长按消息气泡** → 弹出功能菜单，包含桌面端按钮行里的同款功能。
2. **点击用户消息气泡** → 底部弹出「修改输入」编辑面板，聊天记录中其它消息压暗、被点气泡保持高亮（形态参考用户提供的移动端截图）。

桌面端（hover 显示按钮行 + 行内编辑器）行为完全不变。

## 需求（已与用户确认）

| 决策点 | 选择 |
|--------|------|
| 长按与系统「长按选字」的冲突 | **A**：移动端气泡内不再支持长按选字，长按整块气泡统一弹功能菜单；菜单的「复制」可复制整条消息 |
| 编辑入口形态 | **A**：底部独立「修改输入」面板（不改动现有输入框），复用现有 `onEditUserMessage` 重发分支 |
| 实现方案 | **方案 1**：全部在应用层实现，不动 vendored 包 `ai_message_ui` |
| 平台范围 | 仅 Android / iOS；桌面端不变 |
| 菜单功能范围 | 与桌面端按钮行一致：复制、导出 Markdown、编辑、从此 fork、重试、版本切换，按相同条件启用/禁用 |
| 菜单样式 | 复用项目现有 `TpActionMenu`（`showTpActionMenuFromSpecs`） |

两阶段落地，便于阶段一独立验证：

- **阶段一**：长按菜单（F1）
- **阶段二**：点击编辑 + 遮罩（F2）

## 现状

- 气泡下方按钮行是 `AiMessageActionBar`（`client/packages/ai_message_ui/lib/src/message_action_bar.dart:28`），动作包括重试、复制、编辑、fork、版本切换、导出 Markdown；包通过 `AiMessageStrings` 保持 l10n-free。
- `SessionHistoryThread.messageBuilder`（`client/lib/pages/chat/session_history_thread.dart:1300`）逐条构造 `AiMessageView`。对非最后一条消息传 `AiActionBarReveal.hover`（`session_history_thread.dart:1305`），靠 `MouseRegion.onEnter` 显隐。移动端无 hover，这些按钮一直是隐藏的（只剩固定高度的空白占位），功能点不到。
- 消息区整棵子树被 `SelectionArea` 包裹（`session_history_thread.dart:1195`），其 `SelectableRegion` 在 touch/stylus 上注册了 `LongPressGestureRecognizer`，长按文字会弹出文字选择工具栏（`buildTpSelectionAreaContextMenu`）。这是长按菜单必须处理的冲突。
- 现有编辑：`onEdit` → `_edit.openEditor(ai.id)` → `AiMessageView` 把用户气泡替换为行内编辑器 `_UserMessageEditor`（发送/取消）。提交链路在 `session_history_thread.dart:1331-1350`：`_edit.begin` → `widget.onEditUserMessage(ai.id, text)` → `_edit.finish`。
- `BranchEditController`（`client/lib/cubits/branch_edit_controller.dart`）由 `ChatCubit.branchEditFor(sessionId)` 持有，是 pending/draft/`editingMessageId` 的单一来源；`SessionHistoryRewindHost` 与 `SessionHistoryThread` 都监听它。
- `SessionChatView` 的 `Column` 里，消息区（`SessionChatMessageArea`）与底部输入框（`SessionChatComposeSection`）是兄弟；rewind 的编辑回调 `onEditUserMessage` 定义在消息区内的 `SessionHistoryRewindHost`，上层拿不到。
- `session_history_thread.dart` 已 1400+ 行，超过 `docs/CODE_QUALITY.md` 的单文件软上限；新增 UI 应拆文件。
- 已有测试 harness `client/test/pages/chat/session_history_thread_test.dart` 支持通过 `mobilePerformanceMode` 强制移动端路径。

## 方案（已确认）

### 文件清单

| 文件 | 改动 |
|------|------|
| `client/lib/pages/chat/chat_message_action_menu.dart` | 新增：`showChatMessageActionMenu(...)` |
| `client/lib/pages/chat/chat_message_edit_panel.dart` | 新增：`showChatMessageEditSheet(...)` + `_MobileMessageEditPanel` |
| `client/lib/pages/chat/session_history_thread.dart` | 改：手势包装、遮罩、抽出 `_submitEdit`、补缓存 key |
| `ai_message_ui` / `shared_ui` / `SessionChatComposeSection` / `SessionChatView` | **不动** |

`session_history_thread.dart` 已 import `ai_message_core`（`plainTextForCopy` / `markdownForExport`）、`ai_message_ui`、`shared_ui`、`l10n_extensions`，无需新增依赖。

不新增 l10n 键，复用：`copy`、`ai.messageExportMarkdown`、`ai.messageCopied`、`edit.userMessage`、`edit.cancel`、`edit.send`、`forkFromHere`、`session.historyRetry`、`branchPrevious`、`branchNext`。

### 平台门控

复用 `build()` 里已有的 `mobile = widget.mobilePerformanceMode ?? (Platform.isAndroid || Platform.isIOS)`（`session_history_thread.dart:1117`）。所有新增手势、遮罩、编辑面板都只在 `mobile == true` 时生效；`mobilePerformanceMode` 供测试注入。

### 阶段一：长按菜单

`messageBuilder` 中，仅对真实消息（跳过 running 占位、landing pending 气泡、system 消息），且 `mobile && _edit.editingMessageId == null` 时包装：

```
SelectionContainer.disabled
  └─ GestureDetector(behavior: HitTestBehavior.translucent,
       onLongPressStart: (d) => unawaited(showChatMessageActionMenu(..., d.globalPosition)))
       └─ result (AiMessageView + highlight ring)
```

- 手势竞技场按命中路径由深到浅注册识别器；我们的 `GestureDetector` 是 `SelectionArea` 的后代，先加入竞技场、先到 500ms deadline，稳定胜出。`SelectionContainer.disabled` 兜底，避免系统文字选择工具栏同时出现。
- `GestureDetector` 只提供 `onLongPressStart`（不注册 tap 识别器），消息内部链接/工具卡的点击不受影响。
- 菜单项顺序与 `AiMessageActionBar` 一致：

  | 项 | 图标 | 出现条件 | 启用条件 | 动作 |
  |----|------|----------|----------|------|
  | 重试 | `Icons.refresh_rounded` | `deliveryFailed` | 始终 | `widget.onRetryFailedMessage!(ai.id)` |
  | 复制 | `Icons.copy_rounded` | 始终 | `plainTextForCopy(ai).isNotEmpty` | `Clipboard.setData` + `AppToast`(`ai.messageCopied`) |
  | 编辑 | `Icons.edit_outlined` | 纯文本用户消息且可编辑 | `rewindEnabled` | `_openMobileEdit(ai)` |
  | 从此 fork | `Icons.call_split` | `onFork != null` | `rewindEnabled` | `widget.onForkFrom(version.commit)` |
  | 上一版本 / 下一版本 | `Icons.chevron_left/right` | `showsVersion` | `rewindEnabled` | `widget.onSwitchVersion(previous/next)` |
  | 导出 Markdown | `Icons.description_outlined` | 始终 | `markdownForExport(ai).isNotEmpty` | `Clipboard.setData` + `AppToast`(`ai.messageCopied`) |

  分组之间加 `TpActionMenuSpec.divider()`。

- `rewindEnabled = AiMessageInteractionScope.maybeRewindEnabled(context) ?? !widget.turnInFlight`，在**菜单打开时**读取，不闭包捕获 `turnInFlight`，避免虚拟列表缓存拿到旧值。
- `showChatMessageActionMenu` 用 `TpActionMenuSpec.item(onAction: …)` + `showTpActionMenuFromSpecs<void>(context:, globalPosition:, specs:)`；复制/导出写剪贴板后给轻量成功 toast。
- 菜单标签全部走 `context.l10n`；helper 保持无状态，不持有 widget 引用。

### 阶段二：点击编辑 + 遮罩

**触发**：仅 `ai.role == AiRole.user`、纯文本、`version != null`、`widget.onEditUserMessage != null` 且 `rewindEnabled` 时，给同一个 `GestureDetector` 加 `onTap: () => unawaited(_openMobileEdit(ai))`。长按与点击由两个识别器处理，长按胜出时 tap 被拒，不会误触。

三个编辑入口统一走 `_openMobileEdit(ai)`：点击气泡、长按菜单的「编辑」项、以及移动端可见的 action bar 编辑图标（`AiMessageView.onEdit` 在 mobile 下改为调用 `_openMobileEdit`）。

**流程**：

1. `_edit.openEditor(ai.id)` → 置 `editingMessageId`，驱动遮罩
2. `await showChatMessageEditSheet(...)`
3. 返回非 `true` 且 `_edit.editingMessageId == ai.id` → `_edit.cancelEdit()`

**面板**：`showModalBottomSheet<bool>`，`isScrollControlled: true`、`barrierColor: Colors.transparent`（barrier 仍拦截点击，遮罩由逐消息 `Opacity` 承担）；面板自身不透明背景覆盖底部输入框位置，因此**不需要**改 `SessionChatView` 去隐藏 composer。

`_MobileMessageEditPanel` 内容：

- 顶行：标题（`l10n.edit.userMessage`）+ 关闭 X
- 自动聚焦的多行 `TextField`，预填 `_edit.draft ?? plainTextForCopy(ai)`
- 底行：取消（`l10n.edit.cancel`）/ 发送（`l10n.edit.send`）
- 发送 → `await onSubmit(text.trim())`；成功 `Navigator.pop(context, true)`；失败保持面板并保留草稿
- X / 取消 / barrier / 下拉关闭 → `Navigator.pop(context, false)`
- 面板底部 `Padding` 取 `MediaQuery.viewInsetsOf(context).bottom`，保证键盘弹起时面板贴在键盘上方

**提交**：把现有 `session_history_thread.dart:1331-1350` 抽为 `Future<bool> _submitEdit(AiMessage message, String text)`，供桌面端 `AiMessageView.onSubmitEdit` 与移动端面板共用。逻辑不变：`_edit.begin(messageId, text, visibleMessageIds)` → `widget.onEditUserMessage(message.id, text)` → `_edit.finish(accepted, messageId)`。

**遮罩**：`messageBuilder` 中，当 `mobile && editingId != null && editingId != ai.id`，把该消息包成 `IgnorePointer(ignoring: true, child: Opacity(opacity: 0.28, child: result))`。被编辑的气泡保持全亮，其余消息（含 thinking、工具卡、状态横幅）压暗。标题栏等屏幕其它 chrome 不变，与截图一致。

**行内编辑器**：`AiMessageView.editing` 改为 `!mobile && _edit.editingMessageId == ai.id`。移动端只由底部面板承担编辑，避免同一条消息同时出现两个编辑框；桌面端保持原样。

## 边界情况与状态一致性

| 情况 | 行为 |
|------|------|
| 虚拟列表缓存 | `_bodyCacheKeyForTurn` 补入该 turn 各消息的 `pendingDeliveryStatuses[...]`（`FailedMessageStatus.name`），否则失败状态变化时缓存体会让「重试」项陈旧 |
| `turnInFlight` 变化 | 菜单打开时读 `AiMessageInteractionScope`，不进缓存 key |
| 编辑期间 | 禁用长按菜单与点击编辑（dim + `IgnorePointer`），避免重复触发 |
| 提交失败 | `_submitEdit` 返回 false，面板保持打开、`_edit.finish` 保留草稿（与现有行内编辑器一致） |
| 长时间未落地 | 沿用 `BranchEditController` 的 watchdog |
| 非纯文本 / 无 version / 无 `onEditUserMessage` | 不显示「编辑」项、不附加点按手势 |
| running 占位 / landing pending 气泡 / system 消息 | 不附加任何手势与遮罩 |
| 桌面端 | 不附加手势/遮罩/面板；hover 按钮行与行内编辑器照旧 |
| 键盘 | 面板 `isScrollControlled` + `viewInsets` padding；关闭时 `_edit.cancelEdit()` 复原遮罩 |

## 不做的事（YAGNI）

- 不动 `ai_message_ui` / `shared_ui` / composer / 桌面端交互。
- 不把 rewind 的编辑回调抬到 `SessionChatView`（用 bottom sheet 覆盖 composer 位置即可）。
- 不新增功能按钮（如「复制为 AI 上下文」）、不新增 l10n 键。
- 不做全局半透明 scrim（遮罩只作用于消息块，标题栏保持原样）。
- 不改 copy/export 的内容生成逻辑（沿用 `ai_message_core` 的 `plainTextForCopy` / `markdownForExport`）。

## 测试

1. `client/test/pages/chat/chat_message_action_menu_test.dart`（新增）：
   - 各菜单项在对应条件下出现/隐藏/禁用。
   - 各 `onAction` 回调被正确调用。
   - 复制 / 导出写入剪贴板（mock platform channel），success toast 文案正确。
2. `client/test/pages/chat/chat_message_edit_panel_test.dart`（新增）：
   - `TextField` 预填原文；发送成功返回 true 并关闭；发送失败保持打开且草稿不变。
   - 取消 / X 返回 false。
3. `client/test/pages/chat/session_history_thread_test.dart`（扩充，harness 已支持 `mobilePerformanceMode`）：
   - `mobilePerformanceMode: true` 下长按气泡弹出菜单。
   - `mobilePerformanceMode: true` 下点击用户气泡弹出编辑面板，且其它消息带 `Opacity`、被点消息不带。
   - `mobilePerformanceMode: false` 下不附加 `GestureDetector`（`SelectionContainer.disabled` 包装不存在）。
4. 完成前按 `AGENTS.md`：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`（全量在后台跑一次）。内环用 `flutter analyze` + 单文件 `--plain-name` 验证，外环全量一次。
