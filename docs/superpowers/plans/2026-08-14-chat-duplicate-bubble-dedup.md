# 单条消息双气泡：兜底去重与取证日志 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `AiHistorySeat` 发布消息到 runtime 前做防御性去重（同 id / 同文本 assistant 双份），并记录取证日志，消除"单条消息显示成两个气泡"的症状、为下次复现定位真凶。

**Architecture:** 新增纯函数 `dedupeAiHistoryMessages`（`services/session/ai_history_message_dedup.dart`），在 seat 的 `_applyMessages` / `_applySoftReloadMessages` 两处 annotate 之后、写入 `_allMessages` 之前调用；去重触发时打 `appLogger.w`（带会话/member/cli/来源/消息详情），同指纹防刷屏。

**Tech Stack:** Dart / Flutter, flutter_bloc cubit（`AiHistorySeat`）, `ai_message_core`（`AiMessage`/`AiTextPart`/`AiToolCallPart`/`AiReasoningPart`）, `appLogger`。

## Global Constraints

- 依据 spec：`docs/superpowers/specs/2026-08-14-chat-duplicate-bubble-dedup-design.md`。
- 去重规则：① 同 id 保留最后一次；② assistant 且**文本 part 完全相同**（`AiTextPart.text` 拼接比较，不含 reasoning/tool；全列表扫描）的对：工具结果数严格多者胜 → 非文本 part 超集者胜 → 完全相同保留第一条；③ **user 消息不做文本去重**。
- 判定签名只含文本 part；不用 `messageContentIdentity`。
- 日志级别 `w`，前缀 `[ai-history] duplicate-messages`；同一 seat 相同重复指纹只打一次。
- 不改 loader / refresher / viewport / runtime。
- 仓库规范：不加注释除非必要；无 `print`；`flutter analyze --no-fatal-infos --no-fatal-warnings` 与相关测试通过后再 commit。

---

### Task 1: 纯函数 `dedupeAiHistoryMessages` + 单元测试

**Files:**
- Create: `client/lib/services/session/ai_history_message_dedup.dart`
- Test: `client/test/services/session/ai_history_message_dedup_test.dart`

**Interfaces:**
- Produces:
  - `class AiHistoryDedupResult { final List<AiMessage> messages; final List<AiMessage> removed; }`（`messages` = 去重后的新列表；`removed` = 被丢弃的消息，按原列表顺序）
  - `AiHistoryDedupResult dedupeAiHistoryMessages(List<AiMessage> messages)` — 纯函数，无副作用。
- Consumes: `AiMessage` / `AiTextPart` / `AiToolCallPart` / `AiReasoningPart` from `package:ai_message_core/ai_message_core.dart`。

- [ ] **Step 1: 写失败测试**

`client/test/services/session/ai_history_message_dedup_test.dart`：

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/session/ai_history_message_dedup.dart';

AiMessage _msg(
  String id, {
  AiRole role = AiRole.assistant,
  List<String> texts = const [],
  List<AiToolCallPart> tools = const [],
  List<String> reasoning = const [],
}) {
  return AiMessage(
    id: id,
    role: role,
    parts: [
      for (final t in texts) AiTextPart(text: t),
      for (final r in reasoning) AiReasoningPart(text: r),
      ...tools,
    ],
  );
}

AiToolCallPart _tool(
  String callId, {
  Object? result,
  String name = 'question',
}) {
  return AiToolCallPart(
    toolCallId: callId,
    toolName: name,
    status: result == null
        ? AiToolCallStatus.incomplete
        : AiToolCallStatus.complete,
    result: result,
  );
}

void main() {
  test('same id twice keeps the last occurrence', () {
    final pending = _msg('asst-1', texts: ['prose'], tools: [_tool('c1')]);
    final completed = _msg(
      'asst-1',
      texts: ['prose'],
      tools: [_tool('c1', result: 'answer')],
    );
    final result = dedupeAiHistoryMessages([pending, completed]);

    expect(result.messages, hasLength(1));
    expect(result.messages.single.id, 'asst-1');
    expect(
      (result.messages.single.parts.whereType<AiToolCallPart>().single).result,
      'answer',
      reason: '同 id 保留最后一次（内容最新）',
    );
    expect(result.removed, [pending]);
  });

  test('same text, different ids, tool result asymmetry keeps the completed one',
      () {
    final pending = _msg('asst-a', texts: ['prose'], tools: [_tool('c1')]);
    final completed = _msg(
      'asst-b',
      texts: ['prose'],
      tools: [_tool('c1', result: 'answer')],
    );
    final result = dedupeAiHistoryMessages([pending, completed]);

    expect(result.messages, hasLength(1));
    expect(result.messages.single.id, 'asst-b');
    expect(result.removed, [pending]);
  });

  test('same text, different ids, part superset keeps the larger message', () {
    final small = _msg(
      'asst-a',
      texts: ['prose'],
      reasoning: ['r1'],
      tools: [_tool('c1', result: 'o1')],
    );
    final large = _msg(
      'asst-b',
      texts: ['prose'],
      reasoning: ['r1', 'r2'],
      tools: [_tool('c1', result: 'o1'), _tool('c2', result: 'o2')],
    );
    final result = dedupeAiHistoryMessages([small, large]);

    expect(result.messages, hasLength(1));
    expect(result.messages.single.id, 'asst-b');
    expect(result.removed, [small]);
  });

  test('completely identical assistant messages keep the first', () {
    final a = _msg('asst-a', texts: ['prose'], tools: [_tool('c1')]);
    final b = _msg('asst-b', texts: ['prose'], tools: [_tool('c1')]);
    final result = dedupeAiHistoryMessages([a, b]);

    expect(result.messages, hasLength(1));
    expect(result.messages.single.id, 'asst-a');
    expect(result.removed, [b]);
  });

  test('legitimate duplicate USER messages are kept', () {
    final a = _msg(
      'u1',
      role: AiRole.user,
      texts: ['没问题'],
    );
    final b = _msg(
      'u2',
      role: AiRole.user,
      texts: ['没问题'],
    );
    final result = dedupeAiHistoryMessages([a, b]);

    expect(result.messages, hasLength(2));
    expect(result.removed, isEmpty);
  });

  test('tool-only assistant messages are never deduped (empty text signature)',
      () {
    final a = _msg('asst-a', tools: [_tool('c1')]);
    final b = _msg('asst-b', tools: [_tool('c2')]);
    final result = dedupeAiHistoryMessages([a, b]);

    expect(result.messages, hasLength(2));
    expect(result.removed, isEmpty);
  });

  test('messages with different text parts are kept', () {
    final a = _msg('asst-a', texts: ['prose one']);
    final b = _msg('asst-b', texts: ['prose two']);
    final result = dedupeAiHistoryMessages([a, b]);

    expect(result.messages, hasLength(2));
    expect(result.removed, isEmpty);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/services/session/ai_history_message_dedup_test.dart`
Expected: FAIL，编译错误（`ai_history_message_dedup.dart` 不存在）。

- [ ] **Step 3: 实现纯函数**

`client/lib/services/session/ai_history_message_dedup.dart`：

```dart
import 'package:ai_message_core/ai_message_core.dart';

/// 去重结果：去重后的消息列表 + 被丢弃的消息（按原列表顺序）。
class AiHistoryDedupResult {
  const AiHistoryDedupResult({required this.messages, required this.removed});

  final List<AiMessage> messages;
  final List<AiMessage> removed;
}

/// Live 列表兜底去重（spec 2026-08-14）：
/// 1. 同 id → 保留最后一次出现；
/// 2. assistant 且文本 part 拼接完全相同的任意对：
///    - 工具结果数严格多者胜；
///    - 否则非文本 part 集合为超集者胜；
///    - 完全相同 → 保留第一条；
///    - 无法判定 → 两条都保留；
/// 3. user 消息不做文本去重（跨时间合法重复）。
/// 判定签名只含文本 part，不含 reasoning/tool。
AiHistoryDedupResult dedupeAiHistoryMessages(List<AiMessage> messages) {
  if (messages.length < 2) {
    return AiHistoryDedupResult(messages: messages, removed: const []);
  }
  final removed = <String>{};

  // Pass 1: 同 id 保留最后一次。
  final lastById = <String, int>{};
  for (var i = 0; i < messages.length; i++) {
    lastById[messages[i].id] = i;
  }
  final seenIds = <String>{};
  for (var i = 0; i < messages.length; i++) {
    final id = messages[i].id;
    if (seenIds.contains(id) || lastById[id] != i) {
      removed.add(id);
      continue;
    }
    seenIds.add(id);
  }

  // Pass 2: assistant 同文本对（按文本签名分组）。
  final groups = <String, List<int>>{};
  for (var i = 0; i < messages.length; i++) {
    final m = messages[i];
    if (m.role != AiRole.assistant) continue;
    if (removed.contains(m.id)) continue;
    final signature = _textSignature(m);
    if (signature.isEmpty) continue;
    groups.putIfAbsent(signature, () => []).add(i);
  }
  for (final group in groups.values) {
    for (var a = 0; a < group.length; a++) {
      for (var b = a + 1; b < group.length; b++) {
        final ia = group[a];
        final ib = group[b];
        if (removed.contains(messages[ia].id) ||
            removed.contains(messages[ib].id)) {
          continue;
        }
        final winner = _betterAssistant(messages[ia], messages[ib]);
        if (winner == 1) {
          removed.add(messages[ib].id);
        } else if (winner == 2) {
          removed.add(messages[ia].id);
        }
      }
    }
  }

  if (removed.isEmpty) {
    return AiHistoryDedupResult(messages: messages, removed: const []);
  }
  final out = <AiMessage>[
    for (final m in messages)
      if (!removed.contains(m.id)) m,
  ];
  final dropped = <AiMessage>[
    for (final m in messages)
      if (removed.contains(m.id)) m,
  ];
  return AiHistoryDedupResult(messages: out, removed: dropped);
}

/// 0 = 无法判定（都保留）; 1 = 保留 a; 2 = 保留 b。
int _betterAssistant(AiMessage a, AiMessage b) {
  final aResults = a.parts
      .whereType<AiToolCallPart>()
      .where((t) => t.result != null)
      .length;
  final bResults = b.parts
      .whereType<AiToolCallPart>()
      .where((t) => t.result != null)
      .length;
  if (aResults != bResults) {
    return aResults > bResults ? 1 : 2;
  }
  final aParts = _nonTextPartSet(a.parts);
  final bParts = _nonTextPartSet(b.parts);
  final aSubset = aParts.isNotEmpty && aParts.difference(bParts).isEmpty;
  final bSubset = bParts.isNotEmpty && bParts.difference(aParts).isEmpty;
  if (aSubset != bSubset) return aSubset ? 2 : 1;
  if (aSubset && aParts.length == bParts.length) return 1;
  return 0;
}

String _textSignature(AiMessage m) {
  final buffer = StringBuffer();
  for (final part in m.parts) {
    if (part is AiTextPart) {
      buffer.write(part.text);
      buffer.write('\u0000');
    }
  }
  return buffer.toString();
}

Set<String> _nonTextPartSet(List<AiMessagePart> parts) {
  final out = <String>{};
  for (final part in parts) {
    switch (part) {
      case AiReasoningPart(:final text):
        out.add('r:$text');
      case AiToolCallPart(:final toolCallId, :final toolName):
        out.add('t:$toolCallId:$toolName');
      default:
        break;
    }
  }
  return out;
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/services/session/ai_history_message_dedup_test.dart`
Expected: PASS（7 tests）。

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/session/ai_history_message_dedup.dart \
        client/test/services/session/ai_history_message_dedup_test.dart
git commit -m "feat(history): dedup live messages (same id / identical assistant text) before publish"
```

---

### Task 2: seat 接入 `_dedupeLiveMessages` + 取证日志 + seat 级测试

**Files:**
- Modify: `client/lib/cubits/ai_history_seat.dart`（import + `_applyMessages` 两处调用 + 新增私有方法 + 字段）
- Test: `client/test/cubits/ai_history_seat_dedup_test.dart`（新建，harness 参考 `ai_history_seat_no_blank_test.dart`）

**Interfaces:**
- Consumes: `dedupeAiHistoryMessages` / `AiHistoryDedupResult`（Task 1）；`appLogger`（`../utils/logging/logger.dart` 已导入）；`_lastCli`（`CliTool?`，seat 字段）。
- Produces: seat 私有方法 `List<AiMessage> _dedupeLiveMessages(List<AiMessage> messages, {required String sessionId, required String memberId, required String source})`；字段 `String? _lastDedupeLogFingerprint`。

- [ ] **Step 1: 写失败测试**

`client/test/cubits/ai_history_seat_dedup_test.dart`（完整 harness 复制自 `ai_history_seat_no_blank_test.dart` 的 `_HolderAdapter` / `_ScriptedLocator` / `session()` / `ctx()` / `setUp` / `tearDown`，并新增以下测试）：

```dart
import 'package:ai_message_core/ai_message_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_seat.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_launch_context.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/session/ai_history_locator.dart';
import 'package:teampilot/services/session/session_history_context.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/utils/logging/logger.dart';

import '../support/fake_ai_history_registry.dart';
import '../support/post_frame_test_harness.dart';

class _HolderAdapter implements AiTranscriptAdapter {
  _HolderAdapter(this.messages);
  final List<AiMessage> Function() messages;

  @override
  String get id => 'claude';

  @override
  Future<List<AiMessage>> parse(AiTranscriptBundle bundle) async =>
      List.of(messages());
}

class _ScriptedLocator extends AiHistoryLocator {
  bool emitBundle = false;

  @override
  Future<AiTranscriptBundle?> locate({
    required SessionHistoryContext ctx,
    required CliTool cli,
  }) async {
    if (!emitBundle) return null;
    return const AiTranscriptBundle(
      adapterId: 'claude',
      fragments: [AiTranscriptFragment(name: 'canned.jsonl', bytes: [])],
    );
  }
}

AiToolCallPart _tool(String callId, {Object? result, String name = 'question'}) {
  return AiToolCallPart(
    toolCallId: callId,
    toolName: name,
    status:
        result == null ? AiToolCallStatus.incomplete : AiToolCallStatus.complete,
    result: result,
  );
}

void main() {
  late _ScriptedLocator locator;
  late List<AiMessage> holderMessages;
  late String cacheToken;
  late AiHistoryLoader loader;
  late AiHistorySeat seat;

  void bumpCacheToken() =>
      cacheToken = 'token-${cacheToken.hashCode.abs()}-${holderMessages.length}';

  AppSession session() => AppSession(
    sessionId: 'sess-a',
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work/project')],
    cli: CliTool.claude,
    createdAt: 1,
  );

  WorkspaceLaunchContext ctx(AppSession s) => WorkspaceLaunchContext(
    session: s,
    workspace: Workspace(
      workspaceId: s.workspaceId,
      folders: s.folders,
      createdAt: 0,
    ),
  );

  setUp(() {
    setUpTestAppStorage();
    holderMessages = const [];
    cacheToken = 'token-1';
    locator = _ScriptedLocator()..emitBundle = true;
    final fs = LocalFilesystem();
    loader = AiHistoryLoader(
      contextBuilder: const SessionHistoryContextBuilder(),
      resolveWorkContext: (_, {String? memberId}) async => RuntimeContext(
        target: RuntimeTarget.local(),
        filesystem: fs,
        home: '/tmp/history-seat-dedup',
        cwd: '/tmp/history-seat-dedup',
        appDataRoot: '/tmp/history-seat-dedup',
        paths: AppPaths('/tmp/history-seat-dedup'),
      ),
      locator: locator,
      registry: fakeAiHistoryRegistry(
        cli: CliTool.claude,
        adapter: _HolderAdapter(() => holderMessages),
      ),
      resolveCacheToken: (_) async => cacheToken,
    );
    seat = AiHistorySeat(loader: loader);
  });

  tearDown(() async {
    await seat.close();
    tearDownTestAppStorage();
  });

  test('duplicate assistant pair in the live list publishes only the winner',
      () async {
    holderMessages = [
      AiMessage(
        id: 'u1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'question?')],
      ),
      AiMessage(
        id: 'asst-pending',
        role: AiRole.assistant,
        parts: [
          const AiTextPart(text: "I've traced the full back-navigation path"),
          _tool('call_q1'),
        ],
      ),
      AiMessage(
        id: 'asst-completed',
        role: AiRole.assistant,
        parts: [
          const AiTextPart(text: "I've traced the full back-navigation path"),
          _tool('call_q1', result: '{"answers":[]}'),
        ],
      ),
    ];
    await seat.load(session: session(), memberId: '', launchContext: ctx(session()));

    expect(seat.runtime.messages, hasLength(2));
    expect(
      seat.runtime.messages.map((m) => m.id),
      ['u1', 'asst-completed'],
      reason: '同文本 pending/completed 双份只发布 completed 版',
    );
  });

  test('duplicate pair logs [ai-history] duplicate-messages once per fingerprint',
      () async {
    final before = await AppLogger.instance.getPendingLogLines();
    holderMessages = [
      AiMessage(
        id: 'u1',
        role: AiRole.user,
        parts: const [AiTextPart(text: 'question?')],
      ),
      AiMessage(
        id: 'asst-pending',
        role: AiRole.assistant,
        parts: [
          const AiTextPart(text: 'same prose'),
          _tool('call_q1'),
        ],
      ),
      AiMessage(
        id: 'asst-completed',
        role: AiRole.assistant,
        parts: [
          const AiTextPart(text: 'same prose'),
          _tool('call_q1', result: 'answer'),
        ],
      ),
    ];
    await seat.load(session: session(), memberId: '', launchContext: ctx(session()));

    var lines = await AppLogger.instance.getPendingLogLines();
    final firstLogs = lines.skip(before.length).where(
      (l) => l.contains('[ai-history] duplicate-messages'),
    );
    expect(firstLogs, hasLength(1), reason: '去重触发必须打日志');

    // 同指纹再次出现（soft reload 同列表）→ 不再打。
    bumpCacheToken();
    await seat.softReload();
    lines = await AppLogger.instance.getPendingLogLines();
    final secondLogs = lines.skip(before.length).where(
      (l) => l.contains('[ai-history] duplicate-messages'),
    );
    expect(secondLogs, hasLength(1), reason: '相同重复指纹防刷屏，只打一次');
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/cubits/ai_history_seat_dedup_test.dart`
Expected: FAIL（seat 尚未去重：`hasLength(2)` 实际为 3；日志未出现）。

- [ ] **Step 3: 实现 seat 接入**

`client/lib/cubits/ai_history_seat.dart`：

(a) import（第 14 行 `ai_history_loader.dart` 之后）：

```dart
import '../services/session/ai_history_message_dedup.dart';
```

(b) 新增字段（`_lastMailboxRecords` 声明附近）：

```dart
  /// 最近一次重复去重日志的指纹（session|member|removed ids|kept 数），
  /// 相同指纹不重复打日志（防刷屏）。
  String? _lastDedupeLogFingerprint;
```

(c) `_applyMessages`（第 759-760 行，`_cancelTipHoldTimer();` 之前）：

```dart
    messages = _dedupeLiveMessages(
      messages,
      sessionId: sessionId,
      memberId: memberId,
      source: 'applyMessages',
    );
    _cancelTipHoldTimer();
```

(d) `_applySoftReloadMessages`（第 783-784 行，`final oldLength` 之前）：

```dart
    messages = _dedupeLiveMessages(
      messages,
      sessionId: sessionId,
      memberId: memberId,
      source: 'applySoftReloadMessages',
    );
    final oldLength = _allMessages.length;
```

(e) 新增私有方法（放在 `_applySoftReloadMessages` 之后、`_commitThroughLatestUser` 之前）：

```dart
  /// 发布前的兜底去重 + 取证日志。规则见
  /// [dedupeAiHistoryMessages]；命中时打一条 `w` 级日志，
  /// 相同重复指纹只打一次。
  List<AiMessage> _dedupeLiveMessages(
    List<AiMessage> messages, {
    required String sessionId,
    required String memberId,
    required String source,
  }) {
    final result = dedupeAiHistoryMessages(messages);
    if (result.removed.isEmpty) return messages;
    final fingerprint = '$sessionId\u0000$memberId\u0000'
        '${result.removed.map((m) => m.id).join(',')}\u0000'
        '${result.messages.length}';
    if (fingerprint == _lastDedupeLogFingerprint) return result.messages;
    _lastDedupeLogFingerprint = fingerprint;
    final cli = _lastCli;
    final preview = result.removed
        .map((m) {
          final text = m.parts
              .whereType<AiTextPart>()
              .map((p) => p.text)
              .join(' ')
              .trim();
          final tools = m.parts
              .whereType<AiToolCallPart>()
              .map(
                (t) =>
                    '${t.toolName}(${t.result != null ? 'result' : 'pending'})',
              )
              .join(',');
          final shown =
              text.length > 80 ? '${text.substring(0, 80)}…' : text;
          return '${m.id}[${m.role.name}] text=$shown tools=$tools';
        })
        .join(' | ');
    appLogger.w(
      '[ai-history] duplicate-messages session=$sessionId member=$memberId '
      'cli=${cli?.name ?? '?'} source=$source '
      'kept=${result.messages.length} removed=$preview',
    );
    return result.messages;
  }
```

- [ ] **Step 4: 运行确认通过**

Run:
```bash
flutter test test/cubits/ai_history_seat_dedup_test.dart
flutter test test/cubits/ai_history_seat_no_blank_test.dart test/cubits/ai_history_seat_isolation_test.dart test/cubits/ai_history_seat_side_attachment_reload_test.dart
```
Expected: 新测试 + 既有 seat 测试全部 PASS。

- [ ] **Step 5: 分析 + 提交**

Run: `flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无新增 error/warning（文件原有警告除外）。

```bash
git add client/lib/cubits/ai_history_seat.dart \
        client/test/cubits/ai_history_seat_dedup_test.dart
git commit -m "feat(history): dedup + forensics log for live duplicate bubbles"
```

---

## 收尾验证

- [ ] 全量相关套件：`flutter test test/services/session/ test/cubits/` 通过。
- [ ] `flutter analyze --no-fatal-infos --no-fatal-warnings` 无新增问题。
- [ ] 复现验证：下次用户看到重复气泡时，日志中出现 `[ai-history] duplicate-messages`（含消息 id / 文本 / 工具状态 / 来源路径），据此定位真凶。
