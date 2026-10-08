# Event Transport Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把允许列表上的 dispatcher 事件经现有 SSH `forwardLocal` 送到手机，使手机看到桌面占用的 session 与 agent availability。

**Architecture:** 进程内墓碑先修好（`AgentPresenceKind.cleared` 进 dispatcher，投影 `removeSeat` 且广播）。然后纯 NDJSON codec + `EventTransportServer` / `EventTransportClient`；SSH 只在 `app_shell` 接线。local home 开 Server 且 cubit 带 bridge；ssh home 开 Client 且 cubit 不带 bridge。失败降级为今天的磁盘 + 轮询。

**Tech Stack:** Dart 3 / Flutter；`dart:io` `ServerSocket`（仅 loopback）；dartssh2 `forwardLocal`（仅接线层）；测试 `flutter_test` + 假字节流。

**Spec:** `docs/superpowers/specs/2026-09-12-event-transport-design.md`

## Global Constraints

- **绝不直接运行 `flutter test`** —— 一律 `cd client && dart run tool/run_tests.dart <paths>`。
- 内层循环：`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`；单文件：`dart run tool/run_tests.dart test/<path> --plain-name <name>`；全套只在收尾跑一次。
- 读测试摘要行，**不信 runner 退出码**（失败时仍可能为 0）。
- 日志用 `appLogger`，禁止 `print`。本期无新用户可见文案，不改 arb。
- `services/event/` **不 import** `package:dartssh2`、`services/agent_runtime/`、feature 包。
- 本期不触碰 `client/lib/services/agent_runtime/`。
- 不做聊天失效 family、不上线 connection、不事件化 roster / `isWorking`、不做应用层 ping、不搬失败 runtime 分支的 framing。
- **既有测试是行为等价证据**，除下面两处（spec 改了 `null` 报告契约，必须改断言）：
  - `client/test/services/event/presence_event_bridge_test.dart` — `null report clears the baseline without publishing`
  - `client/test/cubits/member_presence_cubit_events_test.dart` — `null report publishes nothing`
  其它 presence / coordination / team 测试一行不改。
- 文件大小软限：`services/` ~600 行。超了按职责再拆，不要把 SSH 和 codec 塞进同一文件。
- 在 worktree `feat-event-transport`（基于 `main`）中实施。新 worktree 先 `git submodule update --init --recursive` + `cd client && dart run tool/sync_bundled_google_fonts.dart`。
- 跑全套若看到 `floating_workspace_panel_gestures_test.dart` / `overflow keeps +` —— 与本路线无关，不要修。

### 文件地图

| 文件 | 职责 |
|---|---|
| `client/lib/services/event/agent_presence_event.dart` | `AgentPresenceKind` 增加 `cleared` |
| `client/lib/services/event/agent_presence_projection.dart` | `handle(cleared)` 广播；`clearAll()`；`occupiedSessionIds` |
| `client/lib/services/event/presence_event_bridge.dart` | `null` → 发布 `cleared` |
| `client/lib/cubits/member_presence_cubit.dart` | `cleared` → availability null；state 带 occupiedSessionIds；ssh home 无 bridge |
| `client/lib/services/event/event_transport_codec.dart` | NDJSON 行、协议常数、family 注册表 |
| `client/lib/services/event/agent_presence_transport_codec.dart` | `agentPresence` set/clear |
| `client/lib/services/event/session_lifecycle_transport_codec.dart` | `sessionLifecycle` live |
| `client/lib/services/event/event_transport_server.dart` | loopback bind、广告文件、握手、snapshot、fan-out |
| `client/lib/services/event/event_transport_client.dart` | subscribe、dispatch、snapshotBegin、退避 |
| `client/lib/services/event/event_transport_controller.dart` | 按 home 角色起停（无 dartssh2） |
| `client/lib/services/storage/app_paths.dart` | `eventTransportJson` 路径 |
| `client/lib/app/app_shell.dart` | 角色接线 + `forwardLocal` |
| `client/lib/utils/session/workspace_running_sessions.dart` | 并入 occupied session ids |
| `docs/workspace-storage-layout.md` / `services/event/README.md` | 广告文件 + transport 段 |

---

### Task 1: 投影墓碑 — `cleared` / `clearAll` / occupancy

**Files:**
- Modify: `client/lib/services/event/agent_presence_event.dart`
- Modify: `client/lib/services/event/agent_presence_projection.dart`
- Test: `client/test/services/event/agent_presence_projection_test.dart`
- Test: `client/test/services/event/agent_presence_family_registration_test.dart`（**只新增**一条测试，不改现有两条）

**Interfaces:**
- Consumes: 现有 `AgentPresenceEvent` / `AgentPresenceProjection`
- Produces:
  - `enum AgentPresenceKind { booting, working, idle, cleared }`
  - `void AgentPresenceProjection.clearAll()`
  - `Set<String> get occupiedSessionIds`（snapshot 里所有 seat 的 `sessionId`；`cleared` 不会留在 map 里）
  - `handle(cleared)`：若 seat 存在则删除并 `changes.add(seat)`；不存在则 no-op

`MemberAvailability` **不**增加值。`cleared` 是 family 动词。

- [ ] **Step 1: 写失败测试**

在 `agent_presence_projection_test.dart` 追加：

```dart
  test('cleared removes the seat and broadcasts', () async {
    final p = AgentPresenceProjection();
    final seen = <PresenceSeatKey>[];
    final sub = p.changes.listen(seen.add);
    const seat = PresenceSeatKey(sessionId: 's', memberId: 'm');
    p.handle(_e('s', 'm', AgentPresenceKind.working));
    p.handle(_e('s', 'm', AgentPresenceKind.cleared));
    await Future<void>.delayed(Duration.zero);
    expect(p.availabilityFor(seat), isNull);
    expect(p.occupiedSessionIds, isEmpty);
    expect(seen, [seat, seat]);
    await sub.cancel();
    await p.close();
  });

  test('cleared on an unknown seat is a no-op', () async {
    final p = AgentPresenceProjection();
    final seen = <PresenceSeatKey>[];
    final sub = p.changes.listen(seen.add);
    p.handle(_e('s', 'm', AgentPresenceKind.cleared));
    await Future<void>.delayed(Duration.zero);
    expect(seen, isEmpty);
    await sub.cancel();
    await p.close();
  });

  test('clearAll drops every seat and broadcasts each', () async {
    final p = AgentPresenceProjection();
    final seen = <PresenceSeatKey>[];
    final sub = p.changes.listen(seen.add);
    p.handle(_e('s1', 'a', AgentPresenceKind.working));
    p.handle(_e('s2', 'b', AgentPresenceKind.idle));
    p.clearAll();
    await Future<void>.delayed(Duration.zero);
    expect(p.snapshot, isEmpty);
    expect(p.occupiedSessionIds, isEmpty);
    expect(
      seen.map((k) => '${k.sessionId}/${k.memberId}').toSet(),
      {'s1/a', 's2/b'},
    );
    await sub.cancel();
    await p.close();
  });

  test('occupiedSessionIds unions session ids still in the snapshot', () async {
    final p = AgentPresenceProjection();
    p.handle(_e('s1', 'a', AgentPresenceKind.booting));
    p.handle(_e('s1', 'b', AgentPresenceKind.working));
    p.handle(_e('s2', 'a', AgentPresenceKind.idle));
    expect(p.occupiedSessionIds, {'s1', 's2'});
    await p.close();
  });
```

在 `agent_presence_family_registration_test.dart` **追加**（保留原两个测试一字不改）：

```dart
  test('cleared shares the family runtimeType so one registration covers it', () {
    expect(
      AgentPresenceKind.cleared.runtimeType,
      AgentPresenceKind.working.runtimeType,
    );
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/agent_presence_projection_test.dart test/services/event/agent_presence_family_registration_test.dart`

Expected: FAIL — `AgentPresenceKind.cleared` 不存在。

- [ ] **Step 3: 最小实现**

`agent_presence_event.dart` 的枚举改为：

```dart
/// Availability phase of one agent seat, plus [cleared] (a retraction verb).
///
/// [booting] / [working] / [idle] mirror `MemberAvailability` one-to-one.
/// [cleared] is NOT an availability: it means the seat is gone (disconnect /
/// unbind). The wire codec maps it to `op:clear`.
enum AgentPresenceKind { booting, working, idle, cleared }
```

`agent_presence_projection.dart` 的 `handle` / 新增 API：

```dart
  Set<String> get occupiedSessionIds =>
      {for (final seat in _bySeat.keys) seat.sessionId};

  @override
  void handle(AgentPresenceEvent event) {
    if (event.eventKind == AgentPresenceKind.cleared) {
      if (!_bySeat.containsKey(event.seat)) return;
      _bySeat.remove(event.seat);
      if (!_changes.isClosed) _changes.add(event.seat);
      return;
    }
    final previous = _bySeat[event.seat];
    if (previous == event.eventKind) return;
    _bySeat[event.seat] = event.eventKind;
    if (!_changes.isClosed) _changes.add(event.seat);
  }

  void removeSeat(PresenceSeatKey seat) {
    _bySeat.remove(seat);
  }

  /// Drops every seat and broadcasts each removed key. Used by transport
  /// `snapshotBegin`. Idempotent on an empty projection.
  void clearAll() {
    if (_bySeat.isEmpty) return;
    final seats = _bySeat.keys.toList();
    _bySeat.clear();
    if (_changes.isClosed) return;
    for (final seat in seats) {
      _changes.add(seat);
    }
  }
```

`removeSeat` 仍不广播（cubit `close()` 路径，座椅随 cubit 一起消失）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/event/agent_presence_projection_test.dart test/services/event/agent_presence_family_registration_test.dart`

Expected: PASS。接着 `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`：`member_presence_cubit.dart` 的 `switch` 会因未处理 `cleared` **失败**。不要在本任务修 cubit——那是 Task 2。若 analyze 只报这一处，继续提交 Task 1 的测试+投影+枚举；若 CI 把 analyze 当门禁，把 cubit 的 `cleared => null` 臂并进 **Step 3** 的最小补丁（只加那一个 case，不改 bridge），并在本任务测试里不覆盖 cubit。

**裁定：** cubit 的 switch 必须同时改，否则工程编译不过。在本任务 Step 3 把 `_availabilityFromKind` 加上 `AgentPresenceKind.cleared => null`，`_kindFromAvailability` 不动（`MemberAvailability` 没有 cleared）。这不是越界：没有 `cleared` 编译已碎。

```dart
  static MemberAvailability? _availabilityFromKind(AgentPresenceKind? kind) =>
      switch (kind) {
        AgentPresenceKind.booting => MemberAvailability.booting,
        AgentPresenceKind.working => MemberAvailability.working,
        AgentPresenceKind.idle => MemberAvailability.idle,
        AgentPresenceKind.cleared => null,
        null => null,
      };
```

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/event/agent_presence_event.dart \
  client/lib/services/event/agent_presence_projection.dart \
  client/lib/cubits/member_presence_cubit.dart \
  client/test/services/event/agent_presence_projection_test.dart \
  client/test/services/event/agent_presence_family_registration_test.dart
git commit -m "feat(presence): cleared kind tombstones the projection"
```

---

### Task 2: Bridge 在 disconnect 时发布 `cleared`

**Files:**
- Modify: `client/lib/services/event/presence_event_bridge.dart`
- Modify: `client/test/services/event/presence_event_bridge_test.dart`（允许改的那一条）
- Modify: `client/test/cubits/member_presence_cubit_events_test.dart`（允许改的那一条断言）

**Interfaces:**
- Consumes: Task 1 的 `AgentPresenceKind.cleared`
- Produces: `reportAvailability(seat, null)` 发布 `AgentPresenceEvent(eventKind: cleared)` 并清基线；随后同值重连仍会再发 `set`

- [ ] **Step 1: 改失败测试（契约变更）**

把 `presence_event_bridge_test.dart` 里 `null report clears the baseline without publishing` **整测替换**为：

```dart
  test('null report publishes cleared and clears the baseline', () {
    final sink = _SpySink();
    final bridge = PresenceEventBridge(
      sink: sink,
      clock: () => DateTime(2026, 9, 12),
    );
    bridge.reportAvailability(seat, AgentPresenceKind.working);
    bridge.reportAvailability(seat, null);
    expect(sink.events.map((e) => e.eventKind), [
      AgentPresenceKind.working,
      AgentPresenceKind.cleared,
    ]);
    expect(sink.events.last.timestamp, DateTime(2026, 9, 12));

    bridge.reportAvailability(seat, AgentPresenceKind.working);
    expect(sink.events.map((e) => e.eventKind), [
      AgentPresenceKind.working,
      AgentPresenceKind.cleared,
      AgentPresenceKind.working,
    ]);
  });
```

把 `member_presence_cubit_events_test.dart` 里：

```dart
        expect(sink.events.length, 1, reason: 'null report publishes nothing');
```

改为：

```dart
        expect(
          sink.events.map((e) => e.eventKind).toList(),
          [AgentPresenceKind.working, AgentPresenceKind.cleared],
          reason: 'disconnect publishes cleared so transport can fan it out',
        );
```

后面「Reconnect at the same value republishes」的 expect 改为：

```dart
        expect(
          sink.events.map((e) => e.eventKind).toList(),
          [
            AgentPresenceKind.working,
            AgentPresenceKind.cleared,
            AgentPresenceKind.working,
          ],
        );
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/presence_event_bridge_test.dart test/cubits/member_presence_cubit_events_test.dart --plain-name "null report publishes cleared"`

Expected: FAIL — 现在 `null` 仍不发布，length 对不上。

- [ ] **Step 3: 最小实现**

`presence_event_bridge.dart` 的 `reportAvailability`：

```dart
  void reportAvailability(PresenceSeatKey seat, AgentPresenceKind? availability) {
    if (_disposed) return;
    if (availability == null) {
      final had = _last.remove(seat);
      if (had == null) return;
      _sink.publish(AgentPresenceEvent(
        seat: seat,
        eventKind: AgentPresenceKind.cleared,
        timestamp: _clock(),
      ));
      return;
    }
    if (_last[seat] == availability) return;
    _last[seat] = availability;
    _sink.publish(AgentPresenceEvent(
      seat: seat,
      eventKind: availability,
      timestamp: _clock(),
    ));
  }
```

注意：`availability == null` 且基线里没有该 seat 时 **不发**（避免未绑定 seat 刷 tombstone）。更新类文档，删掉「publishes NOTHING」。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/event/presence_event_bridge_test.dart test/cubits/member_presence_cubit_events_test.dart`

Expected: PASS（含既有收敛测试）。再跑 `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/event/presence_event_bridge.dart \
  client/test/services/event/presence_event_bridge_test.dart \
  client/test/cubits/member_presence_cubit_events_test.dart
git commit -m "feat(presence): publish cleared on disconnect"
```

---

### Task 3: NDJSON codec + 两个 family codec

**Files:**
- Create: `client/lib/services/event/event_transport_codec.dart`
- Create: `client/lib/services/event/agent_presence_transport_codec.dart`
- Create: `client/lib/services/event/session_lifecycle_transport_codec.dart`
- Test: `client/test/services/event/event_transport_codec_test.dart`

**Interfaces:**
- Consumes: `AgentPresenceEvent`、`SessionLifecycleEvent`、`DispatcherEvent`
- Produces:
  - `eventTransportProtocolVersion == 1`
  - `eventTransportMaxLineBytes == 65536`
  - `eventTransportFamilyAgentPresence == 'agentPresence'`
  - `eventTransportFamilySessionLifecycle == 'sessionLifecycle'`
  - `String encodeTransportLine(Map<String, Object?> object)` — `jsonEncode` + `\n`
  - `Map<String, Object?>? tryDecodeTransportLine(String line)` — 坏 JSON / `v != 1` 返回 `null`（丢弃）
  - `bool transportLineTooLong(List<int> bytes)` — `bytes.length > 65536`
  - `abstract interface class EventTransportFamilyCodec`：
    - `String get family`
    - `Map<String, Object?> encode(DispatcherEvent event)`
    - `DispatcherEvent? decode(Map<String, Object?> payload)`
  - `AgentPresenceTransportCodec` / `SessionLifecycleTransportCodec`

- [ ] **Step 1: 写失败测试**

```dart
// client/test/services/event/event_transport_codec_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/event/agent_presence_event.dart';
import 'package:teampilot/services/event/agent_presence_transport_codec.dart';
import 'package:teampilot/services/event/event_transport_codec.dart';
import 'package:teampilot/services/event/session_lifecycle_event.dart';
import 'package:teampilot/services/event/session_lifecycle_transport_codec.dart';

void main() {
  test('round-trips a presence set line', () {
    final codec = AgentPresenceTransportCodec();
    final event = AgentPresenceEvent(
      seat: const PresenceSeatKey(sessionId: 's', memberId: 'dev'),
      eventKind: AgentPresenceKind.working,
      timestamp: DateTime.utc(2026, 9, 12),
    );
    final payload = codec.encode(event);
    expect(payload['op'], 'set');
    expect(payload['kind'], 'working');
    final line = encodeTransportLine({
      'v': eventTransportProtocolVersion,
      'type': 'event',
      'family': codec.family,
      ...payload,
    });
    expect(line.endsWith('\n'), isTrue);
    expect(line.contains('\n', 0) && line.indexOf('\n') == line.length - 1, isTrue);
    final decoded = tryDecodeTransportLine(line);
    expect(decoded, isNotNull);
    final back = codec.decode(decoded!) as AgentPresenceEvent;
    expect(back.seat, event.seat);
    expect(back.eventKind, AgentPresenceKind.working);
  });

  test('round-trips a presence clear line', () {
    final codec = AgentPresenceTransportCodec();
    final event = AgentPresenceEvent(
      seat: const PresenceSeatKey(sessionId: 's', memberId: 'dev'),
      eventKind: AgentPresenceKind.cleared,
      timestamp: DateTime.utc(2026, 9, 12),
    );
    final payload = codec.encode(event);
    expect(payload['op'], 'clear');
    expect(payload.containsKey('kind'), isFalse);
    final back = codec.decode(payload) as AgentPresenceEvent;
    expect(back.eventKind, AgentPresenceKind.cleared);
  });

  test('round-trips a sessionLifecycle started line', () {
    final codec = SessionLifecycleTransportCodec();
    final event = SessionLifecycleEvent.sessionStarted(
      sessionId: 's',
      workspaceId: 'ws',
      timestamp: DateTime.utc(2026, 9, 12),
    );
    final back = codec.decode(codec.encode(event)) as SessionLifecycleEvent;
    expect(back.eventKind, SessionLifecycleKind.sessionStarted);
    expect(back.sessionId, 's');
    expect(back.workspaceId, 'ws');
    expect(back.memberId, isNull);
  });

  test('drops v!=1 and malformed json', () {
    expect(tryDecodeTransportLine('{"v":2,"type":"event"}\n'), isNull);
    expect(tryDecodeTransportLine('not-json\n'), isNull);
  });

  test('oversize is detected at 65536 bytes', () {
    expect(transportLineTooLong(List.filled(65536, 10)), isFalse);
    expect(transportLineTooLong(List.filled(65537, 10)), isTrue);
  });

  test('unknown presence kind decode returns null', () {
    final codec = AgentPresenceTransportCodec();
    expect(
      codec.decode({
        'op': 'set',
        'kind': 'nope',
        'seat': {'sessionId': 's', 'memberId': 'm'},
        'ts': '2026-09-12T00:00:00.000Z',
      }),
      isNull,
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/event_transport_codec_test.dart`

Expected: FAIL — 文件不存在。

- [ ] **Step 3: 实现**

`event_transport_codec.dart`：

```dart
import 'dart:convert';

import 'dispatcher.dart';

const eventTransportProtocolVersion = 1;
const eventTransportMaxLineBytes = 65536;
const eventTransportFamilyAgentPresence = 'agentPresence';
const eventTransportFamilySessionLifecycle = 'sessionLifecycle';

String encodeTransportLine(Map<String, Object?> object) =>
    '${jsonEncode(object)}\n';

Map<String, Object?>? tryDecodeTransportLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final map = <String, Object?>{
    for (final e in decoded.entries) e.key.toString(): e.value,
  };
  if (map['v'] != eventTransportProtocolVersion) return null;
  return map;
}

bool transportLineTooLong(List<int> bytes) =>
    bytes.length > eventTransportMaxLineBytes;

abstract interface class EventTransportFamilyCodec {
  String get family;
  Map<String, Object?> encode(DispatcherEvent event);
  DispatcherEvent? decode(Map<String, Object?> payload);
}
```

`agent_presence_transport_codec.dart`：

```dart
import 'agent_presence_event.dart';
import 'dispatcher.dart';
import 'event_transport_codec.dart';

final class AgentPresenceTransportCodec implements EventTransportFamilyCodec {
  @override
  String get family => eventTransportFamilyAgentPresence;

  @override
  Map<String, Object?> encode(DispatcherEvent event) {
    final e = event as AgentPresenceEvent;
    return {
      'op': e.eventKind == AgentPresenceKind.cleared ? 'clear' : 'set',
      'seat': {'sessionId': e.sessionId, 'memberId': e.memberId},
      if (e.eventKind != AgentPresenceKind.cleared) 'kind': e.eventKind.name,
      'ts': e.timestamp.toUtc().toIso8601String(),
    };
  }

  @override
  DispatcherEvent? decode(Map<String, Object?> payload) {
    final seatRaw = payload['seat'];
    if (seatRaw is! Map) return null;
    final sessionId = seatRaw['sessionId'] as String?;
    final memberId = seatRaw['memberId'] as String?;
    if (sessionId == null || memberId == null) return null;
    final ts = DateTime.tryParse(payload['ts'] as String? ?? '');
    if (ts == null) return null;
    final op = payload['op'] as String?;
    final AgentPresenceKind kind;
    if (op == 'clear') {
      kind = AgentPresenceKind.cleared;
    } else if (op == 'set') {
      final parsed = switch (payload['kind'] as String?) {
        'booting' => AgentPresenceKind.booting,
        'working' => AgentPresenceKind.working,
        'idle' => AgentPresenceKind.idle,
        _ => null,
      };
      if (parsed == null) return null;
      kind = parsed;
    } else {
      return null;
    }
    return AgentPresenceEvent(
      seat: PresenceSeatKey(sessionId: sessionId, memberId: memberId),
      eventKind: kind,
      timestamp: ts.toUtc(),
    );
  }
}
```

`session_lifecycle_transport_codec.dart`：

```dart
import 'dispatcher.dart';
import 'event_transport_codec.dart';
import 'session_lifecycle_event.dart';

final class SessionLifecycleTransportCodec implements EventTransportFamilyCodec {
  @override
  String get family => eventTransportFamilySessionLifecycle;

  @override
  Map<String, Object?> encode(DispatcherEvent event) {
    final e = event as SessionLifecycleEvent;
    return {
      'kind': e.eventKind.name,
      'sessionId': e.sessionId,
      'workspaceId': e.workspaceId,
      if (e.memberId != null) 'memberId': e.memberId,
      'ts': e.timestamp.toUtc().toIso8601String(),
    };
  }

  @override
  DispatcherEvent? decode(Map<String, Object?> payload) {
    final sessionId = payload['sessionId'] as String?;
    final workspaceId = payload['workspaceId'] as String?;
    final ts = DateTime.tryParse(payload['ts'] as String? ?? '');
    if (sessionId == null || workspaceId == null || ts == null) return null;
    final memberId = payload['memberId'] as String?;
    final utc = ts.toUtc();
    return switch (payload['kind'] as String?) {
      'sessionSpawned' => SessionLifecycleEvent.sessionSpawned(
        sessionId: sessionId, workspaceId: workspaceId, timestamp: utc,
      ),
      'sessionStarted' => SessionLifecycleEvent.sessionStarted(
        sessionId: sessionId, workspaceId: workspaceId, timestamp: utc,
      ),
      'sessionClosed' => SessionLifecycleEvent.sessionClosed(
        sessionId: sessionId, workspaceId: workspaceId, timestamp: utc,
      ),
      'seatStarted' when memberId != null => SessionLifecycleEvent.seatStarted(
        sessionId: sessionId, workspaceId: workspaceId, memberId: memberId,
        timestamp: utc,
      ),
      'seatInterrupted' when memberId != null =>
        SessionLifecycleEvent.seatInterrupted(
          sessionId: sessionId, workspaceId: workspaceId, memberId: memberId,
          timestamp: utc,
        ),
      'seatExited' when memberId != null => SessionLifecycleEvent.seatExited(
        sessionId: sessionId, workspaceId: workspaceId, memberId: memberId,
        timestamp: utc,
      ),
      _ => null,
    };
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/event/event_transport_codec_test.dart`

Expected: PASS。`cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/event/event_transport_codec.dart \
  client/lib/services/event/agent_presence_transport_codec.dart \
  client/lib/services/event/session_lifecycle_transport_codec.dart \
  client/test/services/event/event_transport_codec_test.dart
git commit -m "feat(event): NDJSON codecs for presence and session lifecycle"
```

---

### Task 4: EventTransportServer（loopback + 握手 + snapshot + fan-out）

**Files:**
- Create: `client/lib/services/event/event_transport_server.dart`
- Modify: `client/lib/services/storage/app_paths.dart`（加 `eventTransportJson` 路径 helper）
- Test: `client/test/services/event/event_transport_server_test.dart`

**Interfaces:**
- Consumes: Task 3 codecs、`AsyncDispatcher`、`AgentPresenceProjection`、`Filesystem`
- Produces:
  - `class EventTransportServer`
  - `Future<void> start()` / `Future<void> stop()`
  - bind `InternetAddress.loopbackIPv4` port 0
  - 写广告 JSON `{v, bindHost, port, pid, startedAt}`
  - 每连接：5s 内必须读到 `subscribe`；回复 `subscribed`（求交）；对 `agentPresence` 写 snapshotBegin/set*/snapshotEnd；然后 `registerFamily` 本连接 handler；断开 `unregister`
  - 构造注入：`Dispatcher dispatcher`、`AgentPresenceProjection presence`、`Filesystem fs`、`String advertisementPath`、`List<EventTransportFamilyCodec> codecs`、`Duration subscribeTimeout`、`DateTime Function() clock`、`int Function() pid`、`Future<ServerSocket> Function(InternetAddress host, int port)? bind`

- [ ] **Step 1: 写失败测试**

用真实 loopback（这不是 SSH）。测试文件覆盖：

1. `start` 后广告文件 `bindHost == 127.0.0.1` 且 `port > 0`
2. Client `Socket.connect` + 发 subscribe → 收到 subscribed（求交：请求含未知 family 时结果不含它）
3. 投影里有一个 working seat 时，subscribed 之后是 snapshotBegin、一条 set、snapshotEnd
4. 空投影：snapshotBegin 紧挨 snapshotEnd
5. 两个 socket 都能收到后来 `dispatcher.dispatch` 的同一条 presence set
6. subscribe 超时：不发 subscribe，连接在 timeout 后被关（用 `subscribeTimeout: Duration(milliseconds: 50)` + 短等）
7. 超长行：先发 subscribe 完成握手，再发 65537 字节无换行的垃圾，连接关闭

测试用 `InMemoryFilesystem` 写广告路径 `/tp/event-transport.json`。Server 的 `bind` 默认 `ServerSocket.bind`。

握手写：

```dart
await socket.add(utf8.encode(encodeTransportLine({
  'v': 1,
  'type': 'subscribe',
  'families': ['agentPresence', 'nope'],
})));
```

读侧用 `utf8.decoder.bind(socket).transform(const LineSplitter())`。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/event_transport_server_test.dart`

Expected: FAIL — server 不存在。

- [ ] **Step 3: 实现**

`AppPaths` 增加：

```dart
  String get eventTransportJson =>
      eventTransportJsonForTeampilotRoot(basePath);

  static String eventTransportJsonForTeampilotRoot(String teampilotRoot) =>
      _pathUnderTeampilotRoot(teampilotRoot, 'event-transport.json');
```

`event_transport_server.dart`（结构按此落，细节可微调但签名不能改）：

```dart
final class EventTransportServer {
  EventTransportServer({
    required Dispatcher dispatcher,
    required AgentPresenceProjection presence,
    required Filesystem fs,
    required String advertisementPath,
    required List<EventTransportFamilyCodec> codecs,
    this.subscribeTimeout = const Duration(seconds: 5),
    DateTime Function()? clock,
    int Function()? pid,
    Future<ServerSocket> Function(InternetAddress host, int port)? bind,
  });

  Future<void> start() async {
    _socket = await (_bind ?? ServerSocket.bind)(InternetAddress.loopbackIPv4, 0);
    await _fs.writeAsString(_advertisementPath, jsonEncode({
      'v': eventTransportProtocolVersion,
      'bindHost': '127.0.0.1',
      'port': _socket!.port,
      'pid': (_pid ?? pid)(),
      'startedAt': (_clock ?? DateTime.now)().toUtc().toIso8601String(),
    }));
    _accept = () async {
      await for (final client in _socket!) {
        unawaited(_serve(client));
      }
    }();
  }

  Future<void> _serve(Socket client) async {
    final handler = _ConnectionHandler(
      socket: client,
      codecs: _codecsByFamily,
      dispatcher: _dispatcher,
    );
    try {
      final subscribed = await _readSubscribe(client);
      if (subscribed == null) {
        client.destroy();
        return;
      }
      final families = subscribed.toSet().intersection(_codecsByFamily.keys.toSet());
      client.add(utf8.encode(encodeTransportLine({
        'v': eventTransportProtocolVersion,
        'type': 'subscribed',
        'families': families.toList(),
      })));
      if (families.contains(eventTransportFamilyAgentPresence)) {
        final snapshot = Map<PresenceSeatKey, AgentPresenceKind>.of(_presence.snapshot);
        _dispatcher.registerFamily<AgentPresenceKind>(
          AgentPresenceKind.working.runtimeType,
          handler,
        );
        if (families.contains(eventTransportFamilySessionLifecycle)) {
          _dispatcher.registerFamily<SessionLifecycleKind>(
            SessionLifecycleKind.sessionStarted.runtimeType,
            handler,
          );
        }
        client.add(utf8.encode(encodeTransportLine({
          'v': eventTransportProtocolVersion,
          'type': 'snapshotBegin',
          'family': eventTransportFamilyAgentPresence,
        })));
        final presenceCodec = _codecsByFamily[eventTransportFamilyAgentPresence]!;
        for (final e in snapshot.entries) {
          client.add(utf8.encode(encodeTransportLine({
            'v': eventTransportProtocolVersion,
            'type': 'event',
            'family': eventTransportFamilyAgentPresence,
            ...presenceCodec.encode(AgentPresenceEvent(
              seat: e.key,
              eventKind: e.value,
              timestamp: (_clock ?? DateTime.now)(),
            )),
          })));
        }
        client.add(utf8.encode(encodeTransportLine({
          'v': eventTransportProtocolVersion,
          'type': 'snapshotEnd',
          'family': eventTransportFamilyAgentPresence,
        })));
      }
      await client.done;
    } finally {
      _dispatcher.unregister(handler);
      client.destroy();
    }
  }
}
```

`_readSubscribe`：把 socket 字节拼进 buffer，遇到 `\n` 就 `tryDecodeTransportLine`；buffer 超 `eventTransportMaxLineBytes` 则写 `type=error, code=oversize` 并返回 null。与 `Future<void>.delayed(subscribeTimeout)` race，超时返回 null。首条 type 不是 `subscribe` 也返回 null。families 从 JSON list 里取出字符串。

`_ConnectionHandler.handle`：按 `event.runtimeType` / family 找 codec，`client.add(encodeTransportLine({v, type:event, family, ...codec.encode(event)}))`。写失败只 log。

`stop`：`_dispatcher.unregister` 每个 handler、`await _socket.close()`、`_fs.delete(advertisementPath)`（缺文件吞掉）。

注意：先拷贝 snapshot、再 `registerFamily`（presence 与 sessionLifecycle **各自独立**判断 families.contains，不要把 sessionLifecycle 注册嵌在 presence 的 if 里）、再写 snapshot 行——拷贝与注册之间不要 await。`pid` 用注入的 `int Function() pid`，测试传固定值。`Filesystem` 写/删广告：打开 `client/test/support/in_memory_filesystem.dart` 抄该 fake 已有的 write/delete 方法名，不要臆造 `writeAsString`。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/event/event_transport_server_test.dart`

Expected: PASS。`flutter analyze --no-fatal-infos --no-fatal-warnings`

负向超时测试用固定短 timeout，不要 `Future.delayed` 去赌 `bootMaxWait`；50ms timeout + `_waitFor(() => socket.done, timeout: Duration(seconds: 2))`。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/event/event_transport_server.dart \
  client/lib/services/storage/app_paths.dart \
  client/test/services/event/event_transport_server_test.dart
git commit -m "feat(event): loopback event transport server"
```

---

### Task 5: EventTransportClient（subscribe、snapshotBegin、dispatch、退避）

**Files:**
- Create: `client/lib/services/event/event_transport_client.dart`
- Test: `client/test/services/event/event_transport_client_test.dart`

**Interfaces:**
- Consumes: Task 3 codecs、`Dispatcher`、`AgentPresenceProjection`
- Produces:
  - `abstract interface class EventTransportByteChannel { Stream<List<int>> get incoming; void add(List<int> data); Future<void> close(); }`
  - `class EventTransportClient`
  - 构造：`Dispatcher dispatcher`、`AgentPresenceProjection presence`、`List<EventTransportFamilyCodec> codecs`、`Future<EventTransportByteChannel> Function() open`、`Duration Function(int attempt)? backoff`（默认 `Duration(seconds: 1 << attempt.clamp(0, 4))` 但 cap 在 30s：attempt 0→1s、1→2s、2→4s、3→8s、4+→16s 再 clamp 到 30s；测试传入 `(_) => Duration.zero`）、`void Function(Object error, StackTrace st)? onError`
  - `Future<void> start()` / `Future<void> stop()`
  - 连上立即 `channel.add(utf8.encode(subscribeLine))`；`snapshotBegin` + family agentPresence → `presence.clearAll()`；`type=event` → codec.decode → `dispatcher.dispatch`；incoming 结束则 `channel.close()` 后 backoff 再 `open()`
  - **不**读广告文件、不 SSH（Task 6 的 `open` 闭包才做这两件事）

用一对 `StreamController<List<int>>` 模拟字节流：测试驱动 inbound，断言 outbound subscribe 与 dispatch 结果。

- [ ] **Step 1: 写失败测试**

覆盖：

1. `start` 后 outbound 第一行是 subscribe（families 含 `agentPresence` 与 `sessionLifecycle`）
2. 推 snapshotBegin + 一条 set + snapshotEnd → 投影有该 seat；再推一条 clear → 投影空且 `changes` 收到
3. snapshotBegin 会清掉握手前本地投影里的旧 seat
4. `v:2` 行不 dispatch、不抛
5. 流 `close` 后 client 按 backoff 再调用 `open`（`backoff: (_) => Duration.zero`，计数 `open` 次数 ≥ 2）
6. `stop` 后不再重连

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/event/event_transport_client_test.dart`

Expected: FAIL — client 不存在。

- [ ] **Step 3: 实现**

```dart
abstract interface class EventTransportByteChannel {
  Stream<List<int>> get incoming;
  void add(List<int> data);
  Future<void> close();
}

final class EventTransportClient {
  EventTransportClient({
    required Dispatcher dispatcher,
    required AgentPresenceProjection presence,
    required List<EventTransportFamilyCodec> codecs,
    required Future<EventTransportByteChannel> Function() open,
    Duration Function(int attempt)? backoff,
  });

  Future<void> start() async {
    _running = true;
    unawaited(_run());
  }

  Future<void> stop() async {
    _running = false;
    await _channel?.close();
  }

  Future<void> _run() async {
    var attempt = 0;
    while (_running) {
      try {
        final channel = await _open();
        _channel = channel;
        attempt = 0;
        channel.add(utf8.encode(encodeTransportLine({
          'v': eventTransportProtocolVersion,
          'type': 'subscribe',
          'families': [
            eventTransportFamilyAgentPresence,
            eventTransportFamilySessionLifecycle,
          ],
        })));
        final buffer = <int>[];
        await for (final chunk in channel.incoming) {
          if (!_running) break;
          buffer.addAll(chunk);
          while (true) {
            final nl = buffer.indexOf(10);
            if (nl < 0) {
              if (buffer.length > eventTransportMaxLineBytes) {
                break;
              }
              break;
            }
            final line = utf8.decode(buffer.sublist(0, nl));
            buffer.removeRange(0, nl + 1);
            _onLine(line);
          }
        }
      } catch (e, st) {
        appLogger.w('[event-transport] client loop', error: e, stackTrace: st);
      } finally {
        await _channel?.close();
        _channel = null;
      }
      if (!_running) break;
      await Future<void>.delayed(_backoff(attempt++));
    }
  }
}
```

`_onLine`：`tryDecodeTransportLine` 为 null 则 return。`type==snapshotBegin` 且 family 为 agentPresence → `presence.clearAll()`。`type==event` → 按 family 找 codec → `decode` → 非 null 则 `dispatcher.dispatch`。`type==error` → log 后 `unawaited(_channel?.close())`。`snapshotEnd` / `subscribed` 忽略。

Client **不要**自己 `projection.handle`。测试用真实 `AsyncDispatcher` 注册 projection，等待用：

```dart
Future<void> _waitFor(bool Function() ok, {required Duration timeout}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) {
      fail('timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/event/event_transport_client_test.dart`

Expected: PASS。analyze 干净。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/event/event_transport_client.dart \
  client/test/services/event/event_transport_client_test.dart
git commit -m "feat(event): event transport client over an injected byte stream"
```

---

### Task 6: 角色接线、occupancy、文档

**Files:**
- Create: `client/lib/services/event/event_transport_controller.dart`
- Modify: `client/lib/app/app_shell.dart`
- Modify: `client/lib/cubits/member_presence_cubit.dart`（`MemberPresenceState.occupiedSessionIds`；投影 `changes` 时 emit）
- Modify: `client/lib/utils/session/workspace_running_sessions.dart`
- Modify: `client/lib/utils/session/running_session_ids.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart`（把 occupied ids 并进 running 列表）
- Modify: `client/test/app/agent_presence_wiring_test.dart`（**只追加**断言，不改现有四条；允许加「ssh home 不构造 bridge」的源码针）
- Test: `client/test/services/event/event_transport_controller_test.dart`
- Test: `client/test/utils/session/workspace_running_sessions_test.dart`（追加 occupied 用例，不改旧断言）
- Test: `client/test/cubits/member_presence_cubit_events_test.dart`（**追加** occupied emit 用例）
- Modify: `docs/workspace-storage-layout.md`、`client/lib/services/event/README.md`

**Interfaces:**
- Consumes: Server、Client、`ConnectionModeService`、`SshClientFactory.clientForStorage`、`HomeStorage`
- Produces:
  - `enum EventTransportRole { server, client, none }`
  - `class EventTransportController` — `Future<void> apply(EventTransportRole role, {EventTransportByteChannel? channel})`；进程一份；`server` 起 Server 停 Client；`client` 反之；`none` 都停
  - `EventTransportByteChannel`：`Stream<List<int>> get incoming` / `void add(List<int> data)` / `Future<void> close()`（接线层用 `forwardLocal` 填这个，controller 不 import dartssh2）
  - local home：`role=server`，cubit **带** bridge
  - ssh home：`role=client`，cubit **不带** bridge，channel = `sshClient.forwardLocal('127.0.0.1', port)`（port 来自 `HomeStorage` 读到的广告文件）
  - Termux：`role=none`，bridge 保持今天（生产者）
  - `workspaceRunningSessions` 增加命名参数 `Set<String> occupiedSessionIds = const {}`，在 busy 与 open tabs 之后 `addIds(occupiedSessionIds)`
  - `MemberPresenceState.occupiedSessionIds`；投影变化时若 set 变化则 emit

- [ ] **Step 1: 写失败测试**

Controller 测试（假 Server/Client 工厂，不要真端口）：记录 `apply` 起停顺序。`apply(server)` 再 `apply(client)` 必须先 stop server 再 start client。

`workspace_running_sessions_test.dart` 追加：

```dart
    test('occupied sessions appear even without local busy or open tabs', () {
      final sessions = [session('a'), session('b')];
      final result = workspaceRunningSessions(
        sessions: sessions,
        busySessionIds: const {},
        openTabSessionIds: const {},
        occupiedSessionIds: {'b'},
      );
      expect(result.map((s) => s.sessionId), ['b']);
    });
```

Cubit 追加：无 target 时投影 `handle(working)` → `state.occupiedSessionIds` 含该 sessionId。

Wiring 测试追加：`app_shell.dart` 源码含 `connectionModeService.isSshMode` 决定是否构造 `PresenceEventBridge`（针要匹配你落下的真实字符，写实现后再把针改成与源码一致——先写测试针 `PresenceEventBridge(sink: presenceSink)` 仍在 **非 ssh** 分支）。先写：

```dart
    test('ssh home does not construct PresenceEventBridge', () {
      expect(
        src.contains('connectionModeService.isSshMode'),
        isTrue,
      );
      expect(
        RegExp(
          r'presenceBridge:\s*presenceSink == null\s*\|\|\s*connectionModeService\.isSshMode',
        ).hasMatch(src),
        isTrue,
        reason: 'consumer-only ssh home must not publish presence back',
      );
    });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/utils/session/workspace_running_sessions_test.dart test/app/agent_presence_wiring_test.dart test/services/event/event_transport_controller_test.dart`

Expected: FAIL — occupied 参数 / controller / 接线针不存在。

- [ ] **Step 3: 实现**

1. `workspaceRunningSessions` 增加 `occupiedSessionIds`，`addIds` 第三段。空集合时旧行为不变（旧测试不改）。
2. `RunningSessionIds.fromOpenSessionTabs` / `fromWorkspace` 把 occupied 传下去。sidebar 两处 `context.select` 增加 `occupiedSessionIds: context.read<MemberPresenceCubit>().state.occupiedSessionIds`。select 依赖必须包含 occupied（用 `context.select` 同时读 ChatCubit 与 MemberPresenceCubit 会不方便）——改成：

```dart
final occupied = context.select<MemberPresenceCubit, Set<String>>(
  (c) => c.state.occupiedSessionIds,
);
final running = context.select<ChatCubit, RunningSessionIds>(
  (c) => RunningSessionIds.fromOpenSessionTabs(
    sessions: sessionsForWorkspace(workspace, c.state.sessions),
    openTabSessionIdsInOrder: [...],
    occupiedSessionIds: occupied,
  ),
);
```

3. `MemberPresenceState` 加 `occupiedSessionIds`（默认 `const {}`），写入 `props`。`_onProjectionSeatChanged`：

```dart
  void _onProjectionSeatChanged(PresenceSeatKey seat) {
    _onProjectionChanged?.call();
    final occupied = _presenceProjection?.occupiedSessionIds ?? const <String>{};
    if (!setEquals(state.occupiedSessionIds, occupied)) {
      emit(state.copyWith(occupiedSessionIds: occupied));
    }
    _requestPresenceRecompute();
  }
```

`close()` 时 emit 空 occupied。

4. `buildAppShell` 里 cubit：

```dart
      presenceBridge: presenceSink == null || connectionModeService.isSshMode
          ? null
          : PresenceEventBridge(sink: presenceSink),
```

5. `EventTransportController` 持有可选 server/client。`apply` 幂等。

6. Bootstrap state 里 controller 与 dispatcher/projection 一样进程一份。`buildAppShell` 返回后 / `switchHomeTarget` 之后调用 `apply`：
   - `isLocalMode` → server，`advertisementPath = homeStorage.paths.eventTransportJson`，`fs = homeStorage` 的 filesystem
   - `isSshMode` → 读广告（缺文件则 client 不 start，由 controller 定时重读：复用 Client 的 backoff 包一层 `open:` 先 `fs.read` 广告再 `forwardLocal`）。`forwardLocal` 包成 `EventTransportByteChannel`。SSH client 用现有 `sshClientFactory.clientForStorage(homeProfile)`。
   - 否则 `none`

`forwardLocal` 失败：log，不抛给 UI。

7. 文档：`workspace-storage-layout.md` 顶层清单加 `event-transport.json`。`services/event/README.md` 加 Event Transport 段：角色表、NDJSON、`cleared` ↔ `op:clear`、失败降级。

- [ ] **Step 4: 跑测试确认通过**

Run:

```
cd client && dart run tool/run_tests.dart \
  test/utils/session/workspace_running_sessions_test.dart \
  test/app/agent_presence_wiring_test.dart \
  test/services/event/event_transport_controller_test.dart \
  test/services/event/event_transport_server_test.dart \
  test/services/event/event_transport_client_test.dart \
  test/services/event/presence_event_bridge_test.dart \
  test/cubits/member_presence_cubit_events_test.dart \
  test/cubits/member_presence_cubit_test.dart
```

Expected: PASS。`flutter analyze --no-fatal-infos --no-fatal-warnings` 干净。

然后全套一次：`cd client && dart run tool/run_tests.dart`。摘要允许那条无关的 floating_workspace 失败。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/event/event_transport_controller.dart \
  client/lib/app/app_shell.dart \
  client/lib/cubits/member_presence_cubit.dart \
  client/lib/utils/session/workspace_running_sessions.dart \
  client/lib/utils/session/running_session_ids.dart \
  client/lib/pages/home_workspace/workspace/workspace_sidebar.dart \
  client/test/app/agent_presence_wiring_test.dart \
  client/test/services/event/event_transport_controller_test.dart \
  client/test/utils/session/workspace_running_sessions_test.dart \
  client/test/cubits/member_presence_cubit_events_test.dart \
  docs/workspace-storage-layout.md \
  client/lib/services/event/README.md
git commit -m "feat(event): wire event transport by home role"
```

---

## Spec coverage (self-review)

| Spec 要求 | Task |
|---|---|
| `cleared` 进 dispatcher / 投影广播 / `clearAll` | 1 |
| `reportAvailability(null)` 发墓碑 | 2 |
| NDJSON、`v!=1` 丢弃、64KiB、两 family codec | 3 |
| Server loopback、广告文件、握手求交、snapshot、多 Client fan-out、subscribe 超时 | 4 |
| Client subscribe、snapshotBegin 清空、dispatch、退避重连 | 5 |
| 角色互斥、ssh 无 bridge、occupancy、文档、失败不进 UI | 6 |
| 不做聊天失效 / daemon / ping / unix socket / agent_runtime | 全局约束 |
| sessionLifecycle 手机无新 UI 消费者 | 5 只 dispatch，6 不接 UI |

广告文件重读（桌面晚于手机启动）落在 Task 6 的 ssh `open:` 闭包里，与 Client backoff 组合，不另开任务。
