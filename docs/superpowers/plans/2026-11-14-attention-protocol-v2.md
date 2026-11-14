# Attention 事件日志与协议 v2 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把远程 idle 通知从“实时广播、断了就丢”改成“authority 持久日志 + 客户端游标补发 + eventId 幂等”，协议直接升到 v2。

**Architecture:** `SessionAuthority` 把每一条 attention 先写入 `AttentionLog`（内存索引 + 每 epoch 一个 JSONL 文件），再通过 `attention.log.v1` 的 `events` 帧发给客户端。客户端 `SessionClient` 在 `hello` 里带游标，服务端从游标之后补发；`AttentionInbox` 用 `eventId` 去重、持久化游标、驱动现有 `SessionIdleNotificationService`。

**Tech Stack:** Dart 3 / Flutter、`Filesystem` 抽象（`InMemoryFilesystem` 测试）、`uuid` v7、现有 `SessionFrameDecoder`、`dart run tool/run_tests.dart`。

**Spec:** `docs/superpowers/specs/2026-11-14-attention-event-pipeline-design.md`

## Global Constraints

- 不做向下/向后兼容：`sessionProtocolVersion = 2`，删除旧 `attention` / `attentionAck`。
- `seq` 只能由 authority 的 `AttentionLog` 分配，同一 `(authorityId, epoch)` 内严格单调。
- `eventId` 是唯一幂等键；重复投递不得重复通知。
- 所有纯 Dart 测试必须用 `cd client && dart run tool/run_tests.dart <paths>`；禁止直接 `flutter test`。
- 诊断日志用 `appLogger`，禁止 `print`。
- 用户可见文案走现有 slang l10n；本计划不新增文案。
- 只改本计划列出的文件；不要动工作区里无关的未提交修改。
- 每个任务结束单独 commit，只 `git add` 该任务列出的文件。

---

## File Structure

### New files

| 文件 | 职责 |
|---|---|
| `client/lib/services/attention/attention_event.dart` | `AttentionKind` / `AttentionEvent` 领域模型与 JSON |
| `client/lib/services/attention/attention_cursor.dart` | `AttentionCursor`（authorityId + epoch + seq） |
| `client/lib/services/attention/attention_batch.dart` | `AttentionBatch`（一次 `events` 帧） |
| `client/lib/services/attention/attention_log.dart` | authority 侧 append-only 日志、seq 分配、保留、文件加载 |
| `client/lib/services/attention/attention_cursor_store.dart` | 客户端游标 + 最近 eventId 的持久化 |
| `client/lib/services/attention/attention_inbox.dart` | 客户端去重、推进游标、`fresh` 流 |

### Modified files

| 文件 | 改动 |
|---|---|
| `client/lib/services/storage/app_paths.dart` | `attention/log-<epoch>.jsonl`、`attention/cursors.json` 路径 |
| `client/lib/services/session_protocol/session_envelope.dart` | 协议版本 2、`events`/`ack`、`events` channel |
| `client/lib/services/session_protocol/session_models.dart` | 删除 `SessionAttention` |
| `client/lib/services/session_protocol/session_authority.dart` | 注入 `AttentionLog`、异步 `publishAttention`、暴露 `attentionLog` |
| `client/lib/services/session_protocol/session_server.dart` | hello 游标、`helloAck` 范围、backlog + live 合并、`ack` |
| `client/lib/services/session_protocol/session_client.dart` | hello 游标、`events` 回调、`sendAttentionAck` |
| `client/lib/services/session_sync/chat_session_activity_source.dart` | 不再自己生成 id，改为 `publishAttention` |
| `client/lib/services/session_sync/session_protocol_controller.dart` | 注入 `AttentionInbox`、按 homeId 消费、ack |
| `client/lib/app/session_protocol_home.dart` | `applyClient(homeId: ...)` |
| `client/lib/app/bootstrap/session_runtime_wiring.dart` | 打开 log、创建 cursor store/inbox、订阅 `fresh` |
| `client/lib/app/app_shell.dart` | `await wireSessionRuntime(...)`、传入 device storage、teardown |
| `client/test/services/session_protocol/session_server_client_test.dart` | v2 端到端 + 重连补发 + epoch + gap |

### Test files

- `client/test/services/attention/attention_event_test.dart`
- `client/test/services/attention/attention_log_test.dart`
- `client/test/services/attention/attention_cursor_store_test.dart`
- `client/test/services/attention/attention_inbox_test.dart`

### Explicitly not in this plan

- 本地 idle 通知路径的完全统一（`SessionIdleNotificationListener` → inbox）。本计划只把远程路径接到 inbox；本地路径保持现状，避免和现有桌面通知行为打架。
- Android 前台服务 / push。见 spec 的 Phase 2 / 3。
- 旧 epoch 日志文件的自动清理。本计划只保证每个文件最多 `maxEvents` 条。

---

### Task 1: Attention 领域模型

**Files:**
- Create: `client/lib/services/attention/attention_event.dart`
- Create: `client/lib/services/attention/attention_cursor.dart`
- Create: `client/lib/services/attention/attention_batch.dart`
- Test: `client/test/services/attention/attention_event_test.dart`

**Interfaces:**
- Produces: `AttentionKind`, `AttentionEvent`, `AttentionCursor`, `AttentionBatch` 及其 `toJson` / `fromJson`。
- Later tasks use `AttentionEvent.seq`, `.eventId`, `.sessionId`, `.kind`, `.occurredAt`, `.expiresAt.isAfter(now)`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/attention/attention_batch.dart';
import 'package:teampilot/services/attention/attention_cursor.dart';
import 'package:teampilot/services/attention/attention_event.dart';

void main() {
  test('AttentionEvent round-trips through JSON', () {
    final occurred = DateTime.utc(2026, 11, 14, 10, 30);
    final event = AttentionEvent(
      eventId: 'evt-1',
      authorityId: 'desk',
      epoch: 7,
      seq: 3,
      sessionId: 's1',
      memberId: 'dev',
      turnId: 'turn-1',
      workspaceId: 'ws1',
      kind: AttentionKind.idle,
      occurredAt: occurred,
      expiresAt: occurred.add(const Duration(days: 7)),
      title: 'Build finished',
      message: 'Ready',
      payload: const {'reason': 'turn.completed'},
    );

    final decoded = AttentionEvent.fromJson(event.toJson());

    expect(decoded, isNotNull);
    expect(decoded!.eventId, 'evt-1');
    expect(decoded.authorityId, 'desk');
    expect(decoded.epoch, 7);
    expect(decoded.seq, 3);
    expect(decoded.sessionId, 's1');
    expect(decoded.memberId, 'dev');
    expect(decoded.turnId, 'turn-1');
    expect(decoded.workspaceId, 'ws1');
    expect(decoded.kind, AttentionKind.idle);
    expect(decoded.occurredAt, occurred);
    expect(decoded.expiresAt, occurred.add(const Duration(days: 7)));
    expect(decoded.title, 'Build finished');
    expect(decoded.message, 'Ready');
    expect(decoded.payload, {'reason': 'turn.completed'});
  });

  test('AttentionEvent rejects missing identity or seq', () {
    expect(AttentionEvent.fromJson(const {}), isNull);
    expect(
      AttentionEvent.fromJson(const {
        'eventId': 'evt-1',
        'authorityId': 'desk',
        'sessionId': 's1',
        'kind': 'idle',
        'epoch': 7,
        'seq': 0,
      }),
      isNull,
    );
  });

  test('AttentionCursor advances only forward in the same epoch', () {
    const cursor = AttentionCursor(authorityId: 'desk', epoch: 7, seq: 3);
    final event = AttentionEvent(
      eventId: 'evt-4',
      authorityId: 'desk',
      epoch: 7,
      seq: 4,
      sessionId: 's1',
      memberId: 'dev',
      kind: AttentionKind.idle,
      occurredAt: DateTime.utc(2026, 11, 14),
      expiresAt: DateTime.utc(2026, 11, 21),
    );

    expect(cursor.advance(event).seq, 4);
    expect(cursor.advance(event).advance(event).seq, 4);
    expect(
      cursor
          .advance(
            AttentionEvent(
              eventId: 'evt-new-epoch',
              authorityId: 'desk',
              epoch: 8,
              seq: 1,
              sessionId: 's1',
              memberId: 'dev',
              kind: AttentionKind.idle,
              occurredAt: DateTime.utc(2026, 11, 14),
              expiresAt: DateTime.utc(2026, 11, 21),
            ),
          )
          .epoch,
      8,
    );
  });

  test('AttentionBatch round-trips through JSON', () {
    final occurred = DateTime.utc(2026, 11, 14);
    final batch = AttentionBatch(
      authorityId: 'desk',
      epoch: 7,
      fromSeq: 2,
      toSeq: 2,
      events: [
        AttentionEvent(
          eventId: 'evt-2',
          authorityId: 'desk',
          epoch: 7,
          seq: 2,
          sessionId: 's1',
          memberId: 'dev',
          kind: AttentionKind.idle,
          occurredAt: occurred,
          expiresAt: occurred.add(const Duration(days: 7)),
        ),
      ],
    );

    final decoded = AttentionBatch.fromJson(batch.toJson());

    expect(decoded, isNotNull);
    expect(decoded!.authorityId, 'desk');
    expect(decoded.epoch, 7);
    expect(decoded.fromSeq, 2);
    expect(decoded.toSeq, 2);
    expect(decoded.events.single.eventId, 'evt-2');
    expect(decoded.gap, isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/attention/attention_event_test.dart`
Expected: FAIL — the three library files do not exist.

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/attention/attention_event.dart`:

```dart
import 'dart:convert';

/// Semantic fact a user may want to know about. Unknown values decode to
/// [info] so a newer authority can add kinds without breaking older clients.
enum AttentionKind {
  idle,
  waiting,
  failed,
  info;

  static AttentionKind parse(Object? value) {
    final name = value is String ? value : '';
    for (final kind in AttentionKind.values) {
      if (kind.name == name) return kind;
    }
    return AttentionKind.info;
  }
}

/// One durable attention event.
///
/// `eventId` is the idempotency key; `seq` is assigned by the authority's
/// `AttentionLog` and is strictly monotonic inside one `(authorityId, epoch)`.
final class AttentionEvent {
  const AttentionEvent({
    required this.eventId,
    required this.authorityId,
    required this.epoch,
    required this.seq,
    required this.sessionId,
    required this.memberId,
    required this.kind,
    required this.occurredAt,
    required this.expiresAt,
    this.turnId,
    this.workspaceId = '',
    this.title = '',
    this.message = '',
    this.payload = const {},
  });

  final String eventId;
  final String authorityId;
  final int epoch;
  final int seq;
  final String sessionId;
  final String memberId;
  final String? turnId;
  final String workspaceId;
  final AttentionKind kind;
  final DateTime occurredAt;
  final DateTime expiresAt;
  final String title;
  final String message;
  final Map<String, Object?> payload;

  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now.toUtc());

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'authorityId': authorityId,
    'epoch': epoch,
    'seq': seq,
    'sessionId': sessionId,
    if (memberId.isNotEmpty) 'memberId': memberId,
    if (turnId != null && turnId!.isNotEmpty) 'turnId': turnId,
    if (workspaceId.isNotEmpty) 'workspaceId': workspaceId,
    'kind': kind.name,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    if (title.isNotEmpty) 'title': title,
    if (message.isNotEmpty) 'message': message,
    if (payload.isNotEmpty) 'payload': payload,
  };

  static AttentionEvent? fromJson(Object? json) {
    if (json is! Map) return null;
    final eventId = json['eventId'];
    final authorityId = json['authorityId'];
    final sessionId = json['sessionId'];
    final kind = json['kind'];
    final epoch = json['epoch'];
    final seq = json['seq'];
    if (eventId is! String || eventId.isEmpty) return null;
    if (authorityId is! String || authorityId.isEmpty) return null;
    if (sessionId is! String || sessionId.isEmpty) return null;
    if (kind is! String) return null;
    if (epoch is! num || epoch <= 0) return null;
    if (seq is! num || seq <= 0) return null;
    final memberId = json['memberId'];
    final turnId = json['turnId'];
    final workspaceId = json['workspaceId'];
    final occurredAt = json['occurredAt'];
    final expiresAt = json['expiresAt'];
    final title = json['title'];
    final message = json['message'];
    final rawPayload = json['payload'];
    final parsedOccurred = occurredAt is String
        ? DateTime.tryParse(occurredAt)?.toUtc()
        : null;
    final parsedExpires = expiresAt is String
        ? DateTime.tryParse(expiresAt)?.toUtc()
        : null;
    if (parsedOccurred == null || parsedExpires == null) return null;
    return AttentionEvent(
      eventId: eventId,
      authorityId: authorityId,
      epoch: epoch.toInt(),
      seq: seq.toInt(),
      sessionId: sessionId,
      memberId: memberId is String ? memberId : '',
      turnId: turnId is String && turnId.isNotEmpty ? turnId : null,
      workspaceId: workspaceId is String ? workspaceId : '',
      kind: AttentionKind.parse(kind),
      occurredAt: parsedOccurred,
      expiresAt: parsedExpires,
      title: title is String ? title : '',
      message: message is String ? message : '',
      payload: rawPayload is Map
          ? {
              for (final entry in rawPayload.entries)
                entry.key.toString(): entry.value,
            }
          : const {},
    );
  }
}
```

`client/lib/services/attention/attention_cursor.dart`:

```dart
import 'attention_event.dart';

/// Highest `seq` a client has consumed for one authority epoch.
final class AttentionCursor {
  const AttentionCursor({
    required this.authorityId,
    required this.epoch,
    required this.seq,
  });

  final String authorityId;
  final int epoch;
  final int seq;

  AttentionCursor advance(AttentionEvent event) {
    if (event.authorityId != authorityId || event.epoch != epoch) {
      return AttentionCursor(
        authorityId: event.authorityId,
        epoch: event.epoch,
        seq: event.seq,
      );
    }
    if (event.seq <= seq) return this;
    return AttentionCursor(
      authorityId: authorityId,
      epoch: epoch,
      seq: event.seq,
    );
  }

  Map<String, Object?> toJson() => {
    'authorityId': authorityId,
    'epoch': epoch,
    'seq': seq,
  };

  static AttentionCursor? fromJson(Object? json) {
    if (json is! Map) return null;
    final authorityId = json['authorityId'];
    final epoch = json['epoch'];
    final seq = json['seq'];
    if (authorityId is! String || authorityId.isEmpty) return null;
    if (epoch is! num || epoch <= 0) return null;
    if (seq is! num || seq < 0) return null;
    return AttentionCursor(
      authorityId: authorityId,
      epoch: epoch.toInt(),
      seq: seq.toInt(),
    );
  }
}
```

`client/lib/services/attention/attention_batch.dart`:

```dart
import 'attention_event.dart';

/// One `events` wire frame: a contiguous (or explicitly gapped) slice of the
/// authority log.
final class AttentionBatch {
  const AttentionBatch({
    required this.authorityId,
    required this.epoch,
    required this.fromSeq,
    required this.toSeq,
    required this.events,
    this.gap = false,
  });

  final String authorityId;
  final int epoch;
  final int fromSeq;
  final int toSeq;
  final List<AttentionEvent> events;

  /// True when the requested cursor was older than the retained window; the
  /// client accepts [events] but knows some history is unrecoverable.
  final bool gap;

  Map<String, Object?> toJson() => {
    'authority': authorityId,
    'epoch': epoch,
    'fromSeq': fromSeq,
    'toSeq': toSeq,
    'events': [for (final event in events) event.toJson()],
    'gap': gap,
  };

  static AttentionBatch? fromJson(Object? json) {
    if (json is! Map) return null;
    final authority = json['authority'];
    final epoch = json['epoch'];
    final fromSeq = json['fromSeq'];
    final toSeq = json['toSeq'];
    final gap = json['gap'];
    if (authority is! String || authority.isEmpty) return null;
    final events = <AttentionEvent>[];
    final rawEvents = json['events'];
    if (rawEvents is List) {
      for (final raw in rawEvents) {
        final event = AttentionEvent.fromJson(raw);
        if (event != null) events.add(event);
      }
    }
    return AttentionBatch(
      authorityId: authority,
      epoch: epoch is num ? epoch.toInt() : 0,
      fromSeq: fromSeq is num ? fromSeq.toInt() : 0,
      toSeq: toSeq is num ? toSeq.toInt() : 0,
      events: events,
      gap: gap is bool ? gap : false,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/attention/attention_event_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze lib/services/attention test/services/attention`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/attention/attention_event.dart client/lib/services/attention/attention_cursor.dart client/lib/services/attention/attention_batch.dart client/test/services/attention/attention_event_test.dart
git commit -m "feat(attention): add event, cursor and batch models"
```

---

### Task 2: Authority 侧 append-only 日志

**Files:**
- Create: `client/lib/services/attention/attention_log.dart`
- Test: `client/test/services/attention/attention_log_test.dart`

**Interfaces:**
- Consumes: `AttentionEvent`, `AttentionKind`, `AttentionCursor`, `AttentionBatch`, `Filesystem`, `appLogger`.
- Produces:
  - `AttentionLog({required String authorityId, required int epoch, Filesystem? fs, String? path, DateTime Function()? clock, Duration retention, int maxEvents, String Function()? eventId})`
  - `static Future<AttentionLog> open({required String authorityId, required int epoch, required Filesystem fs, required String path, ...})`
  - `Stream<AttentionEvent> get appended`
  - `Future<AttentionEvent> append({required String sessionId, required String memberId, required AttentionKind kind, String? turnId, String workspaceId, String title, String message, Map<String, Object?> payload, DateTime? occurredAt})`
  - `AttentionBatch slice({AttentionCursor? cursor, int limit = 200})`
  - `int get earliestSeq`, `int get latestSeq`, `Future<void> close()`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/attention/attention_cursor.dart';
import 'package:teampilot/services/attention/attention_event.dart';
import 'package:teampilot/services/attention/attention_log.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  setUp(() => logSeq = 0);

  test('append assigns monotonic seq and emits after the write', () async {
    final log = AttentionLog(
      authorityId: 'desk',
      epoch: 7,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );
    final seen = <AttentionEvent>[];
    final sub = log.appended.listen(seen.add);

    final first = await log.append(
      sessionId: 's1',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    final second = await log.append(
      sessionId: 's1',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    await Future<void>.delayed(Duration.zero);

    expect(first.seq, 1);
    expect(second.seq, 2);
    expect(first.eventId, 'evt-0');
    expect(second.eventId, 'evt-1');
    expect(seen.map((event) => event.seq), [1, 2]);
    expect(log.latestSeq, 2);
    expect(log.earliestSeq, 1);

    await sub.cancel();
    await log.close();
  });

  test('slice returns only events after the cursor', () async {
    final log = AttentionLog(
      authorityId: 'desk',
      epoch: 7,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );
    for (var i = 0; i < 3; i++) {
      await log.append(
        sessionId: 's$i',
        memberId: 'dev',
        kind: AttentionKind.idle,
      );
    }

    final batch = log.slice(
      cursor: const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 1),
      limit: 1,
    );

    expect(batch.events.single.seq, 2);
    expect(batch.fromSeq, 2);
    expect(batch.toSeq, 2);
    expect(batch.gap, isFalse);
    await log.close();
  });

  test('slice reports a gap when the cursor is before the retained window',
      () async {
    final log = AttentionLog(
      authorityId: 'desk',
      epoch: 7,
      maxEvents: 2,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );
    for (var i = 0; i < 3; i++) {
      await log.append(
        sessionId: 's$i',
        memberId: 'dev',
        kind: AttentionKind.idle,
      );
    }

    final batch = log.slice(
      cursor: const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 0),
    );

    expect(batch.gap, isTrue);
    expect(batch.events.map((event) => event.seq), [2, 3]);
    expect(batch.toSeq, 3);
    await log.close();
  });

  test('file-backed log reloads events and continues the sequence', () async {
    final fs = InMemoryFilesystem();
    final path = '/tp/attention/log-7.jsonl';
    final first = await AttentionLog.open(
      authorityId: 'desk',
      epoch: 7,
      fs: fs,
      path: path,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );
    await first.append(
      sessionId: 's1',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    await first.append(
      sessionId: 's2',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    await first.close();

    final second = await AttentionLog.open(
      authorityId: 'desk',
      epoch: 7,
      fs: fs,
      path: path,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );

    expect(second.events.map((event) => event.seq), [1, 2]);
    expect(second.latestSeq, 2);
    final third = await second.append(
      sessionId: 's3',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    expect(third.seq, 3);
    await second.close();
  });

  test('corrupt lines are skipped', () async {
    final fs = InMemoryFilesystem();
    final path = '/tp/attention/log-7.jsonl';
    fs.files[path] = 'not json\n';
    final log = await AttentionLog.open(
      authorityId: 'desk',
      epoch: 7,
      fs: fs,
      path: path,
      clock: () => DateTime.utc(2026, 11, 14),
      eventId: () => 'evt-${logSeq++}',
    );

    expect(log.events, isEmpty);
    expect(log.latestSeq, 0);
    final event = await log.append(
      sessionId: 's1',
      memberId: 'dev',
      kind: AttentionKind.idle,
    );
    expect(event.seq, 1);
    await log.close();
  });
}

var logSeq = 0;
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/attention/attention_log_test.dart`
Expected: FAIL — `attention_log.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/attention/attention_log.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import 'attention_batch.dart';
import 'attention_cursor.dart';
import 'attention_event.dart';

/// Append-only attention log owned by the process that owns the seat runtime.
///
/// `seq` is assigned here, in append order. With [fs] + [path] every event is
/// persisted before it is emitted. A failed file write is logged and the event
/// is still emitted: losing one notification is worse than losing durability
/// for that one event.
final class AttentionLog {
  AttentionLog({
    required this.authorityId,
    required this.epoch,
    Filesystem? fs,
    String? path,
    DateTime Function()? clock,
    this.retention = const Duration(days: 7),
    this.maxEvents = 1000,
    String Function()? eventId,
  }) : _fs = fs,
       _path = path,
       _clock = clock ?? DateTime.now,
       _eventId = eventId ?? (() => const Uuid().v7());

  static const tag = 'attention';

  final String authorityId;
  final int epoch;
  final Duration retention;
  final int maxEvents;
  final Filesystem? _fs;
  final String? _path;
  final DateTime Function() _clock;
  final String Function() _eventId;

  final List<AttentionEvent> _events = [];
  final StreamController<AttentionEvent> _appended =
      StreamController<AttentionEvent>.broadcast();
  Future<void> _queue = Future<void>.value();
  int _nextSeq = 1;
  bool _closed = false;

  Stream<AttentionEvent> get appended => _appended.stream;

  List<AttentionEvent> get events => List.unmodifiable(_events);

  int get earliestSeq => _events.isEmpty ? _nextSeq : _events.first.seq;

  int get latestSeq => _nextSeq - 1;

  static Future<AttentionLog> open({
    required String authorityId,
    required int epoch,
    required Filesystem fs,
    required String path,
    DateTime Function()? clock,
    Duration retention = const Duration(days: 7),
    int maxEvents = 1000,
    String Function()? eventId,
  }) async {
    final log = AttentionLog(
      authorityId: authorityId,
      epoch: epoch,
      fs: fs,
      path: path,
      clock: clock,
      retention: retention,
      maxEvents: maxEvents,
      eventId: eventId,
    );
    await log._load();
    return log;
  }

  Future<void> _load() async {
    final fs = _fs;
    final path = _path;
    if (fs == null || path == null) return;
    try {
      await fs.ensureDir(fs.pathContext.dirname(path));
      final raw = await fs.readString(path);
      if (raw == null || raw.trim().isEmpty) return;
      var maxSeq = 0;
      for (final line in const LineSplitter().convert(raw)) {
        if (line.trim().isEmpty) continue;
        try {
          final event = AttentionEvent.fromJson(jsonDecode(line));
          if (event == null ||
              event.authorityId != authorityId ||
              event.epoch != epoch) {
            continue;
          }
          _events.add(event);
          if (event.seq > maxSeq) maxSeq = event.seq;
        } on Object catch (error, stackTrace) {
          appLogger.w(
            '[$tag] skipping corrupt log line path=$path',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      _events.sort((a, b) => a.seq.compareTo(b.seq));
      _nextSeq = maxSeq + 1;
      _pruneMemory();
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[$tag] load failed path=$path',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<AttentionEvent> append({
    required String sessionId,
    required String memberId,
    required AttentionKind kind,
    String? turnId,
    String workspaceId = '',
    String title = '',
    String message = '',
    Map<String, Object?> payload = const {},
    DateTime? occurredAt,
  }) {
    final completer = Completer<AttentionEvent>();
    _queue = _queue.catchError((Object _) {}).then((_) async {
      try {
        if (_closed) {
          completer.completeError(StateError('attention log is closed'));
          return;
        }
        final now = (occurredAt ?? _clock()).toUtc();
        final event = AttentionEvent(
          eventId: _eventId(),
          authorityId: authorityId,
          epoch: epoch,
          seq: _nextSeq++,
          sessionId: sessionId,
          memberId: memberId,
          turnId: turnId,
          workspaceId: workspaceId,
          kind: kind,
          occurredAt: now,
          expiresAt: now.add(retention),
          title: title,
          message: message,
          payload: payload,
        );
        await _persist(event);
        _events.add(event);
        if (_pruneMemory()) await _compact();
        if (!_appended.isClosed) _appended.add(event);
        completer.complete(event);
      } on Object catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }

  AttentionBatch slice({AttentionCursor? cursor, int limit = 200}) {
    final earliest = earliestSeq;
    final latest = latestSeq;
    var baseSeq = latest;
    var start = 0;
    var gap = false;
    final current = cursor;
    if (current != null &&
        current.authorityId == authorityId &&
        current.epoch == epoch) {
      baseSeq = current.seq;
      if (current.seq < earliest - 1) {
        gap = true;
        start = 0;
      } else {
        start = _events.indexWhere((event) => event.seq > current.seq);
        if (start < 0) start = _events.length;
      }
    }
    final events = _events.skip(start).take(limit).toList(growable: false);
    return AttentionBatch(
      authorityId: authorityId,
      epoch: epoch,
      fromSeq: events.isEmpty ? baseSeq + 1 : events.first.seq,
      toSeq: events.isEmpty ? (gap ? earliest - 1 : baseSeq) : events.last.seq,
      events: events,
      gap: gap,
    );
  }

  Future<void> _persist(AttentionEvent event) async {
    final fs = _fs;
    final path = _path;
    if (fs == null || path == null) return;
    try {
      await fs.appendString(path, '${jsonEncode(event.toJson())}\n');
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[$tag] append failed path=$path',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool _pruneMemory() {
    final now = _clock().toUtc();
    final before = _events.length;
    _events.removeWhere((event) => !event.expiresAt.isAfter(now));
    if (_events.length > maxEvents) {
      _events.removeRange(0, _events.length - maxEvents);
    }
    return _events.length != before;
  }

  Future<void> _compact() async {
    final fs = _fs;
    final path = _path;
    if (fs == null || path == null) return;
    try {
      final content = _events.isEmpty
          ? ''
          : '${_events.map((event) => jsonEncode(event.toJson())).join('\n')}\n';
      await fs.atomicWrite(path, content);
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[$tag] compact failed path=$path',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _queue;
    if (!_appended.isClosed) await _appended.close();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/attention/attention_log_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze lib/services/attention test/services/attention`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/attention/attention_log.dart client/test/services/attention/attention_log_test.dart
git commit -m "feat(attention): add append-only authority log"
```

---

### Task 3: 客户端游标存储

**Files:**
- Create: `client/lib/services/attention/attention_cursor_store.dart`
- Test: `client/test/services/attention/attention_cursor_store_test.dart`

**Interfaces:**
- Consumes: `Filesystem`, `AttentionCursor`.
- Produces:
  - `AttentionCursorStore({Filesystem? fs, String? path, int maxSeenEventIds = 512})`
  - `Future<void> load()`
  - `AttentionCursor? cursorFor(String homeId)`
  - `bool hasSeen(String eventId)`
  - `Future<void> remember(String homeId, AttentionCursor cursor, Iterable<String> eventIds)`
  - `Future<void> clearCursor(String homeId)`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/attention/attention_cursor.dart';
import 'package:teampilot/services/attention/attention_cursor_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('remembers cursors and caps the seen event id list', () async {
    final fs = InMemoryFilesystem();
    final store = AttentionCursorStore(
      fs: fs,
      path: '/tp/attention/cursors.json',
      maxSeenEventIds: 2,
    );
    await store.load();

    await store.remember(
      'local',
      const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 2),
      ['e1', 'e2'],
    );
    await store.remember(
      'local',
      const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 3),
      ['e3'],
    );

    expect(store.cursorFor('local')?.seq, 3);
    expect(store.hasSeen('e1'), isFalse);
    expect(store.hasSeen('e2'), isTrue);
    expect(store.hasSeen('e3'), isTrue);
    expect(fs.files['/tp/attention/cursors.json'], contains('"seq": 3'));
  });

  test('reloads cursors from disk', () async {
    final fs = InMemoryFilesystem();
    final path = '/tp/attention/cursors.json';
    final first = AttentionCursorStore(fs: fs, path: path);
    await first.load();
    await first.remember(
      'local',
      const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 9),
      ['e9'],
    );

    final second = AttentionCursorStore(fs: fs, path: path);
    await second.load();

    expect(second.cursorFor('local')?.seq, 9);
    expect(second.hasSeen('e9'), isTrue);
  });

  test('clearCursor removes only that home', () async {
    final fs = InMemoryFilesystem();
    final store = AttentionCursorStore(
      fs: fs,
      path: '/tp/attention/cursors.json',
    );
    await store.load();
    await store.remember(
      'local',
      const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 1),
      const [],
    );
    await store.remember(
      'ssh:p1',
      const AttentionCursor(authorityId: 'desk', epoch: 7, seq: 2),
      const [],
    );

    await store.clearCursor('local');

    expect(store.cursorFor('local'), isNull);
    expect(store.cursorFor('ssh:p1')?.seq, 2);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/attention/attention_cursor_store_test.dart`
Expected: FAIL — `attention_cursor_store.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/attention/attention_cursor_store.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import '../../utils/logging/logger.dart';
import '../io/filesystem.dart';
import 'attention_cursor.dart';

/// Device-local cursor + seen-event store.
///
/// Cursors are keyed by home id (`RuntimeTarget.id`) so switching between a
/// local home and an SSH home never reuses the wrong authority position.
final class AttentionCursorStore {
  AttentionCursorStore({
    Filesystem? fs,
    String? path,
    int maxSeenEventIds = 512,
  }) : _fs = fs,
       _path = path,
       _maxSeenEventIds = maxSeenEventIds;

  static const tag = 'attention';

  final Filesystem? _fs;
  final String? _path;
  final int _maxSeenEventIds;

  final Map<String, AttentionCursor> _cursors = {};
  final List<String> _seen = [];
  final Set<String> _seenSet = {};
  Future<void> _queue = Future<void>.value();
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final fs = _fs;
    final path = _path;
    if (fs == null || path == null) return;
    try {
      final raw = await fs.readString(path);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final cursors = decoded['cursors'];
      if (cursors is Map) {
        for (final entry in cursors.entries) {
          final cursor = AttentionCursor.fromJson(entry.value);
          if (cursor != null) {
            _cursors[entry.key.toString()] = cursor;
          }
        }
      }
      final seen = decoded['seenEventIds'];
      if (seen is List) {
        for (final id in seen) {
          if (id is String && id.isNotEmpty && _seenSet.add(id)) {
            _seen.add(id);
          }
        }
      }
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[$tag] cursor load failed path=$path',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  AttentionCursor? cursorFor(String homeId) => _cursors[homeId];

  bool hasSeen(String eventId) => _seenSet.contains(eventId);

  Future<void> remember(
    String homeId,
    AttentionCursor cursor,
    Iterable<String> eventIds,
  ) {
    _cursors[homeId] = cursor;
    for (final id in eventIds) {
      if (id.isEmpty || !_seenSet.add(id)) continue;
      _seen.add(id);
    }
    if (_seen.length > _maxSeenEventIds) {
      final drop = _seen.length - _maxSeenEventIds;
      for (final id in _seen.take(drop)) {
        _seenSet.remove(id);
      }
      _seen.removeRange(0, drop);
    }
    return _persist();
  }

  Future<void> clearCursor(String homeId) {
    _cursors.remove(homeId);
    return _persist();
  }

  Future<void> _persist() {
    _queue = _queue.catchError((Object _) {}).then((_) async {
      final fs = _fs;
      final path = _path;
      if (fs == null || path == null) return;
      try {
        await fs.ensureDir(fs.pathContext.dirname(path));
        await fs.atomicWrite(
          path,
          const JsonEncoder.withIndent('  ').convert({
            'version': 1,
            'cursors': {
              for (final entry in _cursors.entries)
                entry.key: entry.value.toJson(),
            },
            'seenEventIds': _seen,
          }),
        );
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[$tag] cursor save failed path=$path',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
    return _queue;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/attention/attention_cursor_store_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze lib/services/attention test/services/attention`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/attention/attention_cursor_store.dart client/test/services/attention/attention_cursor_store_test.dart
git commit -m "feat(attention): add device-local cursor store"
```

---

### Task 4: 客户端 Inbox（去重 + 游标 + fresh 流）

**Files:**
- Create: `client/lib/services/attention/attention_inbox.dart`
- Test: `client/test/services/attention/attention_inbox_test.dart`

**Interfaces:**
- Consumes: `AttentionCursorStore`, `AttentionBatch`, `AttentionEvent`.
- Produces:
  - `AttentionInbox({required AttentionCursorStore store, DateTime Function()? clock})`
  - `Stream<AttentionEvent> get fresh`
  - `AttentionCursor? cursorFor(String homeId)`
  - `Future<void> ingest(String homeId, Iterable<AttentionEvent> events)`
  - `Future<void> skipGap(String homeId, AttentionBatch batch)`
  - `Future<void> clearCursor(String homeId)`
  - `Future<void> dispose()`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/attention/attention_batch.dart';
import 'package:teampilot/services/attention/attention_cursor.dart';
import 'package:teampilot/services/attention/attention_cursor_store.dart';
import 'package:teampilot/services/attention/attention_event.dart';
import 'package:teampilot/services/attention/attention_inbox.dart';

AttentionEvent _event({
  required int seq,
  String eventId = '',
  DateTime? occurredAt,
}) {
  final at = occurredAt ?? DateTime.utc(2026, 11, 14);
  return AttentionEvent(
    eventId: eventId.isEmpty ? 'evt-$seq' : eventId,
    authorityId: 'desk',
    epoch: 7,
    seq: seq,
    sessionId: 's1',
    memberId: 'dev',
    kind: AttentionKind.idle,
    occurredAt: at,
    expiresAt: at.add(const Duration(days: 7)),
  );
}

void main() {
  test('ingest deduplicates by eventId and advances the cursor', () async {
    final store = AttentionCursorStore();
    final inbox = AttentionInbox(store: store);
    final seen = <AttentionEvent>[];
    final sub = inbox.fresh.listen(seen.add);

    await inbox.ingest('local', [_event(seq: 1)]);
    await inbox.ingest('local', [_event(seq: 1), _event(seq: 2)]);
    await Future<void>.delayed(Duration.zero);

    expect(seen.map((event) => event.seq), [1, 2]);
    expect(inbox.cursorFor('local')?.seq, 2);
    await sub.cancel();
    await inbox.dispose();
  });

  test('out-of-order events still leave the cursor at the highest seq',
      () async {
    final inbox = AttentionInbox(store: AttentionCursorStore());
    final seen = <AttentionEvent>[];
    final sub = inbox.fresh.listen(seen.add);

    await inbox.ingest('local', [_event(seq: 3)]);
    await inbox.ingest('local', [_event(seq: 1), _event(seq: 2)]);
    await Future<void>.delayed(Duration.zero);

    expect(seen.map((event) => event.seq), [1, 2, 3]);
    expect(inbox.cursorFor('local')?.seq, 3);
    await sub.cancel();
    await inbox.dispose();
  });

  test('expired events advance the cursor but do not notify', () async {
    final now = DateTime.utc(2026, 11, 14);
    final inbox = AttentionInbox(
      store: AttentionCursorStore(),
      clock: () => now.add(const Duration(days: 8)),
    );
    final seen = <AttentionEvent>[];
    final sub = inbox.fresh.listen(seen.add);

    await inbox.ingest('local', [_event(seq: 1, occurredAt: now)]);
    await Future<void>.delayed(Duration.zero);

    expect(seen, isEmpty);
    expect(inbox.cursorFor('local')?.seq, 1);
    await sub.cancel();
    await inbox.dispose();
  });

  test('skipGap advances the cursor past an unrecoverable range', () async {
    final inbox = AttentionInbox(store: AttentionCursorStore());
    await inbox.skipGap(
      'local',
      const AttentionBatch(
        authorityId: 'desk',
        epoch: 7,
        fromSeq: 3,
        toSeq: 3,
        events: [],
        gap: true,
      ),
    );

    expect(inbox.cursorFor('local')?.seq, 3);
  });

  test('cursor is retained across inbox instances', () async {
    final store = AttentionCursorStore();
    final first = AttentionInbox(store: store);
    await first.ingest('local', [_event(seq: 7)]);
    await first.dispose();

    final second = AttentionInbox(store: store);
    expect(second.cursorFor('local')?.seq, 7);
    await second.dispose();
  });

  test('clearCursor removes the home position', () async {
    final inbox = AttentionInbox(store: AttentionCursorStore());
    await inbox.ingest('local', [_event(seq: 2)]);
    await inbox.clearCursor('local');

    expect(inbox.cursorFor('local'), isNull);
    await inbox.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/attention/attention_inbox_test.dart`
Expected: FAIL — `attention_inbox.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/attention/attention_inbox.dart`:

```dart
import 'dart:async';

import 'attention_batch.dart';
import 'attention_cursor.dart';
import 'attention_cursor_store.dart';
import 'attention_event.dart';

/// Client-side consumer of an authority attention log.
///
/// [ingest] is deliberately serialized by the caller (the protocol controller
/// awaits it before acking). It deduplicates by [AttentionEvent.eventId],
/// persists the highest consumed seq per home, and only then emits [fresh].
final class AttentionInbox {
  AttentionInbox({
    required this.store,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AttentionCursorStore store;
  final DateTime Function() _clock;
  final StreamController<AttentionEvent> _fresh =
      StreamController<AttentionEvent>.broadcast();

  Stream<AttentionEvent> get fresh => _fresh.stream;

  AttentionCursor? cursorFor(String homeId) => store.cursorFor(homeId);

  Future<void> ingest(String homeId, Iterable<AttentionEvent> events) async {
    final ordered = events.toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    if (ordered.isEmpty) return;
    var cursor = store.cursorFor(homeId);
    final accepted = <AttentionEvent>[];
    final batchSeen = <String>{};
    for (final event in ordered) {
      if (!batchSeen.add(event.eventId)) continue;
      if (!store.hasSeen(event.eventId)) accepted.add(event);
      cursor = cursor?.advance(event) ??
          AttentionCursor(
            authorityId: event.authorityId,
            epoch: event.epoch,
            seq: event.seq,
          );
    }
    if (cursor != null) {
      await store.remember(
        homeId,
        cursor,
        accepted.map((event) => event.eventId),
      );
    }
    final now = _clock().toUtc();
    for (final event in accepted) {
      if (event.isExpiredAt(now)) continue;
      if (!_fresh.isClosed) _fresh.add(event);
    }
  }

  /// Advances past a range the authority no longer retains. Does not emit.
  Future<void> skipGap(String homeId, AttentionBatch batch) async {
    final existing = store.cursorFor(homeId);
    if (existing != null &&
        existing.authorityId == batch.authorityId &&
        existing.epoch == batch.epoch &&
        existing.seq >= batch.toSeq) {
      return;
    }
    await store.remember(
      homeId,
      AttentionCursor(
        authorityId: batch.authorityId,
        epoch: batch.epoch,
        seq: batch.toSeq,
      ),
      const [],
    );
  }

  Future<void> clearCursor(String homeId) => store.clearCursor(homeId);

  Future<void> dispose() async {
    if (!_fresh.isClosed) await _fresh.close();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/attention/attention_inbox_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze lib/services/attention test/services/attention`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/attention/attention_inbox.dart client/test/services/attention/attention_inbox_test.dart
git commit -m "feat(attention): add idempotent client inbox"
```

---

### Task 5: `SessionAuthority` 接入 `AttentionLog`

**Files:**
- Modify: `client/lib/services/session_protocol/session_authority.dart`
- Modify: `client/lib/services/session_protocol/session_models.dart` (delete `SessionAttention`)
- Modify: `client/lib/services/session_sync/chat_session_activity_source.dart`
- Test: `client/test/services/session_protocol/session_authority_test.dart`

**Interfaces:**
- Consumes: `AttentionLog`, `AttentionEvent`, `AttentionKind`.
- Produces:
  - `SessionAuthority` factory keeps `authorityId`, `controlPort`, `epoch`, adds `attentionLog`.
  - `AttentionLog get attentionLog`
  - `Stream<AttentionEvent> get attention` (now the log's `appended`)
  - `Future<AttentionEvent> publishAttention({required String sessionId, required AttentionKind kind, String memberId, String? turnId, String workspaceId, String title, String message, Map<String, Object?> payload})`
  - `ChatSessionActivitySource` no longer generates `attention-N` ids.

- [ ] **Step 1: Write the failing test**

Append to `client/test/services/session_protocol/session_authority_test.dart` inside `main()`:

```dart
  test('publishAttention appends to the authority log', () async {
    final event = await authority.publishAttention(
      sessionId: 's1',
      kind: AttentionKind.idle,
      memberId: 'dev',
      workspaceId: 'ws1',
    );

    expect(event.seq, 1);
    expect(event.authorityId, 'desk');
    expect(event.epoch, 7);
    expect(event.workspaceId, 'ws1');
    expect(authority.attentionLog.latestSeq, 1);
    expect(authority.attentionLog.events.single.eventId, event.eventId);

    final second = await authority.publishAttention(
      sessionId: 's1',
      kind: AttentionKind.idle,
      memberId: 'dev',
    );
    expect(second.seq, 2);
  });
```

Add the import at the top:

```dart
import 'package:teampilot/services/attention/attention_event.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/session_protocol/session_authority_test.dart`
Expected: FAIL — `publishAttention` returns `SessionAttention` and does not expose `attentionLog`.

- [ ] **Step 3: Write minimal implementation**

In `client/lib/services/session_protocol/session_authority.dart`:

1. Add imports:

```dart
import '../attention/attention_event.dart';
import '../attention/attention_log.dart';
```

2. Replace the constructor with a factory + private constructor:

```dart
  factory SessionAuthority({
    required String authorityId,
    required SessionControlPort controlPort,
    int? epoch,
    AttentionLog? attentionLog,
    DateTime Function()? clock,
  }) {
    final resolvedEpoch =
        attentionLog?.epoch ?? epoch ?? DateTime.now().millisecondsSinceEpoch;
    return SessionAuthority._(
      authorityId: authorityId,
      controlPort: controlPort,
      epoch: resolvedEpoch,
      attentionLog: attentionLog ??
          AttentionLog(
            authorityId: authorityId,
            epoch: resolvedEpoch,
            clock: clock,
          ),
      clock: clock,
    );
  }

  SessionAuthority._({
    required this.authorityId,
    required SessionControlPort controlPort,
    required this.epoch,
    required AttentionLog attentionLog,
    DateTime Function()? clock,
  }) : _controlPort = controlPort,
       _attentionLog = attentionLog,
       _clock = clock ?? DateTime.now;
```

3. Replace the `_attention` field and getter:

```dart
  final AttentionLog _attentionLog;

  AttentionLog get attentionLog => _attentionLog;
```

4. Replace the `attention` getter:

```dart
  Stream<AttentionEvent> get attention => _attentionLog.appended;
```

5. Replace `publishAttention`:

```dart
  Future<AttentionEvent> publishAttention({
    required String sessionId,
    required AttentionKind kind,
    String memberId = '',
    String? turnId,
    String workspaceId = '',
    String title = '',
    String message = '',
    Map<String, Object?> payload = const {},
  }) {
    return _attentionLog.append(
      sessionId: sessionId,
      memberId: memberId,
      kind: kind,
      turnId: turnId,
      workspaceId: workspaceId,
      title: title,
      message: message,
      payload: payload,
    );
  }
```

6. In `dispose`, replace `await _attention.close();` with `await _attentionLog.close();`.

In `client/lib/services/session_protocol/session_models.dart`, delete the whole `SessionAttention` class (lines starting at `/// Durable notification fact...` through its closing `}`).

In `client/lib/services/session_sync/chat_session_activity_source.dart`:

1. Add import:

```dart
import '../attention/attention_event.dart';
```

2. Delete the `int _attentionSeq = 0;` field.

3. Replace the `publishAttention` call:

```dart
          unawaited(
            authority.publishAttention(
              sessionId: sessionId,
              kind: AttentionKind.idle,
              memberId: seat.memberId,
              turnId: seat.turnId,
              workspaceId: tab.persistedSession?.workspaceId ?? '',
            ),
          );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/session_protocol/session_authority_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze lib/services/session_protocol/session_authority.dart lib/services/session_protocol/session_models.dart lib/services/session_sync/chat_session_activity_source.dart test/services/session_protocol/session_authority_test.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/session_protocol/session_authority.dart client/lib/services/session_protocol/session_models.dart client/lib/services/session_sync/chat_session_activity_source.dart client/test/services/session_protocol/session_authority_test.dart
git commit -m "feat(attention): publish authority attention through the log"
```

---

### Task 6: 协议 v2（envelope + server backlog + client events/ack）

**Files:**
- Modify: `client/lib/services/session_protocol/session_envelope.dart`
- Modify: `client/lib/services/session_protocol/session_server.dart`
- Modify: `client/lib/services/session_protocol/session_client.dart`
- Test: `client/test/services/session_protocol/session_server_client_test.dart`

**Interfaces:**
- Consumes: `AttentionLog`, `AttentionBatch`, `AttentionCursor`, `AttentionEvent`.
- Produces:
  - `sessionProtocolVersion = 2`
  - `SessionChannel.events` (removed `attention`)
  - `SessionMessageType.events` / `SessionMessageType.ack`
  - `SessionServer` accepts `hello.cursors`, sends `helloAck.earliestSeq/latestSeq/epoch`, sends `events` backlog + live, accepts `ack`
  - `SessionClient({..., Map<String, AttentionCursor> Function()? attentionCursors})`
  - `SessionClientCallbacks.onAttentionBatch`
  - `SessionClient.sendAttentionAck({authorityId, epoch, seq})`

- [ ] **Step 1: Write the failing test**

Replace `client/test/services/session_protocol/session_server_client_test.dart` with:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/attention/attention_batch.dart';
import 'package:teampilot/services/attention/attention_cursor.dart';
import 'package:teampilot/services/attention/attention_event.dart';
import 'package:teampilot/services/attention/attention_log.dart';
import 'package:teampilot/services/session_protocol/session_authority.dart';
import 'package:teampilot/services/session_protocol/session_channel.dart';
import 'package:teampilot/services/session_protocol/session_client.dart';
import 'package:teampilot/services/session_protocol/session_control_port.dart';
import 'package:teampilot/services/session_protocol/session_models.dart';
import 'package:teampilot/services/session_protocol/session_server.dart';

final class _Control implements SessionControlPort {
  int cancels = 0;
  final List<String> refreshes = [];
  final List<Map<String, Object?>> adopted = [];
  final List<String> removed = [];
  final List<(String, String, String)> edits = [];
  final List<String> editCancels = [];

  @override
  Future<void> cancelTurn({
    required String sessionId,
    required String memberId,
  }) async {
    cancels++;
  }

  @override
  Future<void> refreshWorkspaceSessions(String workspaceId) async {
    refreshes.add(workspaceId);
  }

  @override
  Future<void> adoptSession({
    required String workspaceId,
    required Map<String, Object?> entry,
  }) async {
    adopted.add(entry);
  }

  @override
  Future<void> removeSession({
    required String workspaceId,
    required String sessionId,
  }) async {
    removed.add(sessionId);
  }

  @override
  Future<void> editTurn({
    required String sessionId,
    required String memberId,
    required String operationId,
    required String userMessageId,
    required String text,
  }) async {
    edits.add((operationId, userMessageId, text));
  }

  @override
  Future<void> cancelEdit({
    required String sessionId,
    required String memberId,
    required String operationId,
  }) async {
    editCancels.add(operationId);
  }
}

final class _Pipe {
  _Pipe() {
    server = _Channel(this, isServer: true);
    client = _Channel(this, isServer: false);
  }

  late final _Channel server;
  late final _Channel client;

  void forward(_Channel from, List<int> data) {
    final target = identical(from, server) ? client : server;
    target.push(data);
  }
}

final class _Channel implements SessionByteChannel {
  _Channel(this._pipe, {required this.isServer});

  final _Pipe _pipe;
  final bool isServer;
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  bool closed = false;

  @override
  Stream<List<int>> get incoming => _incoming.stream;

  @override
  void add(List<int> data) => _pipe.forward(this, data);

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await _incoming.close();
  }

  void push(List<int> data) {
    if (!_incoming.isClosed) _incoming.add(data);
  }
}

Future<void> _waitFor(bool Function() ok, {Duration? timeout}) async {
  final end = DateTime.now().add(timeout ?? const Duration(seconds: 2));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('timed out');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

SessionSeatActivity _seat(String state) => SessionSeatActivity(
  sessionId: 's1',
  memberId: 'dev',
  state: state,
  readyToChat: state == SessionSeatActivity.stateIdle,
);

void main() {
  test(
    'server and client exchange snapshot, delta, intent and attention events',
    () async {
      final pipe = _Pipe();
      final control = _Control();
      final authority = SessionAuthority(
        authorityId: 'desk',
        controlPort: control,
        epoch: 7,
      );
      final server = SessionServer(
        channel: pipe.server,
        authority: authority,
        deviceId: 'desk',
      );
      var snapshots = 0;
      final deltas = <SessionDelta>[];
      final contents = <SessionContentInvalidated>[];
      final contentDeltas = <SessionContentDelta>[];
      final sessionLists = <SessionListDelta>[];
      final batches = <AttentionBatch>[];
      final errors = <String>[];
      final client = SessionClient(
        channel: pipe.client,
        deviceId: 'phone',
        callbacks: SessionClientCallbacks(
          onSnapshot: (value) => snapshots++,
          onDelta: deltas.add,
          onContent: contents.add,
          onContentDelta: contentDeltas.add,
          onSessionList: sessionLists.add,
          onAttentionBatch: batches.add,
          onError: (code, message) => errors.add(code),
        ),
      );

      await server.start();
      await client.start();
      await _waitFor(() => client.isReady && snapshots > 0);

      authority.updateSeats('s1', [
        _seat(SessionSeatActivity.stateWorking),
      ], workspaceId: 'ws1');
      await _waitFor(() => deltas.isNotEmpty);
      expect(deltas.last.seats.single.state, 'working');
      expect(deltas.last.workspaceId, 'ws1');

      final result = await client.cancelTurn(sessionId: 's1', memberId: 'dev');
      expect(result.status, SessionIntentStatus.applied);
      expect(control.cancels, 1);

      final refresh = await client.refreshSessions(workspaceId: 'ws1');
      expect(refresh.status, SessionIntentStatus.applied);
      expect(control.refreshes, ['ws1']);

      const entry = <String, Object?>{
        'sessionId': 's-new',
        'display': 'From mobile',
        'createdAt': 10,
      };
      final created = await client.createSession(
        workspaceId: 'ws1',
        sessionId: 's-new',
        entry: entry,
      );
      expect(created.status, SessionIntentStatus.applied);
      expect(control.adopted, [entry]);
      await _waitFor(() => sessionLists.isNotEmpty);
      expect(sessionLists.single.workspaceId, 'ws1');
      expect(sessionLists.single.upserted, [entry]);

      final removed = await client.removeSession(
        workspaceId: 'ws1',
        sessionId: 's-new',
      );
      expect(removed.status, SessionIntentStatus.applied);
      expect(control.removed, ['s-new']);
      await _waitFor(() => sessionLists.length == 2);
      expect(sessionLists.last.workspaceId, 'ws1');
      expect(sessionLists.last.removed, ['s-new']);

      authority.publishContentInvalidated(sessionId: 's1');
      await _waitFor(() => contents.isNotEmpty);
      expect(contents.single.sessionId, 's1');

      authority.publishContentDelta(
        sessionId: 's1',
        memberId: 'dev',
        kind: 'acp.messages',
        payload: '{"v":2,"type":"reset"}\n',
      );
      await _waitFor(() => contentDeltas.isNotEmpty);
      expect(contentDeltas.single.kind, 'acp.messages');
      expect(contentDeltas.single.seq, 1);
      expect(contentDeltas.single.payload, '{"v":2,"type":"reset"}\n');

      authority.publishContentDelta(
        sessionId: 's1',
        memberId: 'dev',
        kind: 'acp.messages',
        payload: '{"v":2,"type":"part"}\n',
      );
      await _waitFor(() => contentDeltas.length == 2);
      expect(contentDeltas.last.seq, 2);
      expect(contentDeltas.last.baseSeq, 1);

      await authority.publishAttention(
        sessionId: 's1',
        kind: AttentionKind.idle,
        memberId: 'dev',
      );
      await _waitFor(() => batches.isNotEmpty);
      expect(batches.single.events.single.kind, AttentionKind.idle);
      expect(batches.single.events.single.seq, 1);

      client.sendAttentionAck(
        authorityId: 'desk',
        epoch: 7,
        seq: batches.single.toSeq,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(errors, isEmpty);

      await client.close();
      await server.stop();
      await authority.dispose();
    },
  );

  test('reconnect replays events after the client cursor', () async {
    final control = _Control();
    final authority = SessionAuthority(
      authorityId: 'desk',
      controlPort: control,
      epoch: 7,
    );

    final firstPipe = _Pipe();
    final firstBatches = <AttentionBatch>[];
    final firstServer = SessionServer(
      channel: firstPipe.server,
      authority: authority,
      deviceId: 'desk',
    );
    final firstClient = SessionClient(
      channel: firstPipe.client,
      deviceId: 'phone',
      callbacks: SessionClientCallbacks(onAttentionBatch: firstBatches.add),
    );
    await firstServer.start();
    await firstClient.start();
    await _waitFor(() => firstClient.isReady);

    await authority.publishAttention(
      sessionId: 's1',
      kind: AttentionKind.idle,
    );
    await _waitFor(() => firstBatches.isNotEmpty);
    final cursor = AttentionCursor(
      authorityId: 'desk',
      epoch: 7,
      seq: firstBatches.single.toSeq,
    );

    await firstClient.close();
    await firstServer.stop();

    await authority.publishAttention(
      sessionId: 's2',
      kind: AttentionKind.idle,
    );

    final secondPipe = _Pipe();
    final secondBatches = <AttentionBatch>[];
    final secondServer = SessionServer(
      channel: secondPipe.server,
      authority: authority,
      deviceId: 'desk',
    );
    final secondClient = SessionClient(
      channel: secondPipe.client,
      deviceId: 'phone',
      attentionCursors: () => {'desk': cursor},
      callbacks: SessionClientCallbacks(onAttentionBatch: secondBatches.add),
    );
    await secondServer.start();
    await secondClient.start();
    await _waitFor(() => secondBatches.isNotEmpty);

    expect(secondBatches.single.events.single.sessionId, 's2');
    expect(secondBatches.single.events.single.seq, 2);

    await secondClient.close();
    await secondServer.stop();
    await authority.dispose();
  });

  test('an epoch mismatch starts from live instead of replaying old events',
      () async {
    final authority = SessionAuthority(
      authorityId: 'desk',
      controlPort: _Control(),
      epoch: 7,
    );
    await authority.publishAttention(
      sessionId: 'old',
      kind: AttentionKind.idle,
    );

    final pipe = _Pipe();
    final batches = <AttentionBatch>[];
    final server = SessionServer(
      channel: pipe.server,
      authority: authority,
      deviceId: 'desk',
    );
    final client = SessionClient(
      channel: pipe.client,
      deviceId: 'phone',
      attentionCursors: () => const {
        'desk': AttentionCursor(authorityId: 'desk', epoch: 6, seq: 1),
      },
      callbacks: SessionClientCallbacks(onAttentionBatch: batches.add),
    );
    await server.start();
    await client.start();
    await _waitFor(() => client.isReady);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(batches, isEmpty);

    await authority.publishAttention(
      sessionId: 'new',
      kind: AttentionKind.idle,
    );
    await _waitFor(() => batches.isNotEmpty);
    expect(batches.single.events.single.sessionId, 'new');

    await client.close();
    await server.stop();
    await authority.dispose();
  });

  test('a cursor older than the retained window reports a gap', () async {
    final log = AttentionLog(
      authorityId: 'desk',
      epoch: 7,
      maxEvents: 2,
    );
    final authority = SessionAuthority(
      authorityId: 'desk',
      controlPort: _Control(),
      epoch: 7,
      attentionLog: log,
    );
    for (var i = 0; i < 3; i++) {
      await authority.publishAttention(
        sessionId: 's$i',
        kind: AttentionKind.idle,
      );
    }

    final pipe = _Pipe();
    final batches = <AttentionBatch>[];
    final server = SessionServer(
      channel: pipe.server,
      authority: authority,
      deviceId: 'desk',
    );
    final client = SessionClient(
      channel: pipe.client,
      deviceId: 'phone',
      attentionCursors: () => const {
        'desk': AttentionCursor(authorityId: 'desk', epoch: 7, seq: 0),
      },
      callbacks: SessionClientCallbacks(onAttentionBatch: batches.add),
    );
    await server.start();
    await client.start();
    await _waitFor(() => batches.isNotEmpty);

    expect(batches.any((batch) => batch.gap), isTrue);
    expect(
      batches.expand((batch) => batch.events).map((event) => event.seq),
      [2, 3],
    );

    await client.close();
    await server.stop();
    await authority.dispose();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/session_protocol/session_server_client_test.dart`
Expected: FAIL — `AttentionLog`/`attentionCursors`/`onAttentionBatch` are not defined on the protocol classes.

- [ ] **Step 3: Write minimal implementation**

`client/lib/services/session_protocol/session_envelope.dart`:

```dart
/// Protocol version carried in every envelope.
const sessionProtocolVersion = 2;

/// Logical channels multiplexed on one byte stream.
enum SessionChannel { control, state, content, events, bulk }

/// Message type names.
abstract final class SessionMessageType {
  static const hello = 'hello';
  static const helloAck = 'helloAck';
  static const attach = 'attach';
  static const snapshot = 'snapshot';
  static const delta = 'delta';
  static const content = 'content';
  static const contentDelta = 'contentDelta';
  static const contentAck = 'contentAck';
  static const sessionList = 'sessionList';
  static const intent = 'intent';
  static const intentResult = 'intentResult';
  static const events = 'events';
  static const ack = 'ack';
  static const resync = 'resync';
  static const ping = 'ping';
  static const pong = 'pong';
  static const error = 'error';
}
```

Keep the rest of `SessionEnvelope` unchanged.

`client/lib/services/session_protocol/session_server.dart`:

1. Add imports:

```dart
import '../attention/attention_batch.dart';
import '../attention/attention_cursor.dart';
import '../attention/attention_event.dart';
```

2. Change the default capabilities:

```dart
    this.capabilities = const [
      'state',
      'content.invalidated',
      'intent.turn.cancel',
      'intent.turn.edit',
      'op.state',
      'attention.log.v1',
    ],
```

3. Replace the `_attentionSub` field and add backlog state:

```dart
  StreamSubscription<AttentionEvent>? _attentionSub;
  final List<AttentionEvent> _pendingLiveAttention = [];
  bool _attentionBacklogDone = false;
  int _lastSentAttentionSeq = 0;
```

4. Replace the hello branch:

```dart
      _helloReceived = true;
      _helloTimer?.cancel();
      final rawCursors = envelope.body['cursors'];
      AttentionCursor? cursor;
      if (rawCursors is Map) {
        cursor = AttentionCursor.fromJson(
          rawCursors[_authority.authorityId],
        );
      }
      if (cursor != null && cursor.epoch != _authority.epoch) {
        cursor = null;
      }
      _send(
        SessionMessageType.helloAck,
        channel: SessionChannel.control,
        body: {
          'proto': sessionProtocolVersion,
          'authority': _authority.authorityId,
          'epoch': _authority.epoch,
          'device': deviceId,
          'caps': capabilities,
          'earliestSeq': _authority.attentionLog.earliestSeq,
          'latestSeq': _authority.attentionLog.latestSeq,
        },
      );
      _sendSnapshot(_authority.snapshots());
      _subscribeAuthority(cursor);
      return;
```

5. Add an `ack` case to the switch:

```dart
      case SessionMessageType.ack:
        break;
```

6. Replace `_subscribeAuthority()` with `_subscribeAuthority(AttentionCursor? cursor)` and append the attention methods:

```dart
  void _subscribeAuthority(AttentionCursor? cursor) {
    _deltaSub = _authority.deltas.listen(
      (delta) => _send(
        SessionMessageType.delta,
        channel: SessionChannel.state,
        body: delta.toJson(),
      ),
    );
    _contentSub = _authority.content.listen(
      (event) => _send(
        SessionMessageType.content,
        channel: SessionChannel.content,
        body: event.toJson(),
      ),
    );
    _contentDeltaSub = _authority.contentDeltas.listen(
      (event) => _send(
        SessionMessageType.contentDelta,
        channel: SessionChannel.content,
        body: event.toJson(),
      ),
    );
    _sessionListSub = _authority.sessionLists.listen(
      (event) => _send(
        SessionMessageType.sessionList,
        channel: SessionChannel.state,
        body: event.toJson(),
      ),
    );
    _startAttention(cursor);
  }

  void _startAttention(AttentionCursor? cursor) {
    if (cursor == null) {
      _lastSentAttentionSeq = _authority.attentionLog.latestSeq;
      _attentionBacklogDone = true;
    } else {
      _lastSentAttentionSeq = cursor.seq;
    }
    _attentionSub = _authority.attention.listen((event) {
      if (!_attentionBacklogDone) {
        _pendingLiveAttention.add(event);
        return;
      }
      _sendAttentionEvent(event);
    });
    if (cursor != null) {
      unawaited(_sendAttentionBacklog(cursor));
    }
  }

  Future<void> _sendAttentionBacklog(AttentionCursor cursor) async {
    var next = cursor;
    while (!_closed) {
      final batch = _authority.attentionLog.slice(cursor: next, limit: 200);
      if (batch.events.isEmpty) {
        if (batch.gap) _sendAttentionBatch(batch);
        break;
      }
      _sendAttentionBatch(batch);
      next = AttentionCursor(
        authorityId: batch.authorityId,
        epoch: batch.epoch,
        seq: batch.toSeq,
      );
      if (batch.events.length < 200) break;
    }
    _attentionBacklogDone = true;
    final pending = List<AttentionEvent>.of(_pendingLiveAttention)
      ..sort((a, b) => a.seq.compareTo(b.seq));
    _pendingLiveAttention.clear();
    for (final event in pending) {
      if (event.seq > _lastSentAttentionSeq) _sendAttentionEvent(event);
    }
  }

  void _sendAttentionBatch(AttentionBatch batch) {
    _send(
      SessionMessageType.events,
      channel: SessionChannel.events,
      body: batch.toJson(),
    );
    if (batch.toSeq > _lastSentAttentionSeq) {
      _lastSentAttentionSeq = batch.toSeq;
    }
  }

  void _sendAttentionEvent(AttentionEvent event) {
    if (event.seq <= _lastSentAttentionSeq) return;
    _sendAttentionBatch(
      AttentionBatch(
        authorityId: event.authorityId,
        epoch: event.epoch,
        fromSeq: event.seq,
        toSeq: event.seq,
        events: [event],
      ),
    );
  }
```

7. In `_close`, keep `await _attentionSub?.cancel();`.

`client/lib/services/session_protocol/session_client.dart`:

1. Add imports:

```dart
import '../attention/attention_batch.dart';
import '../attention/attention_cursor.dart';
```

2. Replace the typedef and callbacks:

```dart
typedef SessionAttentionBatchHandler = void Function(AttentionBatch batch);
```

In `SessionClientCallbacks`, replace `onAttention` with:

```dart
    this.onAttentionBatch,
...
  final SessionAttentionBatchHandler? onAttentionBatch;
```

3. Add constructor parameters and fields:

```dart
    this.attentionCursors,
...
  final Map<String, AttentionCursor> Function()? attentionCursors;
```

4. Add a field for the authority id:

```dart
  String? _authorityId;
...
  String? get authorityId => _authorityId;
```

5. In `start()`, replace the hello body with:

```dart
      body: {
        'proto': sessionProtocolVersion,
        'device': deviceId,
        'caps': const [
          'state',
          'content.invalidated',
          'intent.turn.cancel',
          'intent.turn.edit',
          'op.state',
          'attention.log.v1',
        ],
        'cursors': {
          for (final entry
              in (attentionCursors?.call() ?? const <String, AttentionCursor>{})
                  .entries)
            entry.key: entry.value.toJson(),
        },
      },
```

6. In `helloAck`, set `_authorityId`:

```dart
      case SessionMessageType.helloAck:
        _ready = true;
        _helloTimer?.cancel();
        final authority = envelope.body['authority'];
        _authorityId = authority is String ? authority : null;
        final epoch = envelope.body['epoch'];
        _epoch = epoch is num ? epoch.toInt() : null;
        callbacks.onReady?.call();
        break;
```

7. Replace the `attention` case with `events` and add `ack`:

```dart
      case SessionMessageType.events:
        final batch = AttentionBatch.fromJson(envelope.body);
        if (batch != null) callbacks.onAttentionBatch?.call(batch);
        break;
      case SessionMessageType.ack:
        break;
```

8. Add the ack sender after `sendResync()`:

```dart
  void sendAttentionAck({
    required String authorityId,
    required int epoch,
    required int seq,
  }) {
    _send(
      SessionMessageType.ack,
      channel: SessionChannel.control,
      body: {'authority': authorityId, 'epoch': epoch, 'seq': seq},
    );
  }
```

9. In `SessionClientConnection`, add the constructor parameter and field:

```dart
    this.attentionCursors,
...
  final Map<String, AttentionCursor> Function()? attentionCursors;
```

10. In `_run`, pass it to each `SessionClient`:

```dart
        client = SessionClient(
          channel: channel,
          deviceId: deviceId,
          attentionCursors: attentionCursors,
          callbacks: SessionClientCallbacks(
            ...
            onAttentionBatch: callbacks.onAttentionBatch,
            ...
          ),
        );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/session_protocol/session_server_client_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze lib/services/session_protocol test/services/session_protocol`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/session_protocol/session_envelope.dart client/lib/services/session_protocol/session_server.dart client/lib/services/session_protocol/session_client.dart client/test/services/session_protocol/session_server_client_test.dart
git commit -m "feat(session-protocol): stream attention log over protocol v2"
```

---

### Task 7: Controller 按 homeId 消费事件并 ack

**Files:**
- Modify: `client/lib/services/session_sync/session_protocol_controller.dart`
- Modify: `client/lib/app/session_protocol_home.dart`
- Test: `client/test/services/session_sync/` is not extended in this task; Task 6 exercises the wire contract, and `flutter analyze` covers the controller wiring.

**Interfaces:**
- Consumes: `AttentionInbox`, `AttentionBatch`, `AttentionCursor`.
- Produces:
  - `SessionProtocolController({..., AttentionInbox? attentionInbox})`
  - `Future<void> applyClient({required Future<SessionByteChannel> Function() open, required String homeId})`
  - On every `events` batch: `inbox.ingest(homeId, batch.events)`, `inbox.skipGap(homeId, batch)` when `gap`, then `client.sendAttentionAck(...)`.
  - On `helloAck` epoch mismatch: `inbox.clearCursor(homeId)`.

- [ ] **Step 1: Write the failing test**

There is no new test file in this task. The failing signal is the analyzer: `SessionProtocolController` still declares `onAttention` and `SessionAttention`. After the protocol v2 change it will not compile.

Run: `cd client && flutter analyze lib/services/session_sync/session_protocol_controller.dart lib/app/session_protocol_home.dart`
Expected: FAIL — `SessionAttention` is gone and `applyClient` needs `homeId`.

- [ ] **Step 2: Write minimal implementation**

In `client/lib/services/session_sync/session_protocol_controller.dart`:

1. Add imports:

```dart
import '../attention/attention_batch.dart';
import '../attention/attention_cursor.dart';
import '../attention/attention_inbox.dart';
```

2. Replace the `onAttention` constructor parameter and field with `attentionInbox`:

```dart
    this.attentionInbox,
...
  final AttentionInbox? attentionInbox;
```

3. Add a home id field:

```dart
  String _homeId = '';
```

4. Replace `applyClient`:

```dart
  Future<void> applyClient({
    required Future<SessionByteChannel> Function() open,
    required String homeId,
  }) async {
    await applyNone();
    _homeId = homeId.trim();
    _role = SessionProtocolRole.client;
    appLogger.i('[$_tag] role=client device=$deviceId home=$_homeId');
    final client = SessionClientConnection(
      open: open,
      deviceId: deviceId,
      attentionCursors: _attentionCursors,
      isExpectedFailure: isExpectedFailure,
      waitForRecovery: waitForRecovery,
      callbacks: SessionClientCallbacks(
        onSnapshot: (snapshots) { ... },
        onDelta: (delta) { ... },
        onContent: (invalidation) { ... },
        onContentDelta: (delta) { ... },
        onSessionList: (delta) { ... },
        onAttentionBatch: (batch) {
          appLogger.i(
            '[$_tag] client attention authority=${batch.authorityId} '
            'epoch=${batch.epoch} from=${batch.fromSeq} to=${batch.toSeq} '
            'count=${batch.events.length} gap=${batch.gap}',
          );
          unawaited(_handleAttentionBatch(batch));
        },
        onReady: () {
          appLogger.i('[$_tag] client ready');
          _resetAttentionCursorIfEpochMoved();
          unawaited(_flushPendingRefreshes());
          unawaited(_flushPendingCreates());
          unawaited(_flushPendingRemoves());
        },
        onError: (code, message) { ... },
        onClosed: () { ... },
      ),
    );
    _client = client;
    await client.start();
  }
```

Keep the existing bodies of the other callbacks unchanged.

5. Add the helpers near `applyClient`:

```dart
  Map<String, AttentionCursor> _attentionCursors() {
    final inbox = attentionInbox;
    if (inbox == null || _homeId.isEmpty) return const {};
    final cursor = inbox.cursorFor(_homeId);
    return cursor == null ? const {} : {cursor.authorityId: cursor};
  }

  void _resetAttentionCursorIfEpochMoved() {
    final inbox = attentionInbox;
    final cursor = inbox?.cursorFor(_homeId);
    final epoch = _client?.client?.epoch;
    if (inbox == null ||
        cursor == null ||
        epoch == null ||
        cursor.epoch == epoch) {
      return;
    }
    unawaited(inbox.clearCursor(_homeId));
  }

  Future<void> _handleAttentionBatch(AttentionBatch batch) async {
    final inbox = attentionInbox;
    if (inbox != null && _homeId.isNotEmpty) {
      await inbox.ingest(_homeId, batch.events);
      if (batch.gap) await inbox.skipGap(_homeId, batch);
    }
    _client?.client?.sendAttentionAck(
      authorityId: batch.authorityId,
      epoch: batch.epoch,
      seq: batch.toSeq,
    );
  }
```

6. In `applyNone`, add `_homeId = '';`.

In `client/lib/app/session_protocol_home.dart`, change the client branch:

```dart
      await controller.applyClient(
        homeId: homeStorage.context.target.id,
        open: () => openSshSessionProtocolChannel(
          homeStorage: homeStorage,
          sshClientFactory: sshClientFactory,
          homeProfile: homeProfile,
        ),
      );
```

- [ ] **Step 3: Run analyzer**

Run: `cd client && flutter analyze lib/services/session_sync/session_protocol_controller.dart lib/app/session_protocol_home.dart`
Expected: No issues.

- [ ] **Step 4: Run the protocol tests again**

Run: `cd client && dart run tool/run_tests.dart test/services/session_protocol/session_server_client_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/session_sync/session_protocol_controller.dart client/lib/app/session_protocol_home.dart
git commit -m "feat(attention): ingest remote attention batches per home"
```

---

### Task 8: Boot wiring（日志、游标、inbox、通知）

**Files:**
- Modify: `client/lib/services/storage/app_paths.dart`
- Modify: `client/lib/app/bootstrap/session_runtime_wiring.dart`
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/services/storage/attention_paths_test.dart` (create)

**Interfaces:**
- Consumes: `AttentionLog.open`, `AttentionCursorStore`, `AttentionInbox`, `AttentionEvent`.
- Produces:
  - `AppPaths.attentionLogJsonForEpoch(int epoch)`
  - `AppPaths.attentionCursorsJson`
  - `SessionRuntimeWiring` adds `AttentionInbox attentionInbox` and `StreamSubscription<AttentionEvent> attentionSub`
  - `wireSessionRuntime` becomes `Future<SessionRuntimeWiring>` and accepts `required HomeStorage deviceStorage`
  - Remote notification is driven by `attentionInbox.fresh` instead of `SessionAttention`.

- [ ] **Step 1: Write the failing test**

Create `client/test/services/storage/attention_paths_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/app_paths.dart';

void main() {
  test('attention paths are stable and epoch-scoped', () {
    const paths = AppPaths('/tp');

    expect(
      paths.attentionLogJsonForEpoch(7),
      '/tp/attention/log-7.jsonl',
    );
    expect(paths.attentionCursorsJson, '/tp/attention/cursors.json');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/attention_paths_test.dart`
Expected: FAIL — `attentionLogJsonForEpoch` / `attentionCursorsJson` do not exist.

- [ ] **Step 3: Write minimal implementation**

In `client/lib/services/storage/app_paths.dart`, add next to `sessionProtocolJson`:

```dart
  String attentionLogJsonForEpoch(int epoch) =>
      attentionLogJsonForEpochAtTeampilotRoot(basePath, epoch);

  static String attentionLogJsonForEpochAtTeampilotRoot(
    String teampilotRoot,
    int epoch,
  ) => _pathUnderTeampilotRoot(
    teampilotRoot,
    'attention/log-$epoch.jsonl',
  );

  String get attentionCursorsJson =>
      attentionCursorsJsonForTeampilotRoot(basePath);

  static String attentionCursorsJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'attention/cursors.json');
```

In `client/lib/app/bootstrap/session_runtime_wiring.dart`:

1. Add imports:

```dart
import '../attention/attention_cursor_store.dart';
import '../attention/attention_event.dart';
import '../attention/attention_inbox.dart';
import '../attention/attention_log.dart';
import '../storage/home_storage.dart';
```

2. Change the wiring typedef:

```dart
typedef SessionRuntimeWiring = ({
  SessionRemoteActivityCubit sessionRemoteActivityCubit,
  SessionAuthority sessionAuthority,
  ChatSessionActivitySource activitySource,
  SessionProtocolController protocolController,
  AttentionInbox attentionInbox,
  StreamSubscription<AttentionEvent> attentionSub,
  AiHistoryCubit aiHistoryCubit,
  MailboxCubit mailboxCubit,
  BoardCubit boardCubit,
  StreamSubscription<SessionRemoteActivityState> sessionRemoteRefreshSub,
  StreamSubscription<SessionContentInvalidation> contentInvalidationSub,
  StreamSubscription<SessionContentStreamChunk> contentStreamSub,
});
```

3. Change the signature to async and add `deviceStorage`:

```dart
Future<SessionRuntimeWiring> wireSessionRuntime({
  required HomeStorage deviceStorage,
  ...
}) async {
```

4. Replace the authority construction block:

```dart
  final authorityEpoch = DateTime.now().millisecondsSinceEpoch;
  final attentionLog = await AttentionLog.open(
    authorityId: SharedStateIdentity.deviceId,
    epoch: authorityEpoch,
    fs: deviceStorage.fs,
    path: deviceStorage.paths.attentionLogJsonForEpoch(authorityEpoch),
  );
  final attentionCursorStore = AttentionCursorStore(
    fs: deviceStorage.fs,
    path: deviceStorage.paths.attentionCursorsJson,
  );
  await attentionCursorStore.load();
  final attentionInbox = AttentionInbox(store: attentionCursorStore);
  final sessionAuthority = SessionAuthority(
    authorityId: SharedStateIdentity.deviceId,
    controlPort: ChatSessionControlPort(chatCubit),
    epoch: authorityEpoch,
    attentionLog: attentionLog,
  );
```

5. Replace the `seenRemoteAttentionIds` / `notifyRemoteAttention(SessionAttention)` block with:

```dart
  Future<void> notifyRemoteAttention(AttentionEvent attention) async {
    final session = chatCubit.state.sessions
        .where((item) => item.sessionId == attention.sessionId)
        .firstOrNull;
    final title = attention.title.trim().isNotEmpty
        ? attention.title.trim()
        : (session?.display.trim().isNotEmpty ?? false)
        ? session!.display.trim()
        : attention.sessionId;
    final locale = PlatformDispatcher.instance.locale;
    final l10n = lookupAppLocalizations(
      basicLocaleListResolution([locale], appLocalizationsSupportedLocales),
    );
    final workspaceId = attention.workspaceId.isNotEmpty
        ? attention.workspaceId
        : session?.workspaceId ?? '';
    final payload = HomeWorkspaceRoute.sessionLocation(
      workspaceId: workspaceId,
      sessionId: attention.sessionId,
    );
    await remoteIdleNotifications.notifyRemoteSessionIdle(
      title: title,
      message: attention.message.isNotEmpty
          ? attention.message
          : l10n.session.idleNotificationSubtitle,
      badge: l10n.session.idleNotificationTitle,
      payload: payload,
      systemNotificationEnabled: notifyOnSessionIdle(),
    );
  }

  final attentionSub = attentionInbox.fresh.listen((event) {
    if (event.kind != AttentionKind.idle) return;
    unawaited(notifyRemoteAttention(event));
  });
```

6. Remove `onAttention` from `SessionProtocolController` and add `attentionInbox`:

```dart
  final sessionProtocolController = SessionProtocolController(
    deviceId: SharedStateIdentity.deviceId,
    remoteCubit: sessionRemoteActivityCubit,
    authority: sessionAuthority,
    attentionInbox: attentionInbox,
    isExpectedFailure: isExpectedFailure,
    waitForRecovery: waitForRecovery,
    ...
  );
```

7. Add `attentionInbox` and `attentionSub` to the returned record:

```dart
  return (
    sessionRemoteActivityCubit: sessionRemoteActivityCubit,
    sessionAuthority: sessionAuthority,
    activitySource: sessionActivitySource,
    protocolController: sessionProtocolController,
    attentionInbox: attentionInbox,
    attentionSub: attentionSub,
    ...
  );
```

In `client/lib/app/app_shell.dart`:

1. Add imports:

```dart
import '../services/attention/attention_event.dart';
import '../services/attention/attention_inbox.dart';
```

2. Add fields next to the other shell subscriptions:

```dart
  StreamSubscription<AttentionEvent>? _attentionSub;
  AttentionInbox? _attentionInbox;
```

3. In `cancelShellSubscriptions`, add:

```dart
    unawaited(_attentionSub?.cancel());
    unawaited(_attentionInbox?.dispose());
```

4. At the `wireSessionRuntime` call, add `await` and `deviceStorage`:

```dart
    final sessionRuntime = await wireSessionRuntime(
      deviceStorage: deviceLocalHomeStorage(nativeAppDataPath),
      chat: () => chatCubit,
      ...
    );
```

5. Destructure the new record fields:

```dart
    final attentionInbox = sessionRuntime.attentionInbox;
    final attentionSub = sessionRuntime.attentionSub;
```

6. Assign them to the shell after construction, next to the other subscriptions:

```dart
    shell._attentionInbox = attentionInbox;
    shell._attentionSub = attentionSub;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && dart run tool/run_tests.dart test/services/storage/attention_paths_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze lib/services/storage/app_paths.dart lib/app/bootstrap/session_runtime_wiring.dart lib/app/app_shell.dart test/services/storage/attention_paths_test.dart`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add client/lib/services/storage/app_paths.dart client/lib/app/bootstrap/session_runtime_wiring.dart client/lib/app/app_shell.dart client/test/services/storage/attention_paths_test.dart
git commit -m "feat(attention): wire durable cursor and inbox at boot"
```

---

### Task 9: 回归、清理与验收

**Files:**
- Modify: any test that still references `SessionAttention`, `onAttention`, or `publishAttention(..., id: ...)`.
- Test: all affected suites.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: a green change set with no stale v1 symbols.

- [ ] **Step 1: Find stale symbols**

Run:

```bash
cd client && grep -rn "SessionAttention\|onAttention\b\|attentionAck\|SessionMessageType.attention\|SessionChannel.attention\|publishAttention(.*id:" lib test
```

Expected: no matches. If a test still uses the old API, update it to `AttentionEvent` / `onAttentionBatch`.

- [ ] **Step 2: Run the attention suite**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/attention test/services/session_protocol/session_server_client_test.dart test/services/session_protocol/session_authority_test.dart test/services/storage/attention_paths_test.dart
```

Expected: PASS.

- [ ] **Step 3: Run the notification suite**

Run:

```bash
cd client && dart run tool/run_tests.dart test/services/notification
```

Expected: PASS. The existing `SessionIdleNotificationService` tests must still pass unchanged.

- [ ] **Step 4: Analyze the whole client**

Run:

```bash
cd client && flutter analyze
```

Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add -u client/lib client/test
git commit -m "test(attention): update protocol v2 regression coverage"
```

---

## Self-Review

**Spec coverage**

| Spec requirement | Task |
|---|---|
| 领域模型 `AttentionEvent` / `AttentionKind` | Task 1 |
| authority append-only log、seq、epoch、retention | Task 2 |
| 客户端游标持久化、eventId 去重 | Tasks 3–4 |
| 协议 v2 `hello(cursors)` / `helloAck` / `events` / `ack` | Task 6 |
| 断线补发、epoch fencing、gap | Task 6 |
| `SessionAuthority` 先 append 再广播 | Task 5 |
| `SessionProtocolController` 消费 + ack | Task 7 |
| 启动接线、设备本地游标、远程通知 | Task 8 |
| 现有 `notifyOnSessionIdle` 仍然生效 | Task 8（继续调用 `notifyRemoteSessionIdle`） |
| 旧 `attention` 语义删除 | Tasks 5–6 + Task 9 grep |
| 本地路径完全统一 / Android 前台服务 / push | 明确不在本计划（见 File Structure） |

**Placeholder scan**

- 无 `TBD` / `TODO` / “类似 Task N”。
- 每个代码步骤都给出了完整文件内容或精确替换片段。
- 每个测试步骤都给出了完整测试代码。

**Type consistency**

- `AttentionEvent.kind` 是 `AttentionKind`；`SessionAuthority.publishAttention`、`SessionServer`、`SessionClient` 都使用同一类型。
- `AttentionBatch.authorityId` 对应 JSON 的 `authority`；`SessionClient` / `SessionServer` 都通过 `toJson`/`fromJson` 读写。
- `AttentionCursorStore.remember` 的参数顺序在 Task 3、Task 4、Task 7 中一致：`(homeId, cursor, eventIds)`。
- `SessionProtocolController.applyClient` 在 Task 7 和 `applySessionProtocolForHome` 中都使用 `homeId:` 命名参数。
- `wireSessionRuntime` 在 Task 8 中改为 `Future<...>`，调用点同步加 `await`。
