# 聊天消息时间戳显示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在会话聊天界面的消息工具条（hover 显示）中展示每条用户消息 / AI 回复的发送时间：今天 `15:44`，非今天 `11月6日 15:44`。

**Architecture:** 应用层新增 `formatChatTimestamp` 格式化工具（intl + locale），在 `session_history_thread.dart` 构造 `AiMessageView` 处传入；`ai_message_ui` 包内 `AiMessageActionBar` 新增可选 `timestampText` 参数渲染在动作行行首，经 `AiMessageView` → `_UserBubble` / `_AssistantBlock` → `_HoverScopedActionBar` 透传。包不引入 l10n，只接收格式化好的字符串。

**Tech Stack:** Flutter / Dart、intl（DateFormat）、flutter_test。

**Spec:** `docs/superpowers/specs/2026-11-09-chat-message-timestamp-design.md`

## Global Constraints

- **绝不直接调用 `flutter test`** —— 一律 `cd client && dart run tool/run_tests.dart <paths/options>`（包测试也验证过可用：`dart run tool/run_tests.dart packages/ai_message_ui/test/message_action_bar_test.dart`）。
- 测试循环：内层 `flutter analyze`，先跑单个测试文件，全部完成前才跑完整套件。
- `ai_message_ui` 包保持不依赖应用 l10n —— 只接收 `String? timestampText`。
- client 根目录 analyze 排除 `packages/**`；改包代码后在包目录单独跑 `flutter analyze --no-fatal-infos --no-fatal-warnings`。
- `createdAt == null` → 不显示时间，工具条行为与现状一致。
- 跨年消息不特殊处理（仍 `M月d日 HH:mm`，无年份）。
- 不加新的用户可见文案，无需改 slang l10n。
- 提交信息用英文 conventional commits。

---

### Task 1: 应用层时间格式化工具 `formatChatTimestamp`

**Files:**
- Create: `client/lib/utils/chat/chat_timestamp_format.dart`
- Test: `client/test/utils/chat/chat_timestamp_format_test.dart`

**Interfaces:**
- Consumes: 无（独立纯函数）。
- Produces: `String? formatChatTimestamp(DateTime? createdAt, {DateTime? now, required String locale})` — Task 4 在 `session_history_thread.dart` 调用。

- [ ] **Step 1: 写失败测试**

创建 `client/test/utils/chat/chat_timestamp_format_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:teampilot/utils/chat/chat_timestamp_format.dart';

void main() {
  setUpAll(initializeDateFormatting);

  final now = DateTime(2026, 11, 9, 18, 0);

  test('null createdAt returns null', () {
    expect(formatChatTimestamp(null, now: now, locale: 'zh'), isNull);
  });

  test('same local day renders time only', () {
    expect(
      formatChatTimestamp(DateTime(2026, 11, 9, 15, 44), now: now, locale: 'zh'),
      '15:44',
    );
    expect(
      formatChatTimestamp(DateTime(2026, 11, 9, 0, 0), now: now, locale: 'zh'),
      '00:00',
    );
  });

  test('another day renders month-day and time (zh)', () {
    expect(
      formatChatTimestamp(DateTime(2026, 11, 6, 15, 44), now: now, locale: 'zh'),
      '11月6日 15:44',
    );
    // One minute before midnight is still "another day".
    expect(
      formatChatTimestamp(DateTime(2026, 11, 8, 23, 59), now: now, locale: 'zh'),
      '11月8日 23:59',
    );
  });

  test('another day renders month-day and time (en)', () {
    expect(
      formatChatTimestamp(DateTime(2026, 11, 6, 15, 44), now: now, locale: 'en'),
      'Nov 6 15:44',
    );
  });

  test('cross-year stays month-day form without a year', () {
    expect(
      formatChatTimestamp(DateTime(2025, 12, 31, 23, 0), now: now, locale: 'zh'),
      '12月31日 23:00',
    );
  });

  test('UTC input is converted to local time', () {
    final utc = DateTime.utc(2026, 11, 9, 12, 30);
    final local = utc.toLocal();
    final expected =
        '${DateFormat('MMMd', 'zh').format(local)} '
        '${DateFormat('HH:mm').format(local)}';
    expect(formatChatTimestamp(utc, now: local, locale: 'zh'), expected);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/utils/chat/chat_timestamp_format_test.dart`
Expected: FAIL（`chat_timestamp_format.dart` 不存在，编译错误）。

- [ ] **Step 3: 写最小实现**

创建 `client/lib/utils/chat/chat_timestamp_format.dart`：

```dart
import 'package:intl/intl.dart';

/// Formats a chat message timestamp for the message action bar.
///
/// Same local calendar day as [now] (defaults to `DateTime.now()`) renders
/// `HH:mm`; any other day renders `MMMd HH:mm` (zh: `11月6日 15:44`,
/// en: `Nov 6 15:44`). Returns null when [createdAt] is null — callers hide
/// the label in that case.
String? formatChatTimestamp(
  DateTime? createdAt, {
  DateTime? now,
  required String locale,
}) {
  if (createdAt == null) return null;
  final local = createdAt.toLocal();
  final reference = (now ?? DateTime.now()).toLocal();
  final sameDay =
      local.year == reference.year &&
      local.month == reference.month &&
      local.day == reference.day;
  final time = DateFormat('HH:mm').format(local);
  if (sameDay) return time;
  return '${DateFormat('MMMd', locale).format(local)} $time';
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/utils/chat/chat_timestamp_format_test.dart`
Expected: PASS（6 个用例全过）。

- [ ] **Step 5: 内层 analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues found.

- [ ] **Step 6: 提交**

```bash
git add client/lib/utils/chat/chat_timestamp_format.dart client/test/utils/chat/chat_timestamp_format_test.dart
git commit -m "feat: add chat message timestamp formatter"
```

---

### Task 2: `AiMessageActionBar` 增加 `timestampText`

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/message_action_bar.dart`
- Test: `client/packages/ai_message_ui/test/message_action_bar_timestamp_test.dart`（新建）

**Interfaces:**
- Consumes: 无。
- Produces: `AiMessageActionBar({..., String? timestampText})` — Task 3 经 `_HoverScopedActionBar` 透传。

- [ ] **Step 1: 写失败测试**

创建 `client/packages/ai_message_ui/test/message_action_bar_timestamp_test.dart`：

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final message = AiMessage(
    id: '1',
    role: AiRole.assistant,
    parts: const [AiTextPart(text: 'hello')],
  );

  Finder copyIcon() => find.byIcon(Icons.copy_rounded);

  testWidgets('timestamp renders before the copy icon', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(
            message: message,
            timestampText: '11月6日 15:44',
          ),
        ),
      ),
    );
    expect(find.text('11月6日 15:44'), findsOneWidget);
    final tsLeft = tester.getTopLeft(find.text('11月6日 15:44')).dx;
    final copyLeft = tester.getTopLeft(copyIcon()).dx;
    expect(tsLeft, lessThan(copyLeft));
  });

  testWidgets('null timestamp renders no label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AiMessageActionBar(message: message)),
      ),
    );
    expect(find.text('11月6日 15:44'), findsNothing);
    expect(copyIcon(), findsOneWidget);
  });

  testWidgets('hover reveal keeps bar height stable with timestamp', (
    tester,
  ) async {
    Widget bar({required bool forceVisible}) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: AiMessageActionBar(
              message: message,
              reveal: AiActionBarReveal.hover,
              forceVisible: forceVisible,
              timestampText: '15:44',
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(bar(forceVisible: false));
    final hidden = tester.getSize(find.byType(AiMessageActionBar));
    // Unmounted phase: the label is not in the tree at all, only the
    // fixed-height placeholder.
    expect(find.text('15:44'), findsNothing);

    await tester.pumpWidget(bar(forceVisible: true));
    await tester.pump();
    final shown = tester.getSize(find.byType(AiMessageActionBar));
    expect(find.text('15:44'), findsOneWidget);
    expect(shown.height, equals(hidden.height));
  });

  testWidgets('timestamp alone mounts the bar for a copyless message', (
    tester,
  ) async {
    final empty = AiMessage(id: '2', role: AiRole.assistant, parts: const []);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiMessageActionBar(message: empty, timestampText: '15:44'),
        ),
      ),
    );
    expect(find.text('15:44'), findsOneWidget);
  });
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && dart run tool/run_tests.dart packages/ai_message_ui/test/message_action_bar_timestamp_test.dart`
Expected: FAIL（`timestampText` 参数不存在，编译错误）。

- [ ] **Step 3: 实现**

修改 `client/packages/ai_message_ui/lib/src/message_action_bar.dart`：

1. 构造函数参数列表（`this.dense = false,` 之后、`super.key` 之前）加：

```dart
    this.timestampText,
```

2. 字段（`final bool dense;` 之后）加：

```dart
  /// Pre-formatted timestamp label rendered at the start of the action row.
  /// The package stays free of date formatting / l10n — callers pass text.
  final String? timestampText;
```

3. `_mountActions` 的挂载条件（`if (_plain.isNotEmpty || ...)` 块）追加一行，让只有时间没有动作的消息也能挂载工具条：

```dart
    if (_plain.isNotEmpty ||
        _markdown.isNotEmpty ||
        widget.onRetryDelivery != null ||
        widget.onEdit != null ||
        widget.onFork != null ||
        _showsVersion ||
        widget.timestampText != null) {
```

4. `build` 中 `actions` 的 `Row` children 最前面（第一个 `if (widget.onRetryDelivery != null)` 之前）加：

```dart
        if (widget.timestampText != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              widget.timestampText!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart packages/ai_message_ui/test/message_action_bar_timestamp_test.dart`
Expected: PASS（4 个用例全过）。

- [ ] **Step 5: 包内已有测试不回归**

Run: `cd client && dart run tool/run_tests.dart packages/ai_message_ui/test/message_action_bar_test.dart`
Expected: PASS。

- [ ] **Step 6: 包内 analyze**

Run: `cd client/packages/ai_message_ui && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues found.

- [ ] **Step 7: 提交**

```bash
git add client/packages/ai_message_ui/lib/src/message_action_bar.dart client/packages/ai_message_ui/test/message_action_bar_timestamp_test.dart
git commit -m "feat(ai_message_ui): optional timestamp label in message action bar"
```

---

### Task 3: `AiMessageView` 透传 `timestampText`

**Files:**
- Modify: `client/packages/ai_message_ui/lib/src/ai_message_view.dart`
- Test: `client/packages/ai_message_ui/test/ai_message_view_timestamp_test.dart`（新建）

**Interfaces:**
- Consumes: `AiMessageActionBar({String? timestampText})`（Task 2）。
- Produces: `AiMessageView({..., String? timestampText})` — Task 4 在 `session_history_thread.dart` 调用。

- [ ] **Step 1: 写失败测试**

创建 `client/packages/ai_message_ui/test/ai_message_view_timestamp_test.dart`：

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:ai_message_ui/ai_message_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: child),
  );

  testWidgets('user message renders timestamp under the bubble', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AiMessageView(
          message: const AiMessage(
            id: 'u1',
            role: AiRole.user,
            parts: [AiTextPart(text: 'hello')],
          ),
          timestampText: '11月6日 15:44',
        ),
      ),
    );
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('11月6日 15:44'), findsOneWidget);
    final tsTop = tester.getTopLeft(find.text('11月6日 15:44')).dy;
    final bubbleTop = tester.getTopLeft(find.text('hello')).dy;
    expect(tsTop, greaterThan(bubbleTop));
  });

  testWidgets('assistant message renders timestamp under the block', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        AiMessageView(
          message: const AiMessage(
            id: 'a1',
            role: AiRole.assistant,
            parts: [AiTextPart(text: 'reply')],
          ),
          timestampText: '15:44',
        ),
      ),
    );
    expect(find.text('15:44'), findsOneWidget);
    final tsTop = tester.getTopLeft(find.text('15:44')).dy;
    final bodyTop = tester.getTopLeft(find.text('reply')).dy;
    expect(tsTop, greaterThan(bodyTop));
  });

  testWidgets('null timestamp renders nothing extra', (tester) async {
    await tester.pumpWidget(
      host(
        AiMessageView(
          message: const AiMessage(
            id: 'u2',
            role: AiRole.user,
            parts: [AiTextPart(text: 'hi')],
          ),
        ),
      ),
    );
    expect(find.text('15:44'), findsNothing);
  });
}
```

注意：`AiMessage` / `AiTextPart` 构造若非常量可去掉 `const`（以包内现有构造签名为准；测试编译不过就把消息提到局部变量、去掉 `const`）。

- [ ] **Step 2: 运行测试确认失败**

Run: `cd client && dart run tool/run_tests.dart packages/ai_message_ui/test/ai_message_view_timestamp_test.dart`
Expected: FAIL（`timestampText` 参数不存在，编译错误）。

- [ ] **Step 3: 实现**

修改 `client/packages/ai_message_ui/lib/src/ai_message_view.dart`（4 处透传）：

1. `AiMessageView` 构造函数（`this.chainOfThoughtAutoExpand = false,` 附近，`super.key` 之前）加：

```dart
    this.timestampText,
```

2. `AiMessageView` 字段（`final AiMessage message;` 之后）加：

```dart
  /// Pre-formatted timestamp for the action bar; null hides the label.
  final String? timestampText;
```

3. `_AiMessageViewState.build` 的 switch 分支：`_UserBubble(...)`（`AiRole.user =>`）和 `_AssistantBlock(...)`（`AiRole.assistant =>`）各加一行：

```dart
            timestampText: widget.timestampText,
```

4. `_UserBubble` 构造参数 + 字段（`this.nextVersionLabel = 'Next version',` 之后）加 `this.timestampText,` / `final String? timestampText;`；其 `_buildCollapsed` 中 `_HoverScopedActionBar(...)` 调用加：

```dart
                    timestampText: timestampText,
```

5. `_AssistantBlock` 同样加构造参数 + 字段；其 `_HoverScopedActionBar(...)` 调用加：

```dart
                  timestampText: timestampText,
```

6. `_HoverScopedActionBar` 构造参数（`this.dense = false,` 之后）+ 字段加 `this.timestampText,` / `final String? timestampText;`；其 `AiMessageActionBar(...)` 调用加：

```dart
      timestampText: timestampText,
```

- [ ] **Step 4: 运行测试确认通过**

Run: `cd client && dart run tool/run_tests.dart packages/ai_message_ui/test/ai_message_view_timestamp_test.dart`
Expected: PASS（3 个用例全过）。

- [ ] **Step 5: 包内相关测试不回归**

Run: `cd client && dart run tool/run_tests.dart packages/ai_message_ui/test/`
Expected: PASS（包内全部测试通过）。

- [ ] **Step 6: 包内 analyze**

Run: `cd client/packages/ai_message_ui && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues found.

- [ ] **Step 7: 提交**

```bash
git add client/packages/ai_message_ui/lib/src/ai_message_view.dart client/packages/ai_message_ui/test/ai_message_view_timestamp_test.dart
git commit -m "feat(ai_message_ui): thread timestamp through AiMessageView"
```

---

### Task 4: 应用侧接线（session_history_thread）

**Files:**
- Modify: `client/lib/pages/chat/session_history_thread.dart`（约 :1293 `final messageChild = AiMessageView(` 处）

**Interfaces:**
- Consumes: `formatChatTimestamp`（Task 1）、`AiMessageView({String? timestampText})`（Task 3）。
- Produces: 完整功能。

- [ ] **Step 1: 加 import**

在 `client/lib/pages/chat/session_history_thread.dart` 顶部 import 区加：

```dart
import '../../utils/chat/chat_timestamp_format.dart';
```

（相对路径按该文件现有 `../../` 风格；文件位于 `lib/pages/chat/` 下。）

- [ ] **Step 2: 构造 `AiMessageView` 处传入时间**

在 `final messageChild = AiMessageView(` 之前加：

```dart
                          final timestampText = formatChatTimestamp(
                            ai.createdAt,
                            locale: Localizations.localeOf(context).languageCode,
                          );
```

并在 `AiMessageView(...)` 参数列表中（`message: ai,` 之后）加：

```dart
                            timestampText: timestampText,
```

- [ ] **Step 3: 内层 analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues found.

- [ ] **Step 4: 冒烟验证（已有聊天页面测试）**

Run: `cd client && dart run tool/run_tests.dart test/pages/chat/`
Expected: PASS（现有 chat 页面测试不回归）。

- [ ] **Step 5: 提交**

```bash
git add client/lib/pages/chat/session_history_thread.dart
git commit -m "feat: show message timestamps in chat action bars"
```

- [ ] **Step 6: 完成前全量门禁**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: analyze 无问题、全部测试通过。**通过后才能声称完成。**
