# 移动端消息交互：长按菜单与点击编辑 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Android/iOS 上被隐藏的消息功能按钮通过长按菜单可达，并让点击用户气泡进入带遮罩的底部编辑面板。

**Architecture:** 全部改动在应用层 `client/lib/pages/chat/`。两个新的无状态/有状态 widget 文件分别负责菜单项构建与底部编辑面板；`SessionHistoryThread.messageBuilder` 负责在移动端给每条消息套上 `SelectionContainer.disabled + GestureDetector`，并在编辑态给其它消息套 `IgnorePointer + Opacity`。vendored 包 `ai_message_ui`、`shared_ui`、composer、`SessionChatView` 均不改动。

**Tech Stack:** Flutter 3.47 / Dart 3.8、`ai_message_core`（`plainTextForCopy` / `markdownForExport`）、`ai_message_ui`（`AiMessageView` / `AiMessageInteractionScope`）、`shared_ui`（`showTpActionMenuFromSpecs` / `TpActionMenuSpec` / `TpTextStyles`）、slang l10n（`context.l10n`）、`BranchEditController`（rewind 编辑状态）。

**Spec:** `docs/superpowers/specs/2026-11-11-mobile-chat-message-actions-design.md`（已批准并提交）。

## Global Constraints

- 仅 Android / iOS 启用；门控复用 `build()` 中 `mobile = widget.mobilePerformanceMode ?? (Platform.isAndroid || Platform.isIOS)`（`session_history_thread.dart:1117`）。桌面端行为完全不变。
- 测试可用 `mobilePerformanceMode: true/false` 注入平台门控。
- **Never invoke `flutter test` directly** — 一律 `cd client && dart run tool/run_tests.dart <paths/options>`。
- 完成前必须：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`（全量仅一次，后台跑）。
- 内环 `flutter analyze` + 单文件 `--plain-name` 验证，外环全量一次，不要倒置。
- l10n：复用现有键，**不新增键**、不跑 `dart run slang`。复用：`copy`、`ai.messageExportMarkdown`、`ai.messageCopied`、`edit.userMessage`、`edit.cancel`、`edit.send`、`forkFromHere`、`session.historyRetry`、`branchPrevious`、`branchNext`。
- 文本样式必须用 `TpTextStyles` 命名 scale getter（如 `mdColored` / `mdSemiboldColored`），不得内联 `TextStyle` 或 `copyWith`。
- 新增 UI 拆成独立文件；`session_history_thread.dart` 已 1400+ 行，不得往里塞大块 UI。
- **工作区原本就有 39 个未提交/未跟踪的改动（含 `session_chat_view.dart`、`workspace_compose_card.dart`、`ai_message_ui` 包内文件）。每次 commit 只 `git add` 本任务涉及的文件，绝对不要 `git add -A` / `git add .`。**
- 每个 commit 只包含本任务的文件；不要提交或修改任何预先存在的改动。

---

## File Structure

| 文件 | 职责 |
|------|------|
| `client/lib/pages/chat/chat_message_action_menu.dart` | **新增**。`ChatMessageActionHandlers`（回调集合）、`buildChatMessageActionSpecs`（纯函数，产出菜单项）、`showChatMessageActionMenu`（弹菜单）。剪贴板写入与 toast 通过参数注入，便于测试。 |
| `client/lib/pages/chat/chat_message_edit_panel.dart` | **新增**。`showChatMessageEditSheet`（`showModalBottomSheet<bool>`）+ `_MobileMessageEditPanel`（标题/关闭、预填 TextField、取消/发送）。 |
| `client/lib/pages/chat/session_history_thread.dart` | **修改**。`messageBuilder` 手势包装与遮罩；`AiMessageView` 的 `editing` / `onEdit` / `onSubmitEdit`；抽出 `_submitEdit`；新增 `_openMobileEdit`；`_bodyCacheKeyForTurn` 补缓存键；加 2 个本地 import。 |
| `client/test/pages/chat/chat_message_action_menu_test.dart` | **新增**。菜单项单测 + 弹菜单 widget 测试。 |
| `client/test/pages/chat/chat_message_edit_panel_test.dart` | **新增**。编辑面板预填/成功/失败/取消测试。 |
| `client/test/pages/chat/session_history_thread_test.dart` | **修改**。扩展 `_harness` 支持 `branches` / `onEditUserMessage`，新增移动端手势、长按菜单、点击编辑 + 遮罩测试。 |

---

### Task 1: 长按菜单 helper（`chat_message_action_menu.dart`）

**Files:**
- Create: `client/lib/pages/chat/chat_message_action_menu.dart`
- Create: `client/test/pages/chat/chat_message_action_menu_test.dart`

**Interfaces:**
- Consumes: `AiMessage`、`plainTextForCopy` / `markdownForExport`（`ai_message_core`）、`context.l10n`、`showTpActionMenuFromSpecs` / `TpActionMenuSpec`（`shared_ui`）、`AppToast` / `TpToastVariant`。
- Produces:
  - `typedef ChatMessageClipboardWriter = Future<void> Function(String text);`
  - `class ChatMessageActionHandlers` — const 构造，字段 `VoidCallback? onRetry, onEdit, onFork, onPreviousVersion, onNextVersion`。
  - `List<TpActionMenuSpec> buildChatMessageActionSpecs(BuildContext context, {required AiMessage message, required bool deliveryFailed, required bool showsVersion, required bool rewindEnabled, required ChatMessageActionHandlers handlers, required ChatMessageClipboardWriter writeClipboard, required ValueChanged<String> onFeedback})`
  - `Future<void> showChatMessageActionMenu(BuildContext context, {required Offset globalPosition, required AiMessage message, required bool deliveryFailed, required bool showsVersion, required bool rewindEnabled, required ChatMessageActionHandlers handlers, ChatMessageClipboardWriter writeClipboard = _defaultClipboardWriter, ValueChanged<String>? onFeedback})`

- [ ] **Step 1: Write the failing test**

Create `client/test/pages/chat/chat_message_action_menu_test.dart`:

```dart
import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/chat/chat_message_action_menu.dart';

const _textMessage = AiMessage(
  id: 'm1',
  role: AiRole.assistant,
  parts: [AiTextPart(text: 'hello')],
);

const _emptyMessage = AiMessage(
  id: 'm2',
  role: AiRole.assistant,
  parts: [],
);

Future<BuildContext> _captureContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appLocalizationsSupportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return captured;
}

List<TpActionMenuSpec> _specs(
  BuildContext context, {
  AiMessage message = _textMessage,
  bool deliveryFailed = false,
  bool showsVersion = false,
  bool rewindEnabled = true,
  ChatMessageActionHandlers handlers = const ChatMessageActionHandlers(),
  required ChatMessageClipboardWriter writeClipboard,
  required ValueChanged<String> onFeedback,
}) {
  return buildChatMessageActionSpecs(
    context,
    message: message,
    deliveryFailed: deliveryFailed,
    showsVersion: showsVersion,
    rewindEnabled: rewindEnabled,
    handlers: handlers,
    writeClipboard: writeClipboard,
    onFeedback: onFeedback,
  );
}

void main() {
  testWidgets('plain message offers only copy + export markdown', (tester) async {
    final context = await _captureContext(tester);
    final specs = _specs(
      context,
      writeClipboard: (text) async {},
      onFeedback: (_) {},
    );
    expect(specs, hasLength(2));
    expect(specs[0].label, 'copy');
    expect(specs[0].enabled, isTrue);
    expect(specs[1].label, 'Export Markdown');
    expect(specs[1].enabled, isTrue);
  });

  testWidgets('empty message disables both clipboard actions', (tester) async {
    final context = await _captureContext(tester);
    final specs = _specs(
      context,
      message: _emptyMessage,
      writeClipboard: (text) async {},
      onFeedback: (_) {},
    );
    expect(specs, hasLength(2));
    expect(specs[0].enabled, isFalse);
    expect(specs[1].enabled, isFalse);
  });

  testWidgets('full menu keeps action-bar order and honours rewindEnabled', (tester) async {
    final context = await _captureContext(tester);
    final handlers = ChatMessageActionHandlers(
      onRetry: () {},
      onEdit: () {},
      onFork: () {},
      onPreviousVersion: () {},
      onNextVersion: () {},
    );
    final specs = _specs(
      context,
      deliveryFailed: true,
      showsVersion: true,
      rewindEnabled: false,
      handlers: handlers,
      writeClipboard: (text) async {},
      onFeedback: (_) {},
    );
    expect(specs, hasLength(9));
    expect(specs[0].label, 'Retry');
    expect(specs[1].label, 'copy');
    expect(specs[2].isDivider, isTrue);
    expect(specs[3].label, 'Edit message');
    expect(specs[4].label, 'Fork from here');
    expect(specs[5].label, 'Previous version');
    expect(specs[6].label, 'Next version');
    expect(specs[7].isDivider, isTrue);
    expect(specs[8].label, 'Export Markdown');
    // Only the rewind group is disabled; retry / clipboard stay enabled.
    for (final index in [3, 4, 5, 6]) {
      expect(specs[index].enabled, isFalse, reason: 'index $index');
    }
    expect(specs[0].enabled, isTrue);
    expect(specs[1].enabled, isTrue);
    expect(specs[8].enabled, isTrue);
  });

  testWidgets('menu actions invoke handlers and copy both text forms', (tester) async {
    final context = await _captureContext(tester);
    final calls = <String>[];
    final copied = <String>[];
    final feedback = <String>[];
    final specs = _specs(
      context,
      deliveryFailed: true,
      showsVersion: true,
      handlers: ChatMessageActionHandlers(
        onRetry: () => calls.add('retry'),
        onEdit: () => calls.add('edit'),
        onFork: () => calls.add('fork'),
        onPreviousVersion: () => calls.add('prev'),
        onNextVersion: () => calls.add('next'),
      ),
      writeClipboard: (text) async => copied.add(text),
      onFeedback: (message) => feedback.add(message),
    );
    for (final spec in specs.where((spec) => !spec.isDivider)) {
      spec.onAction?.call();
    }
    expect(calls, ['retry', 'edit', 'fork', 'prev', 'next']);
    expect(copied, ['hello', 'hello']);
    expect(feedback, ['Copied', 'Copied']);
  });

  testWidgets('showChatMessageActionMenu renders TpActionMenuItems', (tester) async {
    final context = await _captureContext(tester);
    unawaited(
      showChatMessageActionMenu(
        context,
        globalPosition: Offset.zero,
        message: _textMessage,
        deliveryFailed: false,
        showsVersion: false,
        rewindEnabled: true,
        handlers: const ChatMessageActionHandlers(),
        writeClipboard: (text) async {},
        onFeedback: (_) {},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(TpActionMenuItem), findsNWidgets(2));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/pages/chat/chat_message_action_menu_test.dart
```
Expected: 编译失败 —— `Target of URI doesn't exist: 'package:teampilot/pages/chat/chat_message_action_menu.dart'`。

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/pages/chat/chat_message_action_menu.dart`:

```dart
import 'dart:async';

import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../widgets/app_toast/app_toast.dart';

/// Injected so tests can assert the copied text without mocking the platform
/// channel (matches AGENTS.md "mock at the boundary via injection").
typedef ChatMessageClipboardWriter = Future<void> Function(String text);

Future<void> _defaultClipboardWriter(String text) =>
    Clipboard.setData(ClipboardData(text: text));

/// Callbacks for the message-level actions that the host already wires into
/// [AiMessageView]. Null hides the item.
@immutable
class ChatMessageActionHandlers {
  const ChatMessageActionHandlers({
    this.onRetry,
    this.onEdit,
    this.onFork,
    this.onPreviousVersion,
    this.onNextVersion,
  });

  final VoidCallback? onRetry;
  final VoidCallback? onEdit;
  final VoidCallback? onFork;
  final VoidCallback? onPreviousVersion;
  final VoidCallback? onNextVersion;
}

/// Pure menu-item builder. Order mirrors [AiMessageActionBar]; the rewind
/// group is bracketed by dividers so a plain message stays a 2-item menu.
List<TpActionMenuSpec> buildChatMessageActionSpecs(
  BuildContext context, {
  required AiMessage message,
  required bool deliveryFailed,
  required bool showsVersion,
  required bool rewindEnabled,
  required ChatMessageActionHandlers handlers,
  required ChatMessageClipboardWriter writeClipboard,
  required ValueChanged<String> onFeedback,
}) {
  final l10n = context.l10n;
  final plain = plainTextForCopy(message);
  final markdown = markdownForExport(message);

  void copy(String text) {
    unawaited(writeClipboard(text));
    onFeedback(l10n.ai.messageCopied);
  }

  final rewindItems = <TpActionMenuSpec>[
    if (handlers.onEdit != null)
      TpActionMenuSpec.item(
        icon: Icons.edit_outlined,
        label: l10n.edit.userMessage,
        enabled: rewindEnabled,
        onAction: handlers.onEdit,
      ),
    if (handlers.onFork != null)
      TpActionMenuSpec.item(
        icon: Icons.call_split,
        label: l10n.forkFromHere,
        enabled: rewindEnabled,
        onAction: handlers.onFork,
      ),
    if (showsVersion && handlers.onPreviousVersion != null)
      TpActionMenuSpec.item(
        icon: Icons.chevron_left,
        label: l10n.branchPrevious,
        enabled: rewindEnabled,
        onAction: handlers.onPreviousVersion,
      ),
    if (showsVersion && handlers.onNextVersion != null)
      TpActionMenuSpec.item(
        icon: Icons.chevron_right,
        label: l10n.branchNext,
        enabled: rewindEnabled,
        onAction: handlers.onNextVersion,
      ),
  ];

  return <TpActionMenuSpec>[
    if (deliveryFailed && handlers.onRetry != null)
      TpActionMenuSpec.item(
        icon: Icons.refresh_rounded,
        label: l10n.session.historyRetry,
        onAction: handlers.onRetry,
      ),
    TpActionMenuSpec.item(
      icon: Icons.copy_rounded,
      label: l10n.copy,
      enabled: plain.isNotEmpty,
      onAction: () => copy(plain),
    ),
    if (rewindItems.isNotEmpty) const TpActionMenuSpec.divider(),
    ...rewindItems,
    if (rewindItems.isNotEmpty) const TpActionMenuSpec.divider(),
    TpActionMenuSpec.item(
      icon: Icons.description_outlined,
      label: l10n.ai.messageExportMarkdown,
      enabled: markdown.isNotEmpty,
      onAction: () => copy(markdown),
    ),
  ];
}

Future<void> showChatMessageActionMenu(
  BuildContext context, {
  required Offset globalPosition,
  required AiMessage message,
  required bool deliveryFailed,
  required bool showsVersion,
  required bool rewindEnabled,
  required ChatMessageActionHandlers handlers,
  ChatMessageClipboardWriter writeClipboard = _defaultClipboardWriter,
  ValueChanged<String>? onFeedback,
}) {
  final feedback =
      onFeedback ??
      (String text) => AppToast.show(
        context,
        message: text,
        variant: TpToastVariant.success,
      );
  return showTpActionMenuFromSpecs<void>(
    context: context,
    globalPosition: globalPosition,
    specs: buildChatMessageActionSpecs(
      context,
      message: message,
      deliveryFailed: deliveryFailed,
      showsVersion: showsVersion,
      rewindEnabled: rewindEnabled,
      handlers: handlers,
      writeClipboard: writeClipboard,
      onFeedback: feedback,
    ),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/chat/chat_message_action_menu.dart && dart run tool/run_tests.dart test/pages/chat/chat_message_action_menu_test.dart
```
Expected: PASS（5 个测试全绿），analyze 无 error。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && git add client/lib/pages/chat/chat_message_action_menu.dart client/test/pages/chat/chat_message_action_menu_test.dart && git commit -m "feat(chat): add mobile long-press message action menu helper"
```

---

### Task 2: 底部编辑面板（`chat_message_edit_panel.dart`）

**Files:**
- Create: `client/lib/pages/chat/chat_message_edit_panel.dart`
- Create: `client/test/pages/chat/chat_message_edit_panel_test.dart`

**Interfaces:**
- Consumes: `showModalBottomSheet`、`TpTextStyles`（`shared_ui`）。
- Produces: `Future<bool> showChatMessageEditSheet(BuildContext context, {required String initialText, required String title, required String cancelLabel, required String sendLabel, required Future<bool> Function(String text) onSubmit})` — 成功返回 `true`，取消/关闭返回 `false`。面板内控件 key：`chat-edit-sheet-field`、`chat-edit-sheet-close`、`chat-edit-sheet-cancel`、`chat-edit-sheet-send`。

- [ ] **Step 1: Write the failing test**

Create `client/test/pages/chat/chat_message_edit_panel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/chat_message_edit_panel.dart';

const _field = ValueKey('chat-edit-sheet-field');
const _send = ValueKey('chat-edit-sheet-send');
const _cancel = ValueKey('chat-edit-sheet-cancel');
const _close = ValueKey('chat-edit-sheet-close');

Widget _host(
  Future<bool> Function(String text) onSubmit,
  ValueChanged<bool> onResult,
) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            key: const ValueKey('open'),
            onPressed: () async {
              final result = await showChatMessageEditSheet(
                context,
                initialText: 'original text',
                title: 'Edit message',
                cancelLabel: 'Cancel',
                sendLabel: 'Send',
                onSubmit: onSubmit,
              );
              onResult(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('open')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('sheet prefills the original text and returns true on success', (tester) async {
    final submitted = <String>[];
    final results = <bool>[];
    await tester.pumpWidget(
      _host((text) async {
        submitted.add(text);
        return true;
      }, results.add),
    );
    await _open(tester);

    expect(find.byKey(_field), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(_field)).controller!.text,
      'original text',
    );

    await tester.enterText(find.byKey(_field), 'edited');
    await tester.tap(find.byKey(_send));
    await _settle(tester);

    expect(submitted, ['edited']);
    expect(results, [isTrue]);
    expect(find.byKey(_field), findsNothing);
  });

  testWidgets('a failed submit keeps the sheet and the draft', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(_host((text) async => false, results.add));
    await _open(tester);

    await tester.enterText(find.byKey(_field), 'edited');
    await tester.tap(find.byKey(_send));
    await _settle(tester);

    expect(find.byKey(_field), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(_field)).controller!.text,
      'edited',
    );
    expect(results, isEmpty);
  });

  testWidgets('cancel returns false and closes the sheet', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(_host((text) async => true, results.add));
    await _open(tester);

    await tester.tap(find.byKey(_cancel));
    await _settle(tester);

    expect(results, [isFalse]);
    expect(find.byKey(_field), findsNothing);
  });

  testWidgets('close icon returns false', (tester) async {
    final results = <bool>[];
    await tester.pumpWidget(_host((text) async => true, results.add));
    await _open(tester);

    await tester.tap(find.byKey(_close));
    await _settle(tester);

    expect(results, [isFalse]);
  });

  testWidgets('empty text does not submit', (tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(
      _host((text) async {
        submitted.add(text);
        return true;
      }, (_) {}),
    );
    await _open(tester);

    await tester.enterText(find.byKey(_field), '   ');
    await tester.tap(find.byKey(_send));
    await _settle(tester);

    expect(submitted, isEmpty);
    expect(find.byKey(_field), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/pages/chat/chat_message_edit_panel_test.dart
```
Expected: 编译失败 —— `Target of URI doesn't exist: 'package:teampilot/pages/chat/chat_message_edit_panel.dart'`。

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/pages/chat/chat_message_edit_panel.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Mobile "modify input" sheet. Returns true only after [onSubmit] accepted the
/// edit; dismissing (barrier / drag / X / cancel) returns false.
Future<bool> showChatMessageEditSheet(
  BuildContext context, {
  required String initialText,
  required String title,
  required String cancelLabel,
  required String sendLabel,
  required Future<bool> Function(String text) onSubmit,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    // A transparent barrier still blocks background taps (ModalBarrier), while
    // the "mask other parts" effect comes from per-message Opacity in the thread.
    barrierColor: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _MobileMessageEditPanel(
      initialText: initialText,
      title: title,
      cancelLabel: cancelLabel,
      sendLabel: sendLabel,
      onSubmit: onSubmit,
    ),
  );
  return result ?? false;
}

class _MobileMessageEditPanel extends StatefulWidget {
  const _MobileMessageEditPanel({
    required this.initialText,
    required this.title,
    required this.cancelLabel,
    required this.sendLabel,
    required this.onSubmit,
  });

  final String initialText;
  final String title;
  final String cancelLabel;
  final String sendLabel;
  final Future<bool> Function(String text) onSubmit;

  @override
  State<_MobileMessageEditPanel> createState() =>
      _MobileMessageEditPanelState();
}

class _MobileMessageEditPanelState extends State<_MobileMessageEditPanel> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  var _submitting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    final accepted = await widget.onSubmit(text);
    if (!mounted) return;
    if (accepted) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _submitting = false);
    }
  }

  void _cancel() => Navigator.of(context).pop(false);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TpTextStyles.of(
                        context,
                      ).mdSemiboldColored(scheme.onSurface),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('chat-edit-sheet-close'),
                    onPressed: _cancel,
                    icon: const Icon(Icons.close_rounded),
                    color: scheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('chat-edit-sheet-field'),
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                maxLines: 5,
                minLines: 1,
                style: TpTextStyles.of(context).mdColored(scheme.onSurface),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    key: const ValueKey('chat-edit-sheet-cancel'),
                    onPressed: _submitting ? null : _cancel,
                    child: Text(widget.cancelLabel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('chat-edit-sheet-send'),
                    onPressed: _submitting ? null : () => unawaited(_submit()),
                    child: _submitting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.sendLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/chat/chat_message_edit_panel.dart && dart run tool/run_tests.dart test/pages/chat/chat_message_edit_panel_test.dart
```
Expected: PASS（5 个测试全绿）。若 `pump` 后找不到 panel，把 `_open` / `_settle` 的 `Duration(milliseconds: 300)` 提高到 `500`（弹层动画时长），不要改用 `pumpAndSettle`（自动聚焦 TextField 的光标闪烁会导致其超时）。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && git add client/lib/pages/chat/chat_message_edit_panel.dart client/test/pages/chat/chat_message_edit_panel_test.dart && git commit -m "feat(chat): add mobile bottom sheet message edit panel"
```

---

### Task 3: 阶段一 —— 在 `SessionHistoryThread` 接上长按菜单

**Files:**
- Modify: `client/lib/pages/chat/session_history_thread.dart:259-273`（`_bodyCacheKeyForTurn`）、`:1377-1406`（`messageBuilder` 尾部）、`:1-23`（imports）
- Modify: `client/test/pages/chat/session_history_thread_test.dart`

**Interfaces:**
- Consumes: `showChatMessageActionMenu` / `ChatMessageActionHandlers`（Task 1）、`AiMessageInteractionScope.maybeRewindEnabled`（`ai_message_ui`）。
- Produces: 每条移动端消息外层 `GestureDetector` 带 `key: ValueKey('chat-message-gestures:${ai.id}')` 与非空 `onLongPressStart`。

- [ ] **Step 1: Write the failing test**

在 `client/test/pages/chat/session_history_thread_test.dart` 顶部 import 增加：

```dart
import 'package:shared_ui/shared_ui.dart';
```

在 `main()` 末尾追加：

```dart
  testWidgets('mobile thread attaches a long-press gesture to messages', (tester) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages(_soloUserMessages(3));

    await tester.pumpWidget(
      _harness(runtime: store, mobilePerformanceMode: true),
    );
    await pumpUntilSettled(tester);

    final finder = find.byKey(const ValueKey('chat-message-gestures:m0'));
    expect(finder, findsOneWidget);
    expect(
      tester.widget<GestureDetector>(finder).onLongPressStart,
      isNotNull,
    );
  });

  testWidgets('desktop thread attaches no message gesture wrapper', (tester) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages(_soloUserMessages(3));

    await tester.pumpWidget(
      _harness(runtime: store, mobilePerformanceMode: false),
    );
    await pumpUntilSettled(tester);

    expect(
      find.byKey(const ValueKey('chat-message-gestures:m0')),
      findsNothing,
    );
  });

  testWidgets('long press opens the action menu, not the text selection toolbar', (tester) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages(_soloUserMessages(3));

    await tester.pumpWidget(
      _harness(runtime: store, mobilePerformanceMode: true),
    );
    await pumpUntilSettled(tester);

    await tester.longPress(find.text('msg 0'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(TpActionMenuItem), findsWidgets);
    expect(find.text('Select all'), findsNothing);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/pages/chat/session_history_thread_test.dart --plain-name "mobile thread attaches a long-press gesture"
```
Expected: FAIL —— `Expected: exactly one matching candidate, Actual: _KeyFinder:<zero widgets with key ...>`。

- [ ] **Step 3: Write minimal implementation**

**(a)** 在 `client/lib/pages/chat/session_history_thread.dart` 的本地 import 区加入（与 `chat_outline.dart` 等并列，保持字母序）：

```dart
import 'chat_message_action_menu.dart';
```
（`chat_message_edit_panel.dart` 由 Task 4 加入；本任务不要提前 import，避免 `unused_import`。）

**(b)** 把 `_bodyCacheKeyForTurn`（`:259-273`）替换为：

```dart
  Object? _bodyCacheKeyForTurn(ThreadTurn turn) {
    final keys = <Object?>[
      // Editing dims every turn, so all cached bodies must rebuild when the
      // edit state starts / stops — not just the turn owning the message.
      _edit.editingMessageId,
      widget.onSwitchVersion != null,
      widget.onForkFrom != null,
      widget.onEditUserMessage != null,
    ];
    for (final id in turn.messageIds) {
      if (id == _edit.editingMessageId) keys.add('editing:$id');
      // A failed-delivery flip must refresh the "Retry" menu item.
      keys.add(widget.pendingDeliveryStatuses[id]);
      final version = widget.branches.turnOf(id);
      if (version != null) {
        keys.add(Object.hash(version.commit, version.index, version.count));
      }
    }
    return Object.hashAll(keys);
  }
```

**(c)** 在 `messageBuilder` 尾部：保留现有 `var result = tightenForRunning ? Theme(...) : messageChild;` 与 highlight ring 块，把最后的 `return result;` 替换为下面这段（**这是 Task 3 的最终代码**；`canEdit` / `handlers.onEdit` / `GestureDetector.onTap` / `_openMobileEdit` 由 Task 4 增量加入，本任务不要提前引用它们，否则编译不过）：

```dart
                          final mobileEditingId = mobile
                              ? _edit.editingMessageId
                              : null;
                          if (mobileEditingId != null) {
                            if (mobileEditingId != ai.id) {
                              result = IgnorePointer(
                                key: ValueKey('chat-message-dim:${ai.id}'),
                                ignoring: true,
                                child: Opacity(opacity: 0.28, child: result),
                              );
                            }
                            return result;
                          }
                          if (!mobile) return result;

                          final handlers = ChatMessageActionHandlers(
                            onRetry:
                                deliveryFailed &&
                                    widget.onRetryFailedMessage != null
                                ? () => widget.onRetryFailedMessage!(ai.id)
                                : null,
                            onFork:
                                version != null && widget.onForkFrom != null
                                ? () => widget.onForkFrom!(version.commit)
                                : null,
                            onPreviousVersion:
                                showsVersion &&
                                    previous != null &&
                                    widget.onSwitchVersion != null
                                ? () => widget.onSwitchVersion!(previous)
                                : null,
                            onNextVersion:
                                showsVersion &&
                                    next != null &&
                                    widget.onSwitchVersion != null
                                ? () => widget.onSwitchVersion!(next)
                                : null,
                          );
                          result = SelectionContainer.disabled(
                            child: GestureDetector(
                              key: ValueKey('chat-message-gestures:${ai.id}'),
                              behavior: HitTestBehavior.translucent,
                              onLongPressStart: (details) {
                                unawaited(
                                  showChatMessageActionMenu(
                                    context,
                                    globalPosition: details.globalPosition,
                                    message: ai,
                                    deliveryFailed: deliveryFailed,
                                    showsVersion: showsVersion,
                                    rewindEnabled:
                                        AiMessageInteractionScope.maybeRewindEnabled(
                                          context,
                                        ) ??
                                        !widget.turnInFlight,
                                    handlers: handlers,
                                  ),
                                );
                              },
                              child: result,
                            ),
                          );
                          return result;
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/pages/chat/session_history_thread_test.dart
```
Expected: PASS（含新增 3 个测试）。若 `long press opens the action menu` 失败且出现 "Select all"，说明长按识别器未胜出，按 spec 的备选方案把包装改成 `Listener` + `Timer(kLongPressTimeout)` 的确定性实现（本计划默认路径由测试验证为可行）。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && git add client/lib/pages/chat/session_history_thread.dart client/test/pages/chat/session_history_thread_test.dart && git commit -m "feat(chat): wire mobile long-press action menu into the history thread"
```

---

### Task 4: 阶段二 —— 点击用户气泡编辑 + 遮罩

**Files:**
- Modify: `client/lib/pages/chat/session_history_thread.dart`（`State` 方法区、`AiMessageView` 构造 `editing`/`onEdit`/`onSubmitEdit`、`messageBuilder` 尾部）
- Modify: `client/test/pages/chat/session_history_thread_test.dart`（`_harness` 扩展 + 新测试）

**Interfaces:**
- Consumes: `showChatMessageEditSheet`（Task 2）、`BranchEditController`（`openEditor` / `cancelEdit` / `begin` / `finish` / `editingMessageId` / `draft`）、`_isPureText`、`plainTextForCopy`。
- Produces: `Future<bool> _submitEdit(AiMessage message, String text)`、`Future<void> _openMobileEdit(BuildContext context, AiMessage message)`；dim 包装 key `chat-message-dim:${ai.id}`。

- [ ] **Step 1: Write the failing test**

在 `client/test/pages/chat/session_history_thread_test.dart` 顶部 import 增加：

```dart
import 'package:teampilot/services/chat/rewind/seat_branches.dart';
```

把 `_harness` 签名改为（保留原有全部参数，新增两个）：

```dart
Widget _harness({
  required AiThreadRuntime runtime,
  bool hasOlder = false,
  bool isLoadingOlder = false,
  SessionHistoryLiveChrome liveChrome = SessionHistoryLiveChrome.none,
  String? backgroundLabel,
  Future<void> Function()? onLoadOlder,
  ValueNotifier<String?>? visibleOwnerId,
  bool? mobilePerformanceMode,
  bool expandLatest = true,
  double width = 600,
  double height = 400,
  SeatBranches? branches,
  Future<bool> Function(String messageId, String text)? onEditUserMessage,
}) {
```

并在 `SessionHistoryThread(...)` 构造参数里加入：

```dart
          branches: branches ?? const SeatBranches.empty(),
          onEditUserMessage: onEditUserMessage,
```

在 `main()` 末尾追加：

```dart
  testWidgets('tapping a user bubble opens the edit sheet and dims other messages', (tester) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages(const [
        AiMessage(
          id: 'u1',
          role: AiRole.user,
          parts: [AiTextPart(text: 'first')],
        ),
        AiMessage(
          id: 'a1',
          role: AiRole.assistant,
          parts: [AiTextPart(text: 'answer')],
        ),
      ]);

    await tester.pumpWidget(
      _harness(
        runtime: store,
        mobilePerformanceMode: true,
        branches: const SeatBranches(
          turns: {
            'u1': SeatBranchVersion(
              index: 1,
              count: 1,
              commit: 'c1',
              siblings: ['c1'],
            ),
          },
        ),
        onEditUserMessage: (_, __) async => true,
      ),
    );
    await pumpUntilSettled(tester);

    await tester.tap(find.text('first'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('chat-edit-sheet-field')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('chat-edit-sheet-field')))
          .controller!
          .text,
      'first',
    );
    // Only the sheet owns a TextField: the inline editor stays off on mobile.
    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-message-dim:a1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('chat-message-dim:u1')),
      findsNothing,
    );
  });

  testWidgets('desktop keeps the inline editor instead of the bottom sheet', (tester) async {
    final store = ExternalStoreAiThreadRuntime()
      ..setMessages(const [
        AiMessage(
          id: 'u1',
          role: AiRole.user,
          parts: [AiTextPart(text: 'first')],
        ),
      ]);

    await tester.pumpWidget(
      _harness(
        runtime: store,
        mobilePerformanceMode: false,
        branches: const SeatBranches(
          turns: {
            'u1': SeatBranchVersion(
              index: 1,
              count: 1,
              commit: 'c1',
              siblings: ['c1'],
            ),
          },
        ),
        onEditUserMessage: (_, __) async => true,
      ),
    );
    await pumpUntilSettled(tester);

    await tester.tap(find.byTooltip('Edit message'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-edit-sheet-field')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('chat-message-dim:u1')), findsNothing);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/pages/chat/session_history_thread_test.dart --plain-name "tapping a user bubble opens the edit sheet"
```
Expected: FAIL —— `Expected: exactly one matching candidate, Actual: _KeyFinder:<zero widgets with key [<'chat-edit-sheet-field'>]>`（气泡尚无 `onTap`）。

- [ ] **Step 3: Write minimal implementation**

**(a)** 在 `client/lib/pages/chat/session_history_thread.dart` 的本地 import 区加入（与 `chat_message_action_menu.dart` 并列，保持字母序）：

```dart
import 'chat_message_edit_panel.dart';
```

**(b)** 在 `SessionHistoryThreadState` 方法区（紧接 `_bodyCacheKeyForTurn` 之后，约 `:274`）加入两个方法：

```dart
  Future<bool> _submitEdit(AiMessage message, String text) async {
    _edit.begin(
      messageId: message.id,
      text: text,
      visibleMessageIds: _messages.map((m) => m.id),
    );
    final accepted =
        await (widget.onEditUserMessage?.call(message.id, text) ??
            Future<bool>.value(true));
    if (!mounted) return accepted;
    _edit.finish(accepted: accepted, messageId: message.id);
    return accepted;
  }

  Future<void> _openMobileEdit(
    BuildContext context,
    AiMessage message,
  ) async {
    if (!mounted) return;
    final rewindEnabled =
        AiMessageInteractionScope.maybeRewindEnabled(context) ??
        !widget.turnInFlight;
    if (!rewindEnabled || _edit.editingMessageId == message.id) return;
    _edit.openEditor(message.id);
    final accepted = await showChatMessageEditSheet(
      context,
      initialText: _edit.draft ?? plainTextForCopy(message),
      title: context.l10n.edit.userMessage,
      cancelLabel: context.l10n.edit.cancel,
      sendLabel: context.l10n.edit.send,
      onSubmit: (text) => _submitEdit(message, text),
    );
    if (!mounted) return;
    if (!accepted && _edit.editingMessageId == message.id) {
      _edit.cancelEdit();
    }
  }
```

**(c)** 在 `AiMessageView(...)` 构造中（`:1323-1351`）把三处改为：

```dart
                            editing: !mobile && editing,
                            onEdit:
                                version == null ||
                                    widget.onEditUserMessage == null ||
                                    !_isPureText(ai)
                                ? null
                                : mobile
                                ? () => unawaited(_openMobileEdit(context, ai))
                                : () => _edit.openEditor(ai.id),
                            editLabel: editLabel,
                            onSubmitEdit: (text) => _submitEdit(ai, text),
```

把原来 `:1331-1351` 的 `onSubmitEdit: (text) async { ... }` 整块替换为上面的单行 `onSubmitEdit: (text) => _submitEdit(ai, text),`。

**(d)** 在 `messageBuilder` 尾部（Task 3 写入的代码）里：

- 把 `final handlers = ChatMessageActionHandlers(` 之前插入 `canEdit` 计算：
```dart
                          final canEdit =
                              ai.role == AiRole.user &&
                              _isPureText(ai) &&
                              version != null &&
                              widget.onEditUserMessage != null;
```
- 在 `ChatMessageActionHandlers(` 里 `onRetry:` 之后加入：
```dart
                            onEdit: canEdit
                                ? () => unawaited(_openMobileEdit(context, ai))
                                : null,
```
- 在 `GestureDetector(` 里 `onLongPressStart: (details) { ... },` 之后加入：
```dart
                              onTap: canEdit
                                  ? () => unawaited(_openMobileEdit(context, ai))
                                  : null,
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart test/pages/chat/session_history_thread_test.dart
```
Expected: PASS（含 Task 3 的 3 个 + 本任务 2 个新测试）。

- [ ] **Step 5: Commit**

```bash
cd /home/hhoa/git/hhoa/teampilot && git add client/lib/pages/chat/session_history_thread.dart client/test/pages/chat/session_history_thread_test.dart && git commit -m "feat(chat): add mobile tap-to-edit sheet with dimmed transcript"
```

---

### Task 5: 全量验证与收尾

**Files:** 无新增；仅验证与修复。

- [ ] **Step 1: Analyze 全量**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && flutter analyze --no-fatal-infos --no-fatal-warnings
```
Expected: `No issues found!`（或只剩预先存在改动带来的 info/warning，且 `--no-fatal-*` 使其不阻断）。

- [ ] **Step 2: 三个新测试文件 + 改动测试文件一起跑**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart test/pages/chat/chat_message_action_menu_test.dart test/pages/chat/chat_message_edit_panel_test.dart test/pages/chat/session_history_thread_test.dart
```
Expected: 全绿。

- [ ] **Step 3: 全量测试（后台，仅一次）**

Run（后台执行，等完成通知后再读结果）:
```bash
cd /home/hhoa/git/hhoa/teampilot/client && dart run tool/run_tests.dart
```
Expected: 全绿。若有失败，定位是否是预先存在的未提交改动导致；只修复本计划引入的回归，不要改动他人未提交代码。

- [ ] **Step 4: 确认提交范围**

Run:
```bash
cd /home/hhoa/git/hhoa/teampilot && git log --oneline -5 && git status --short
```
Expected: 能在 `git log` 里找到本计划 Task 1-4 的 4 个 commit；`git status --short` 里仍保留其它并行工作留下的未提交/未跟踪改动，**且本计划的 6 个文件都不再出现在未提交列表里**。注意：仓库中可能有其它 agent 并行提交，最近几条 commit 不一定全是本计划的。

- [ ] **Step 5: 设备/模拟器目视检查（人工）**

在 Android 或 iOS 上确认：
1. 长按任意消息气泡 → 弹出功能菜单，系统「复制/全选」文字选择工具栏不出现。
2. 菜单「复制」「导出 Markdown」写入剪贴板并出现 `Copied` toast；「编辑」「从此 fork」「重试」「版本切换」按条件出现/禁用。
3. 点击用户气泡 → 底部出现编辑面板（预填原文）、其余消息压暗、被点气泡保持高亮；键盘弹起时面板在键盘上方。
4. 发送成功后面板关闭、遮罩复原；取消/点空白处关闭面板后遮罩复原。
5. 桌面端：hover 按钮行与行内编辑器行为与改动前一致。

---

## Self-Review（对照 spec）

**1. Spec coverage**

| Spec 要求 | 任务 |
|-----------|------|
| 仅 Android/iOS 门控、桌面不变 | Global Constraints、Task 3/4（`if (!mobile) return result;` 与 `editing: !mobile && ...`） |
| 长按气泡弹菜单、禁用长按选字 | Task 3（`SelectionContainer.disabled` + `GestureDetector.onLongPressStart`） |
| 菜单项与 action bar 对齐（重试/复制/编辑/fork/版本/导出） | Task 1 `buildChatMessageActionSpecs` |
| 启用条件 `rewindEnabled`、打开时读 scope | Task 3 `maybeRewindEnabled(context)` |
| 复制/导出写剪贴板 + toast | Task 1 `copy()` + 注入的 writer/feedback |
| 复用 `TpActionMenu` | Task 1 `showTpActionMenuFromSpecs` |
| 点击用户气泡 → 底部编辑面板 | Task 2 + Task 4 `onTap` / `_openMobileEdit` |
| 三个编辑入口统一 | Task 4 `onEdit` 移动端点按、`onTap`、菜单 `onEdit` 都指向 `_openMobileEdit` |
| 提交复用 `onEditUserMessage` | Task 4 `_submitEdit` |
| 失败保留草稿 | Task 2 面板 + `_submitEdit` 的 `_edit.finish` |
| 其余消息遮罩、被点气泡高亮 | Task 3 `chat-message-dim:` 的 `IgnorePointer + Opacity(0.28)` |
| 移动端不出现两个编辑框 | Task 4 `editing: !mobile && editing` |
| 缓存 key 补 delivery status / 全局编辑态 | Task 3 `_bodyCacheKeyForTurn` |
| 不新增 l10n 键 | Global Constraints + Task 1 复用现有键 |
| 不动 vendored 包 / composer / `SessionChatView` | 文件清单 |
| 测试与完成前 analyze + 全量测试 | Task 1/2/3/4 各自 TDD + Task 5 |

无遗漏。

**2. Placeholder scan** — 无 `TBD` / `TODO` / "implement later" / "similar to Task N" / 无代码的步骤。所有代码步骤都有完整 Dart 代码块与确切命令。

**3. Type consistency**

- `showChatMessageActionMenu(BuildContext context, {...})` 与 `showChatMessageEditSheet(BuildContext context, {...})` 在 Task 1/2 定义、Task 3/4 以位置参数 `context` 调用，一致。
- `ChatMessageActionHandlers` 字段名在 Task 1 定义、Task 3/4 使用，一致。
- `ChatMessageClipboardWriter` 在 Task 1 定义、Task 1 测试使用，一致。
- `_submitEdit(AiMessage, String)` 与 `_openMobileEdit(BuildContext, AiMessage)` 在 Task 4 (a) 定义、Task 4 (b)(c) 调用，一致。
- `chat-message-gestures:${ai.id}` / `chat-message-dim:${ai.id}` / `chat-edit-sheet-*` key 在定义与测试间一致。
- Task 3 (c) 的临时版本（无 `onEdit` / 无 `onTap`）与 Task 4 (c) 的增量修改顺序一致，且 Task 3 的测试不依赖 `onTap`。

**与 spec 的两处有意细化（不改变行为意图）：**

1. 剪贴板写入与 toast 通过参数注入（默认仍是 `Clipboard.setData` / `AppToast.show`），使 Task 1 的测试不需要 mock platform channel，符合 `AGENTS.md` 的"边界注入"测试约定；spec 中写的 "mock platform channel" 由等价的注入断言替代。
2. 菜单在 rewind 组两侧加分隔线；纯消息仍是 2 项菜单，顺序与 action bar 一致。
