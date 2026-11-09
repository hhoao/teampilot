# 聊天消息时间戳显示 设计文档

日期：2026-11-09

## 目标

在会话聊天界面中，让用户消息和 AI 回复都能查看发送时间。时间跟随现有的消息工具条（hover 时出现），不增加常驻界面元素。

## 需求（已与用户确认）

1. **范围**：用户消息气泡和 AI 回复块都显示时间。
2. **显隐方式**：时间随现有工具条一起 hover 显示，复用工具条的 hover-reveal 行为（固定高度、180ms unmount 延迟等），不常驻。
3. **格式**：智能格式 —— 今天的消息只显示 `15:44`；非今天显示 `11月6日 15:44`（英文 locale 下日期部分为 `Nov 6`）。跨年不需要特殊处理（仍显示 `M月d日 HH:mm`）。

## 现状

- `AiMessage`（`ai_message_core`）已有 `createdAt: DateTime?`；各 CLI 历史转录（Claude `compatible_jsonl.dart`、Codex、Cursor `ai_transcript.dart`）解析时已填充该字段，数据现成。
- 用户气泡渲染在 `ai_message_ui` 包 `_UserBubble`（`ai_message_view.dart`），下方是 dense 模式的 `AiMessageActionBar`（编辑 + 复制图标）。
- AI 回复块 `_AssistantBlock` 下方同样挂 `AiMessageActionBar`（复制 / 导出 / fork / 版本切换）。
- 当前 UI 任何位置都不显示消息时间。

## 方案（已确认）

时间文本作为 `AiMessageActionBar` 的一部分，放在工具条行首（图标左侧）。

### 包内改动（ai_message_ui）

- `AiMessageActionBar` 新增可选参数 `String? timestampText`：
  - 非空时在动作行最左侧渲染一段小号文本（`labelSmall`/`labelMedium` 级别，主题色弱化，`tabularFigures` 保证数字宽度稳定），与图标间留 4-6px 间距。
  - 为空时行内容与现状完全一致。
  - 文本不参与 copy/export 动作；`SelectionContainer.disabled` 行为不变。
- `_HoverScopedActionBar` 透传 `timestampText`。
- `AiMessageView` 新增可选参数 `String? timestampText`，`_UserBubble` / `_AssistantBlock` 透传给各自的 `AiMessageActionBar`；不传时行为与现状一致。
- 包不引入 l10n / 日期格式化 —— 只接收应用层格式化好的字符串（符合该包 "stays free of app l10n" 的现有约定）。

### 应用层改动（teampilot client）

- 新增格式化工具（建议 `client/lib/utils/chat/chat_timestamp_format.dart`）：
  - `String? formatChatTimestamp(DateTime? createdAt, {DateTime? now, required String locale})`
  - `createdAt == null` → 返回 null。
  - 同一自然日（本地时区）→ `DateFormat('HH:mm')`。
  - 否则 → `DateFormat('MMMd', locale)` + 空格 + `HH:mm`（zh 输出 `11月6日 15:44`，en 输出 `Nov 6 15:44`）。
  - `now` 可注入以便测试；默认 `DateTime.now()`。
  - `createdAt` 若为 UTC，先转本地时间再比较/格式化。
- 调用点：应用在 `client/lib/pages/chat/session_history_thread.dart:1293` 处逐条构造 `AiMessageView(message: ai, ...)`，在此处对 `ai.createdAt` 调用格式化工具，把结果作为新参数 `timestampText` 传给 `AiMessageView`；`AiMessageView` 内部透传给 `_UserBubble` / `_AssistantBlock`。locale 取应用当前 locale。

### 边界情况

| 情况 | 行为 |
|------|------|
| `createdAt == null`（发送中的乐观消息等） | 不显示时间，工具条照旧 |
| 今天之前的历史消息 | 显示 `M月d日 HH:mm` |
| 跨年历史消息 | 同上（不带年份，YAGNI） |
| 工具条 hover-reveal（非最后一条消息） | 时间随工具条一起显隐 |
| 最后一条消息（reveal = always） | 时间常驻随工具条显示 |

## 不做的事

- 不做消息流中的日期分隔线（iMessage 式）。
- 不改 copy/export 行为、不加“复制时间”交互。
- 不处理跨年特殊格式。
- 不改 transcript 解析（`createdAt` 数据已齐）。

## 测试

1. **包内 widget 测试**（`ai_message_ui/test/`，沿用该包现有测试风格）：
   - `timestampText` 非空时渲染该文本且位于图标行首。
   - 为空时不渲染任何时间文本（与现状一致）。
   - hover-reveal 模式下时间随工具条显隐（Opacity 0/1）。
2. **应用层单测**（`client/test/utils/chat/`）：
   - null → null。
   - 今天的消息 → `HH:mm`。
   - 非今天的消息 → 含月日与 `HH:mm`（zh locale 断言 `11月6日`）。
   - UTC 输入转本地后判断“今天”。
   - `now` 注入构造边界（当天 00:00 前 / 后）。
3. **完成前**：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`。
