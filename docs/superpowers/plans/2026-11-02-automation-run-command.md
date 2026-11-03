# runCommand 定时任务 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 TeamPilot 的 automation 增加第三种动作 `runCommand`，到点在 workspace 所在的运行时（本地 / WSL / SSH / Termux）执行一行 shell 命令，并把 exit code、输出尾部、耗时写入运行历史。

**Architecture:** 调度器只负责「到点认领」（写 `nextRunAtMs`），命令执行交给独立的 `AutomationCommandExecutor` 串行队列，避免长命令占住调度循环；执行层复用 `ProcessRunExecutor`（流式、可 kill）与 `RunTargetResolver`，超时用 `stop()` 真杀进程。MCP 与 UI 共用同一模型层校验。

**Tech Stack:** Flutter/Dart、`package:process` 无、`dart:io` `Process`、`package:path`、`package:clock` 无、`flutter_bloc`、`dartssh2`（经由既有 `ProcessRunExecutor`）。

## Global Constraints

- 禁止直接跑 `flutter test`；统一 `cd client && dart run tool/run_tests.dart <path>`。
- 每个任务结束前跑 `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`。
- 全部完成后跑一次全量：`cd client && dart run tool/run_tests.dart`。
- l10n 只改 `client/lib/l10n/app_en.arb` 与 `app_zh.arb`，改完跑 `cd client && flutter gen-l10n`（生成文件已入库）。
- 诊断日志用 `AppLogger`，用户可见文案走 l10n，禁止 `print`。
- 命令长度上限 2000 字符；`timeoutSeconds` 范围 30–1800，默认 300；输出尾部上限 4096 字节（每条流）。
- `runCommand` 的 `sessionId` / `presetId` / `teamId` 必须为空，`reuseSession` 必须为 false。
- 现有 `scheduledMessage` / `launchPrompt` 行为不得改变（包括「MCP 创建恒为禁用」）。

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `client/lib/models/automation.dart` | 模型：新 action、`runCommand` 字段、run 结果字段、校验 |
| `client/lib/services/automation/automation_tail_buffer.dart` | 按字节上限保留输出尾部 |
| `client/lib/services/automation/automation_run_accounting.dart` | 运行后推进 `runCount` / `lastRunAtMs` / `nextRunAtMs` / 上限停用 |
| `client/lib/services/automation/automation_command_runner.dart` | 命令执行接口 + `ProcessRunExecutor` 实现（含目标解析、超时、输出收集） |
| `client/lib/services/automation/automation_command_executor.dart` | 串行队列、防重叠、写 `AutomationRun`、调用 accounting |
| `client/lib/services/automation/automation_scheduler.dart` | 认领与执行解耦、补跑、中断清理 |
| `client/lib/services/automation/automation_dispatcher.dart` | 拒绝 `runCommand`、委托 accounting |
| `client/lib/services/catalog/modules/automation_catalog_*.dart` | MCP schema 与 create/update 分支 |
| `client/lib/app/app_shell.dart` | 组装 runner / executor，注入 scheduler |
| `client/lib/pages/automations/**` | 编辑器第三选项、列表映射、运行结果展示 |

---

### Task 1: 模型层支持 runCommand

**Files:**
- Modify: `client/lib/models/automation.dart`
- Test: `client/test/models/automation_test.dart`

**Interfaces:**
- Produces: `enum AutomationAction { scheduledMessage, launchPrompt, runCommand }`；
  `enum AutomationCatchUpPolicy { none, once }`；
  `Automation.command`（`String?`）、`Automation.timeoutSeconds`（`int`，默认 300）、
  `Automation.catchUpPolicy`（`AutomationCatchUpPolicy`，默认 `none`）、`Automation.isRunCommand`；
  `AutomationRun.exitCode` / `stdoutTail` / `stderrTail` / `outputTruncated` / `durationMs`；
  `AutomationRunStatus.failed` / `timedOut` / `skippedOverlap`。

- [ ] **Step 1: 写失败测试**

在 `client/test/models/automation_test.dart` 末尾追加（若文件已有 `_baseAutomation` 辅助函数则复用其命名风格；下面自带构造）：

```dart
Automation _runCommandAutomation({
  String command = 'echo hi',
  int timeoutSeconds = 300,
  AutomationCatchUpPolicy catchUpPolicy = AutomationCatchUpPolicy.none,
  String? sessionId,
}) {
  return Automation(
    id: 'a1',
    name: 'nightly',
    action: AutomationAction.runCommand,
    workspaceId: 'ws1',
    command: command,
    timeoutSeconds: timeoutSeconds,
    catchUpPolicy: catchUpPolicy,
    sessionId: sessionId,
    message: '',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '02:00',
    timezone: 'Asia/Shanghai',
    dtstartMs: 1000,
    createdAtMs: 1000,
    updatedAtMs: 1000,
  );
}

test('runCommand does not require a message', () {
  _runCommandAutomation().validate();
});

test('runCommand rejects empty command', () {
  expect(
    () => _runCommandAutomation(command: '  ').validate(),
    throwsA(isA<ArgumentError>()),
  );
});

test('runCommand rejects command over 2000 characters', () {
  expect(
    () => _runCommandAutomation(command: 'a' * 2001).validate(),
    throwsA(isA<ArgumentError>()),
  );
});

test('runCommand rejects out-of-range timeoutSeconds', () {
  expect(
    () => _runCommandAutomation(timeoutSeconds: 10).validate(),
    throwsA(isA<ArgumentError>()),
  );
  expect(
    () => _runCommandAutomation(timeoutSeconds: 1801).validate(),
    throwsA(isA<ArgumentError>()),
  );
});

test('runCommand rejects a bound session', () {
  expect(
    () => _runCommandAutomation(sessionId: 's1').validate(),
    throwsA(isA<ArgumentError>()),
  );
});

test('runCommand json round-trips', () {
  final original = _runCommandAutomation(
    command: 'npm ci && npm run build',
    timeoutSeconds: 900,
    catchUpPolicy: AutomationCatchUpPolicy.once,
  );
  final restored = Automation.fromJson(original.toJson());
  expect(restored, original);
  expect(restored.isRunCommand, isTrue);
  expect(restored.timeoutSeconds, 900);
  expect(restored.catchUpPolicy, AutomationCatchUpPolicy.once);
});

test('legacy json without runCommand fields still parses', () {
  final json = <String, Object?>{
    'id': 'a1',
    'name': 'daily',
    'action': 'scheduledMessage',
    'workspaceId': 'ws1',
    'sessionId': 's1',
    'message': 'hi',
    'preset': 'daily',
    'hourMinute': '09:00',
    'timezone': 'Asia/Shanghai',
    'dtstartMs': 1000,
    'createdAtMs': 1000,
    'updatedAtMs': 1000,
  };
  final restored = Automation.fromJson(json);
  expect(restored.timeoutSeconds, 300);
  expect(restored.catchUpPolicy, AutomationCatchUpPolicy.none);
  expect(restored.command, isNull);
});

test('AutomationRun carries command result fields', () {
  const run = AutomationRun(
    id: 'r1',
    automationId: 'a1',
    workspaceId: 'ws1',
    scheduledForMs: 1000,
    status: AutomationRunStatus.failed,
    trigger: AutomationRunTrigger.scheduled,
    exitCode: 2,
    stdoutTail: 'out',
    stderrTail: 'err',
    outputTruncated: true,
    durationMs: 1234,
  );
  final restored = AutomationRun.fromJson(run.toJson());
  expect(restored, run);
  expect(restored.exitCode, 2);
  expect(restored.outputTruncated, isTrue);
  expect(restored.durationMs, 1234);
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/models/automation_test.dart`
Expected: 编译失败 —— `command` / `timeoutSeconds` / `catchUpPolicy` 未定义。

- [ ] **Step 3: 改模型**

`client/lib/models/automation.dart`：

```dart
enum AutomationAction { scheduledMessage, launchPrompt, runCommand }

enum AutomationCatchUpPolicy { none, once }

enum AutomationRunStatus {
  pending,
  dispatching,
  dispatched,
  completed,
  failed,
  timedOut,
  skippedUnavailable,
  skippedMissed,
  skippedOverlap,
  dispatchFailed,
}
```

`Automation` 构造函数加参数（放在 `message` 之后）：

```dart
    this.command,
    this.timeoutSeconds = 300,
    this.catchUpPolicy = AutomationCatchUpPolicy.none,
```

字段与 getter：

```dart
  /// One-line shell command executed when [action] is [AutomationAction.runCommand].
  final String? command;
  final int timeoutSeconds;
  final AutomationCatchUpPolicy catchUpPolicy;

  bool get isRunCommand => action == AutomationAction.runCommand;
```

`fromJson` 追加：

```dart
      command: json['command'] as String?,
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 300,
      catchUpPolicy:
          _enumByName(
            AutomationCatchUpPolicy.values,
            json['catchUpPolicy'],
          ) ??
          AutomationCatchUpPolicy.none,
```

`toJson` 追加（放在 `if (sessionId != null …)` 之前）：

```dart
      if (isRunCommand) ...{
        'command': command,
        'timeoutSeconds': timeoutSeconds,
        'catchUpPolicy': catchUpPolicy.name,
      },
```

`copyWith` 加参数与赋值：

```dart
    String? command,
    bool clearCommand = false,
    int? timeoutSeconds,
    AutomationCatchUpPolicy? catchUpPolicy,
```

```dart
      command: clearCommand ? null : (command ?? this.command),
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      catchUpPolicy: catchUpPolicy ?? this.catchUpPolicy,
```

`==` 与 `hashCode` 追加 `command`、`timeoutSeconds`、`catchUpPolicy`。

`validate()`：把开头无条件的 `message` 检查删掉，改为按 action 分支：

```dart
    switch (action) {
      case AutomationAction.scheduledMessage:
        if (message.trim().isEmpty) {
          throw ArgumentError('Automation message is required');
        }
        if (sessionId == null || sessionId!.trim().isEmpty) {
          throw ArgumentError('scheduledMessage requires sessionId');
        }
        if (reuseSession) {
          throw ArgumentError('scheduledMessage must not reuse session');
        }
      case AutomationAction.launchPrompt:
        if (message.trim().isEmpty) {
          throw ArgumentError('Automation message is required');
        }
        if (isPersonal) {
          if (presetId == null || presetId!.trim().isEmpty) {
            throw ArgumentError('launchPrompt simple mode requires presetId');
          }
        } else {
          if (teamId == null || teamId!.trim().isEmpty) {
            throw ArgumentError('launchPrompt team mode requires teamId');
          }
          if (targetMemberId.trim().isEmpty) {
            throw ArgumentError(
              'launchPrompt team mode requires targetMemberId',
            );
          }
        }
      case AutomationAction.runCommand:
        final cmd = command?.trim() ?? '';
        if (cmd.isEmpty) {
          throw ArgumentError('runCommand requires command');
        }
        if (cmd.length > 2000) {
          throw ArgumentError('command must be at most 2000 characters');
        }
        if (timeoutSeconds < 30 || timeoutSeconds > 1800) {
          throw ArgumentError('timeoutSeconds must be 30..1800');
        }
        if (sessionId != null && sessionId!.trim().isNotEmpty) {
          throw ArgumentError('runCommand must not bind a session');
        }
        if (presetId != null || teamId != null) {
          throw ArgumentError('runCommand must not carry a launch identity');
        }
        if (reuseSession) {
          throw ArgumentError('runCommand must not reuse session');
        }
    }
```

`AutomationRun` 加字段：

```dart
    this.exitCode,
    this.stdoutTail,
    this.stderrTail,
    this.outputTruncated = false,
    this.durationMs,
```

```dart
  final int? exitCode;
  final String? stdoutTail;
  final String? stderrTail;
  final bool outputTruncated;
  final int? durationMs;
```

`fromJson`：

```dart
      exitCode: (json['exitCode'] as num?)?.toInt(),
      stdoutTail: json['stdoutTail'] as String?,
      stderrTail: json['stderrTail'] as String?,
      outputTruncated: json['outputTruncated'] as bool? ?? false,
      durationMs: (json['durationMs'] as num?)?.toInt(),
```

`copyWith`：

```dart
    int? exitCode,
    bool clearExitCode = false,
    String? stdoutTail,
    bool clearStdoutTail = false,
    String? stderrTail,
    bool clearStderrTail = false,
    bool? outputTruncated,
    int? durationMs,
    bool clearDurationMs = false,
```

```dart
      exitCode: clearExitCode ? null : (exitCode ?? this.exitCode),
      stdoutTail: clearStdoutTail ? null : (stdoutTail ?? this.stdoutTail),
      stderrTail: clearStderrTail ? null : (stderrTail ?? this.stderrTail),
      outputTruncated: outputTruncated ?? this.outputTruncated,
      durationMs: clearDurationMs ? null : (durationMs ?? this.durationMs),
```

`toJson`：

```dart
      if (exitCode != null) 'exitCode': exitCode,
      if (stdoutTail != null && stdoutTail!.isNotEmpty) 'stdoutTail': stdoutTail,
      if (stderrTail != null && stderrTail!.isNotEmpty) 'stderrTail': stderrTail,
      if (outputTruncated) 'outputTruncated': true,
      if (durationMs != null) 'durationMs': durationMs,
```

`==` 与 `hashCode` 同步加入这五个字段。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/models/automation_test.dart`
Expected: PASS（原有测试也必须全绿——`validate()` 重构不能改变两种旧动作的错误文案）。

- [ ] **Step 5: 提交**

```bash
git add client/lib/models/automation.dart client/test/models/automation_test.dart
git commit -m "feat(automation): add runCommand action and command run fields"
```

---

### Task 2: 输出尾部缓冲

**Files:**
- Create: `client/lib/services/automation/automation_tail_buffer.dart`
- Test: `client/test/services/automation/automation_tail_buffer_test.dart`

**Interfaces:**
- Produces: `AutomationTailBuffer({int maxBytes = 4096})`，成员 `void add(String chunk)`、
  `String get text`、`bool get truncated`。

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/automation/automation_tail_buffer.dart';

void main() {
  test('keeps everything under the limit', () {
    final buffer = AutomationTailBuffer(maxBytes: 16);
    buffer.add('hello ');
    buffer.add('world');
    expect(buffer.text, 'hello world');
    expect(buffer.truncated, isFalse);
  });

  test('keeps only the tail and flags truncation', () {
    final buffer = AutomationTailBuffer(maxBytes: 8);
    buffer.add('abcdefghij');
    expect(buffer.text, 'cdefghij');
    expect(buffer.truncated, isTrue);
  });

  test('does not split multi-byte characters', () {
    final buffer = AutomationTailBuffer(maxBytes: 4);
    buffer.add('中文测试');
    expect(buffer.text.endsWith('试'), isTrue);
    expect(buffer.text.contains('\uFFFD'), isFalse);
    expect(buffer.truncated, isTrue);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_tail_buffer_test.dart`
Expected: 编译失败 —— 目标文件不存在。

- [ ] **Step 3: 实现**

```dart
import 'dart:convert';

/// Keeps the last [maxBytes] UTF-8 bytes of a stream of text.
///
/// Command output is unbounded; only the tail is useful for diagnosing a
/// failure, so the head is dropped once the budget is exceeded.
class AutomationTailBuffer {
  AutomationTailBuffer({this.maxBytes = 4096}) : assert(maxBytes > 0);

  static final RegExp _leadingReplacement = RegExp('^\uFFFD+');

  final int maxBytes;
  final StringBuffer _buffer = StringBuffer();
  bool _truncated = false;

  String get text => _buffer.toString();

  bool get truncated => _truncated;

  void add(String chunk) {
    if (chunk.isEmpty) return;
    _buffer.write(chunk);
    _truncateIfNeeded();
  }

  void _truncateIfNeeded() {
    final raw = _buffer.toString();
    final bytes = utf8.encode(raw);
    if (bytes.length <= maxBytes) return;

    _truncated = true;
    final tail = utf8.decode(
      bytes.sublist(bytes.length - maxBytes),
      allowMalformed: true,
    );
    final cleaned = tail.replaceFirst(_leadingReplacement, '');
    _buffer
      ..clear()
      ..write(cleaned);
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_tail_buffer_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/automation/automation_tail_buffer.dart client/test/services/automation/automation_tail_buffer_test.dart
git commit -m "feat(automation): add output tail buffer"
```

---

### Task 3: 抽取运行计数推进

**Files:**
- Create: `client/lib/services/automation/automation_run_accounting.dart`
- Modify: `client/lib/services/automation/automation_dispatcher.dart:411-441`
- Test: `client/test/services/automation/automation_run_accounting_test.dart`

**Interfaces:**
- Consumes: `AutomationScheduleCalculator.computeNextRunAtMs(Automation, {required int afterMs})`。
- Produces: `AutomationRunAccounting(AutomationScheduleCalculator)` 的
  `Automation advance({required Automation automation, required int lastRunAtMs, required int nowMs, String? dispatchedSessionId})`。

- [ ] **Step 1: 写失败测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/services/automation/automation_run_accounting.dart';
import 'package:teampilot/services/automation/automation_schedule_calculator.dart';

Automation _daily({int maxRunCount = 0, bool enabled = true}) {
  return Automation(
    id: 'a1',
    name: 'daily',
    action: AutomationAction.runCommand,
    workspaceId: 'ws1',
    command: 'echo hi',
    message: '',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '02:00',
    timezone: 'Asia/Shanghai',
    dtstartMs: 0,
    maxRunCount: maxRunCount == 0 ? null : maxRunCount,
    enabled: enabled,
    createdAtMs: 0,
    updatedAtMs: 0,
  );
}

void main() {
  final accounting = AutomationRunAccounting(AutomationScheduleCalculator());

  test('increments runCount and recomputes next run', () {
    final now = DateTime(2026, 11, 2, 3).millisecondsSinceEpoch;
    final next = accounting.advance(
      automation: _daily(),
      lastRunAtMs: now,
      nowMs: now,
    );
    expect(next.runCount, 1);
    expect(next.lastRunAtMs, now);
    expect(next.enabled, isTrue);
    expect(next.nextRunAtMs, isNotNull);
    expect(next.nextRunAtMs! > now, isTrue);
  });

  test('disables when the run limit is reached', () {
    final now = DateTime(2026, 11, 2, 3).millisecondsSinceEpoch;
    final next = accounting.advance(
      automation: _daily(maxRunCount: 1),
      lastRunAtMs: now,
      nowMs: now,
    );
    expect(next.runCount, 1);
    expect(next.enabled, isFalse);
    expect(next.nextRunAtMs, isNull);
  });

  test('leaves a disabled automation disabled', () {
    final now = DateTime(2026, 11, 2, 3).millisecondsSinceEpoch;
    final next = accounting.advance(
      automation: _daily(enabled: false),
      lastRunAtMs: now,
      nowMs: now,
    );
    expect(next.enabled, isFalse);
    expect(next.nextRunAtMs, isNull);
    expect(next.runCount, 1);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_run_accounting_test.dart`
Expected: 编译失败 —— 目标文件不存在。

- [ ] **Step 3: 实现并接入 dispatcher**

```dart
import '../../models/automation.dart';
import 'automation_schedule_calculator.dart';

/// Advances an automation after a run finishes: counts the run, stamps it,
/// and resolves the next occurrence (or disables on limit expiry).
class AutomationRunAccounting {
  const AutomationRunAccounting(this._scheduleCalculator);

  final AutomationScheduleCalculator _scheduleCalculator;

  Automation advance({
    required Automation automation,
    required int lastRunAtMs,
    required int nowMs,
  }) {
    final nextRunCount = automation.runCount + 1;
    final max = automation.effectiveMaxRunCount;
    final limitReached = max != null && nextRunCount >= max;
    final stillEnabled = automation.enabled && !limitReached;
    final nextRunAtMs = stillEnabled
        ? _scheduleCalculator.computeNextRunAtMs(
            automation,
            afterMs: lastRunAtMs,
          )
        : null;
    return automation.copyWith(
      lastRunAtMs: lastRunAtMs,
      runCount: nextRunCount,
      enabled: stillEnabled,
      nextRunAtMs: nextRunAtMs,
      clearNextRunAtMs: nextRunAtMs == null,
      updatedAtMs: nowMs,
    );
  }
}
```

在 `automation_dispatcher.dart` 中把 `_advanceAutomationAfterRun` 改成委托（保留 `dispatchedSessionId` 的 binding 逻辑）：

```dart
  late final AutomationRunAccounting _accounting = AutomationRunAccounting(
    _scheduleCalculator,
  );

  Automation _advanceAutomationAfterRun(
    Automation automation, {
    required int lastRunAtMs,
    String? dispatchedSessionId,
  }) {
    var updated = _accounting.advance(
      automation: automation,
      lastRunAtMs: lastRunAtMs,
      nowMs: _nowMs(),
    );
    if (dispatchedSessionId != null && dispatchedSessionId.trim().isNotEmpty) {
      updated = AutomationLaunchSessionBinding.applyAfterSuccessfulDispatch(
        updated,
        sessionId: dispatchedSessionId,
      );
    }
    return updated;
  }
```

补 `import 'automation_run_accounting.dart';`。

- [ ] **Step 4: 跑测试**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_run_accounting_test.dart test/services/automation/automation_dispatcher_test.dart`
Expected: PASS（原有 dispatcher 行为不变）

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/automation/automation_run_accounting.dart client/lib/services/automation/automation_dispatcher.dart client/test/services/automation/automation_run_accounting_test.dart
git commit -m "refactor(automation): extract run accounting from dispatcher"
```

---

### Task 4: 命令执行器（runner）

**Files:**
- Create: `client/lib/services/automation/automation_command_runner.dart`
- Test: `client/test/services/automation/automation_command_runner_test.dart`

**Interfaces:**
- Consumes: `ProcessRunExecutor.start({required String sessionId, required String command, required List<String> args, required RunTargetPlan plan, Map<String,String>? env, bool shell, required void Function(ProcessRunOutput) onOutput})`
  → `Future<ProcessRunResult>`；`ProcessRunResult.exitCode`（`Future<int>`）、`ProcessRunResult.stop`（`Future<void> Function()`）；
  `RunTargetResolver.resolve({required WorkspaceFolder owner, String? cwd, Map<String,String> env})` → `RunTargetPlan`；
  `RuntimeKind { local, wsl, ssh, termux }`。
- Produces:
  `AutomationCommandRequest({required String workspaceId, required String command, String? workingDirectoryPath, int timeoutSeconds = 300, int outputTailBytes = 4096})`；
  `AutomationCommandOutcome({int? exitCode, String stdoutTail = '', String stderrTail = '', bool truncated = false, bool timedOut = false, int durationMs = 0, String? error})`，含
  `AutomationRunStatus get status`；
  `abstract interface class AutomationCommandRunner { Future<AutomationCommandOutcome> run(AutomationCommandRequest request); }`；
  `HostAutomationCommandRunner({required Workspace? Function(String) workspaceById, required RunTargetResolver resolver, required ProcessRunExecutor executor})`。

- [ ] **Step 1: 写失败测试**

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/automation/automation_command_runner.dart';
import 'package:teampilot/services/run/process_run_executor.dart';
import 'package:teampilot/services/run/process_run_handle.dart';
import 'package:teampilot/services/run/run_target_resolver.dart';

class _FakeHandle implements ProcessRunHandle {
  _FakeHandle({this.exit = 0, this.stdoutChunks = const [], this.stderrChunks = const []});

  final int exit;
  final List<String> stdoutChunks;
  final List<String> stderrChunks;
  bool killed = false;

  @override
  Future<int> get exitCode async => exit;

  @override
  Stream<List<int>> get stdout => Stream.fromIterable(
    stdoutChunks.map((c) => c.codeUnits),
  );

  @override
  Stream<List<int>> get stderr => Stream.fromIterable(
    stderrChunks.map((c) => c.codeUnits),
  );

  @override
  void kill() => killed = true;
}

Workspace _workspace(List<WorkspaceFolder> folders) => Workspace(
  workspaceId: 'ws1',
  folders: folders,
  display: 'ws1',
  defaultProfileId: '',
);

void main() {
  test('captures exit code and output tail', () async {
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace([
        const WorkspaceFolder(path: '/repo'),
      ]),
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: ProcessRunExecutor(
        spawner: ({
          required executable,
          required arguments,
          required workingDirectory,
          environment,
          runInShell = false,
          includeParentEnvironment = true,
        }) async => _FakeHandle(
          exit: 2,
          stdoutChunks: const ['built ok'],
          stderrChunks: const ['boom'],
        ),
      ),
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(
        workspaceId: 'ws1',
        command: 'make',
        workingDirectoryPath: '/repo',
      ),
    );

    expect(outcome.exitCode, 2);
    expect(outcome.stdoutTail, 'built ok');
    expect(outcome.stderrTail, 'boom');
    expect(outcome.timedOut, isFalse);
    expect(outcome.status, AutomationRunStatus.failed);
  });

  test('kills the process on timeout', () async {
    final handle = _HungHandle();
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace([
        const WorkspaceFolder(path: '/repo'),
      ]),
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: ProcessRunExecutor(
        spawner: ({
          required executable,
          required arguments,
          required workingDirectory,
          environment,
          runInShell = false,
          includeParentEnvironment = true,
        }) async => handle,
      ),
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(
        workspaceId: 'ws1',
        command: 'sleep 999',
        timeoutSeconds: 30,
      ),
    );

    expect(outcome.timedOut, isTrue);
    expect(outcome.status, AutomationRunStatus.timedOut);
    expect(handle.killed, isTrue);
  });

  test('rejects a working directory outside the workspace', () async {
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => _workspace([
        const WorkspaceFolder(path: '/repo'),
      ]),
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: ProcessRunExecutor(spawner: _unexpectedSpawner),
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(
        workspaceId: 'ws1',
        command: 'make',
        workingDirectoryPath: '/elsewhere',
      ),
    );

    expect(outcome.error, 'working_directory_invalid');
    expect(outcome.status, AutomationRunStatus.dispatchFailed);
  });

  test('reports a missing workspace', () async {
    final runner = HostAutomationCommandRunner(
      workspaceById: (_) => null,
      resolver: RunTargetResolver(homeTarget: () => RuntimeTarget.local()),
      executor: ProcessRunExecutor(spawner: _unexpectedSpawner),
    );

    final outcome = await runner.run(
      const AutomationCommandRequest(workspaceId: 'ws1', command: 'make'),
    );

    expect(outcome.error, 'workspace_unavailable');
  });
}

Future<ProcessRunHandle> _unexpectedSpawner({
  required String executable,
  required List<String> arguments,
  required String workingDirectory,
  Map<String, String>? environment,
  bool runInShell = false,
  bool includeParentEnvironment = true,
}) {
  throw StateError('spawner must not be called');
}

class _HungHandle implements ProcessRunHandle {
  final Completer<int> _exit = Completer<int>();
  bool killed = false;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  void kill() {
    killed = true;
    if (!_exit.isCompleted) _exit.complete(-1);
  }
}
```

> 注：`_HungHandle` 的 exit 只在 `kill()` 后才完成，`HostAutomationCommandRunner` 必须先靠自己的计时器判定超时。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_command_runner_test.dart`
Expected: 编译失败 —— 目标文件不存在。

- [ ] **Step 3: 实现**

```dart
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/automation.dart';
import '../../models/runtime_target.dart';
import '../../models/workspace.dart';
import '../../models/workspace_folder.dart';
import '../run/process_run_executor.dart';
import '../run/run_target_resolver.dart';
import 'automation_tail_buffer.dart';

class AutomationCommandRequest {
  const AutomationCommandRequest({
    required this.workspaceId,
    required this.command,
    this.workingDirectoryPath,
    this.timeoutSeconds = 300,
    this.outputTailBytes = 4096,
  });

  final String workspaceId;
  final String command;
  final String? workingDirectoryPath;
  final int timeoutSeconds;
  final int outputTailBytes;
}

class AutomationCommandOutcome {
  const AutomationCommandOutcome({
    this.exitCode,
    this.stdoutTail = '',
    this.stderrTail = '',
    this.truncated = false,
    this.timedOut = false,
    this.durationMs = 0,
    this.error,
  });

  final int? exitCode;
  final String stdoutTail;
  final String stderrTail;
  final bool truncated;
  final bool timedOut;
  final int durationMs;
  final String? error;

  AutomationRunStatus get status {
    if (error != null) return AutomationRunStatus.dispatchFailed;
    if (timedOut) return AutomationRunStatus.timedOut;
    return exitCode == 0 ? AutomationRunStatus.completed : AutomationRunStatus.failed;
  }
}

abstract interface class AutomationCommandRunner {
  Future<AutomationCommandOutcome> run(AutomationCommandRequest request);
}

/// Runs an automation command on the workspace folder's runtime target
/// (local / WSL / SSH / Termux) through [ProcessRunExecutor].
class HostAutomationCommandRunner implements AutomationCommandRunner {
  HostAutomationCommandRunner({
    required Workspace? Function(String workspaceId) workspaceById,
    required RunTargetResolver resolver,
    required ProcessRunExecutor executor,
  }) : _workspaceById = workspaceById,
       _resolver = resolver,
       _executor = executor;

  final Workspace? Function(String workspaceId) _workspaceById;
  final RunTargetResolver _resolver;
  final ProcessRunExecutor _executor;

  @override
  Future<AutomationCommandOutcome> run(AutomationCommandRequest request) async {
    final workspace = _workspaceById(request.workspaceId);
    if (workspace == null) {
      return const AutomationCommandOutcome(error: 'workspace_unavailable');
    }
    final folder = _folderFor(workspace, request.workingDirectoryPath);
    if (folder == null) {
      return const AutomationCommandOutcome(
        error: 'working_directory_invalid',
      );
    }

    final plan = _resolver.resolve(
      owner: folder,
      cwd: request.workingDirectoryPath,
    );
    final stdout = AutomationTailBuffer(maxBytes: request.outputTailBytes);
    final stderr = AutomationTailBuffer(maxBytes: request.outputTailBytes);
    final watch = Stopwatch()..start();

    final ProcessRunResult result;
    try {
      result = await _executor.start(
        sessionId: 'automation:${request.workspaceId}',
        command: request.command,
        args: const [],
        plan: plan,
        shell: true,
        onOutput: (output) {
          if (output.category == 'stderr') {
            stderr.add(output.data);
          } else {
            stdout.add(output.data);
          }
        },
      );
    } on Object {
      return AutomationCommandOutcome(
        durationMs: watch.elapsedMilliseconds,
        error: _unreachable(plan.runtimeTarget.kind)
            ? 'target_unreachable'
            : 'spawn_failed',
      );
    }

    final exitCode = await _awaitExit(result, request.timeoutSeconds);
    if (exitCode == null) {
      await result.stop();
    }
    watch.stop();

    return AutomationCommandOutcome(
      exitCode: exitCode,
      stdoutTail: stdout.text,
      stderrTail: stderr.text,
      truncated: stdout.truncated || stderr.truncated,
      timedOut: exitCode == null,
      durationMs: watch.elapsedMilliseconds,
    );
  }

  /// Returns the exit code, or `null` when the timeout fires first.
  Future<int?> _awaitExit(ProcessRunResult result, int timeoutSeconds) {
    final completer = Completer<int?>();
    final timer = Timer(Duration(seconds: timeoutSeconds), () {
      if (!completer.isCompleted) completer.complete(null);
    });
    unawaited(
      result.exitCode.then((code) {
        if (!completer.isCompleted) completer.complete(code);
      }),
    );
    return completer.future.whenComplete(timer.cancel);
  }

  bool _unreachable(RuntimeKind kind) =>
      kind == RuntimeKind.ssh || kind == RuntimeKind.termux;

  WorkspaceFolder? _folderFor(Workspace workspace, String? rawPath) {
    final raw = rawPath?.trim() ?? '';
    if (raw.isEmpty) return workspace.folders.firstOrNull;
    for (final folder in workspace.folders) {
      if (_isUnder(raw, folder.path)) return folder;
    }
    return null;
  }

  bool _isUnder(String child, String parent) {
    final style = Platform.isWindows && !parent.startsWith('/')
        ? p.Style.windows
        : p.Style.posix;
    final ctx = p.Context(style: style);
    final normalizedChild = ctx.normalize(child);
    final normalizedParent = ctx.normalize(parent);
    if (normalizedChild == normalizedParent) return true;
    final prefix = normalizedParent.endsWith(ctx.separator)
        ? normalizedParent
        : '$normalizedParent${ctx.separator}';
    return normalizedChild.startsWith(prefix);
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_command_runner_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/automation/automation_command_runner.dart client/test/services/automation/automation_command_runner_test.dart
git commit -m "feat(automation): run shell commands on the workspace runtime"
```

---

### Task 5: 命令执行队列

**Files:**
- Create: `client/lib/services/automation/automation_command_executor.dart`
- Test: `client/test/services/automation/automation_command_executor_test.dart`

**Interfaces:**
- Consumes: `AutomationCommandRunner`、`AutomationRunAccounting`、`AutomationRepository`。
- Produces: `AutomationCommandExecutor({required AutomationRepository repository, required AutomationRunAccounting accounting, required AutomationCommandRunner runner, int Function()? nowMs, String Function()? newId, void Function()? onAfterRun})`，方法
  `Future<AutomationRun?> enqueue(Automation automation, {AutomationRunTrigger trigger = AutomationRunTrigger.scheduled})`、
  `bool isRunning(String automationId)`。

- [ ] **Step 1: 写失败测试**

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/repositories/automation_repository.dart';
import 'package:teampilot/services/automation/automation_command_executor.dart';
import 'package:teampilot/services/automation/automation_command_runner.dart';
import 'package:teampilot/services/automation/automation_run_accounting.dart';
import 'package:teampilot/services/automation/automation_schedule_calculator.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('writes a completed run and advances the automation', () async {
    final env = await _TestEnv.build(
      const AutomationCommandOutcome(exitCode: 0, stdoutTail: 'ok'),
    );
    final run = await env.executor.enqueue(env.automation);

    expect(run!.status, AutomationRunStatus.completed);
    expect(run.exitCode, 0);
    expect(run.stdoutTail, 'ok');

    final stored = await env.repository.runsFor('ws1');
    expect(stored.single.status, AutomationRunStatus.completed);
    final automations = await env.repository.listForWorkspace('ws1');
    expect(automations.single.runCount, 1);
  });

  test('records skippedOverlap without advancing runCount', () async {
    final env = await _TestEnv.build(null);
    final first = env.executor.enqueue(env.automation);
    await env.runner.waitForStart();

    final second = await env.executor.enqueue(env.automation);
    expect(second!.status, AutomationRunStatus.skippedOverlap);

    env.runner.release();
    await first;
    final automations = await env.repository.listForWorkspace('ws1');
    expect(automations.single.runCount, 1);
  });
}
```

配套测试脚手架（同一文件底部）：

```dart
class _GatedRunner implements AutomationCommandRunner {
  _GatedRunner(this.outcome);

  final AutomationCommandOutcome? outcome;
  final Completer<void> _gate = Completer<void>();
  final Completer<void> _started = Completer<void>();

  Future<void> waitForStart() => _started.future;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<AutomationCommandOutcome> run(AutomationCommandRequest request) async {
    if (!_started.isCompleted) _started.complete();
    if (outcome != null) return outcome!;
    await _gate.future;
    return const AutomationCommandOutcome(exitCode: 0);
  }
}

class _TestEnv {
  _TestEnv(this.repository, this.executor, this.runner, this.automation);

  final AutomationRepository repository;
  final AutomationCommandExecutor executor;
  final _GatedRunner runner;
  final Automation automation;

  static Future<_TestEnv> build(AutomationCommandOutcome? outcome) async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repository = AutomationRepository(
      fs: testHomeStorage.fs,
      layout: layout,
    );
    final automation = Automation(
      id: 'a1',
      name: 'nightly',
      action: AutomationAction.runCommand,
      workspaceId: 'ws1',
      command: 'echo hi',
      message: '',
      preset: AutomationSchedulePreset.daily,
      hourMinute: '02:00',
      timezone: 'Asia/Shanghai',
      dtstartMs: 0,
      createdAtMs: 0,
      updatedAtMs: 0,
    );
    await repository.upsert(automation);
    final runner = _GatedRunner(outcome);
    final executor = AutomationCommandExecutor(
      repository: repository,
      accounting: AutomationRunAccounting(AutomationScheduleCalculator()),
      runner: runner,
    );
    return _TestEnv(repository, executor, runner, automation);
  }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_command_executor_test.dart`
Expected: 编译失败 —— 目标文件不存在。

- [ ] **Step 3: 实现**

```dart
import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../models/automation.dart';
import '../../repositories/automation_repository.dart';
import 'automation_command_runner.dart';
import 'automation_run_accounting.dart';

int _defaultNowMs() => DateTime.now().millisecondsSinceEpoch;

/// Serializes command runs, prevents overlapping runs of the same automation,
/// and records the outcome as an [AutomationRun].
class AutomationCommandExecutor {
  AutomationCommandExecutor({
    required AutomationRepository repository,
    required AutomationRunAccounting accounting,
    required AutomationCommandRunner runner,
    int Function()? nowMs,
    String Function()? newId,
    this.onAfterRun,
  }) : _repository = repository,
       _accounting = accounting,
       _runner = runner,
       _nowMs = nowMs ?? _defaultNowMs,
       _newId = newId ?? (() => const Uuid().v4());

  static const _uuid = Uuid();

  final AutomationRepository _repository;
  final AutomationRunAccounting _accounting;
  final AutomationCommandRunner _runner;
  final int Function() _nowMs;
  final String Function() _newId;
  final void Function()? onAfterRun;

  final Set<String> _running = <String>{};
  Future<void> _queue = Future<void>.value();

  bool isRunning(String automationId) => _running.contains(automationId);

  Future<void> waitForIdle() => _queue;

  Future<AutomationRun?> enqueue(
    Automation automation, {
    AutomationRunTrigger trigger = AutomationRunTrigger.scheduled,
  }) {
    if (_running.contains(automation.id)) {
      return _recordOverlap(automation, trigger: trigger);
    }
    _running.add(automation.id);
    final next = _queue.then((_) => _run(automation, trigger: trigger));
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next.whenComplete(() => _running.remove(automation.id));
  }

  Future<AutomationRun> _recordOverlap(
    Automation automation, {
    required AutomationRunTrigger trigger,
  }) async {
    final now = _nowMs();
    final run = AutomationRun(
      id: _uuid.v4(),
      automationId: automation.id,
      workspaceId: automation.workspaceId,
      scheduledForMs: automation.nextRunAtMs ?? now,
      status: AutomationRunStatus.skippedOverlap,
      trigger: trigger,
      startedAtMs: now,
      completedAtMs: now,
    );
    await _repository.upsertRun(automation.workspaceId, run);
    onAfterRun?.call();
    return run;
  }

  Future<AutomationRun> _run(
    Automation automation, {
    required AutomationRunTrigger trigger,
  }) async {
    final startedAtMs = _nowMs();
    final pending = AutomationRun(
      id: _newId(),
      automationId: automation.id,
      workspaceId: automation.workspaceId,
      scheduledForMs: automation.nextRunAtMs ?? startedAtMs,
      status: AutomationRunStatus.dispatching,
      trigger: trigger,
      startedAtMs: startedAtMs,
    );
    await _repository.upsertRun(automation.workspaceId, pending);

    final outcome = await _runner.run(
      AutomationCommandRequest(
        workspaceId: automation.workspaceId,
        command: automation.command ?? '',
        workingDirectoryPath: automation.workingDirectoryPath,
        timeoutSeconds: automation.timeoutSeconds,
      ),
    );
    final finishedAtMs = _nowMs();
    final finished = pending.copyWith(
      status: outcome.status,
      exitCode: outcome.exitCode,
      clearExitCode: outcome.exitCode == null,
      stdoutTail: outcome.stdoutTail,
      stderrTail: outcome.stderrTail,
      outputTruncated: outcome.truncated,
      durationMs: outcome.durationMs,
      error: outcome.error,
      clearError: outcome.error == null,
      completedAtMs: finishedAtMs,
    );
    await _repository.upsertRun(automation.workspaceId, finished);

    final advanced = _accounting.advance(
      automation: automation,
      lastRunAtMs: startedAtMs,
      nowMs: finishedAtMs,
    );
    await _repository.upsert(advanced);
    onAfterRun?.call();
    return finished;
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_command_executor_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/automation/automation_command_executor.dart client/test/services/automation/automation_command_executor_test.dart
git commit -m "feat(automation): add serialized command executor"
```

---

### Task 6: 调度器接线（解耦 / 补跑 / 中断清理）

**Files:**
- Modify: `client/lib/services/automation/automation_scheduler.dart`
- Test: `client/test/services/automation/automation_scheduler_test.dart`

**Interfaces:**
- Consumes: `AutomationCommandExecutor.enqueue`、`Automation.catchUpPolicy`、`Automation.isRunCommand`。
- Produces: `AutomationScheduler({..., AutomationCommandExecutor? commandExecutor})`。

- [ ] **Step 1: 写失败测试**

在 `client/test/services/automation/automation_scheduler_test.dart` 追加：

```dart
const _now = 10_000_000;

Automation _runCommandAutomation({
  AutomationCatchUpPolicy catchUpPolicy = AutomationCatchUpPolicy.none,
  int? nextRunAtMs,
  int timeoutSeconds = 300,
}) {
  return Automation(
    id: 'cmd-1',
    name: 'Nightly build',
    action: AutomationAction.runCommand,
    workspaceId: 'ws1',
    command: 'echo hi',
    timeoutSeconds: timeoutSeconds,
    catchUpPolicy: catchUpPolicy,
    message: '',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '02:00',
    timezone: 'UTC',
    dtstartMs: 1,
    enabled: true,
    nextRunAtMs: nextRunAtMs,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}

({
  AutomationScheduler scheduler,
  _RecordingCommandExecutor executor,
  AutomationRepository repo,
})
_buildCommandScheduler({required int nowMs}) {
  final layout = WorkspaceLayout(
    teampilotRoot: testHomeStorage.paths.basePath,
    fs: testHomeStorage.fs,
  );
  final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
  final executor = _RecordingCommandExecutor(
    repository: repo,
    accounting: AutomationRunAccounting(AutomationScheduleCalculator()),
    runner: _NoopRunner(),
  );
  final scheduler = AutomationScheduler(
    repository: repo,
    dispatcher: _buildDispatcher(
      repo: repo,
      bus: _RecordingBusGateway(),
      sessions: const [],
    ),
    scheduleCalculator: AutomationScheduleCalculator(),
    commandExecutor: executor,
    nowMs: () => nowMs,
  );
  return (scheduler: scheduler, executor: executor, repo: repo);
}

test('catch-up once dispatches a missed runCommand instead of skipping', () async {
  final harness = _buildCommandScheduler(nowMs: _now);
  await harness.repo.upsert(
    _runCommandAutomation(
      catchUpPolicy: AutomationCatchUpPolicy.once,
      nextRunAtMs: _now - const Duration(hours: 2).inMilliseconds,
    ),
  );

  harness.scheduler.start();
  await harness.scheduler.waitForIdle();
  harness.scheduler.stop();

  final runs = await harness.repo.runsFor('ws1');
  expect(
    runs.any((r) => r.status == AutomationRunStatus.skippedMissed),
    isFalse,
  );
  expect(harness.executor.calls, 1);
});

test('catch-up none keeps skipping', () async {
  final harness = _buildCommandScheduler(nowMs: _now);
  await harness.repo.upsert(
    _runCommandAutomation(
      catchUpPolicy: AutomationCatchUpPolicy.none,
      nextRunAtMs: _now - const Duration(hours: 2).inMilliseconds,
    ),
  );

  harness.scheduler.start();
  await harness.scheduler.waitForIdle();
  harness.scheduler.stop();

  final runs = await harness.repo.runsFor('ws1');
  expect(runs.single.status, AutomationRunStatus.skippedMissed);
  expect(harness.executor.calls, 0);
});

test('marks stale dispatching runs as interrupted on start', () async {
  final harness = _buildCommandScheduler(nowMs: _now);
  final automation = _runCommandAutomation(timeoutSeconds: 30);
  await harness.repo.upsert(automation);
  await harness.repo.upsertRun(
    'ws1',
    AutomationRun(
      id: 'stale',
      automationId: automation.id,
      workspaceId: 'ws1',
      scheduledForMs: _now - const Duration(hours: 1).inMilliseconds,
      status: AutomationRunStatus.dispatching,
      trigger: AutomationRunTrigger.scheduled,
      startedAtMs: _now - const Duration(hours: 1).inMilliseconds,
    ),
  );

  harness.scheduler.start();
  await harness.scheduler.waitForIdle();
  harness.scheduler.stop();

  final runs = await harness.repo.runsFor('ws1');
  final stale = runs.firstWhere((r) => r.id == 'stale');
  expect(stale.status, AutomationRunStatus.dispatchFailed);
  expect(stale.error, 'interrupted');
});
```

配套脚手架（同一文件顶部，`_dueAutomation` 之后）：

```dart
class _NoopRunner implements AutomationCommandRunner {
  @override
  Future<AutomationCommandOutcome> run(AutomationCommandRequest request) async {
    return const AutomationCommandOutcome(exitCode: 0);
  }
}

class _RecordingCommandExecutor extends AutomationCommandExecutor {
  _RecordingCommandExecutor({
    required super.repository,
    required super.accounting,
    required super.runner,
  });

  int calls = 0;

  @override
  Future<AutomationRun?> enqueue(
    Automation automation, {
    AutomationRunTrigger trigger = AutomationRunTrigger.scheduled,
  }) async {
    calls += 1;
    return AutomationRun(
      id: 'run-$calls',
      automationId: automation.id,
      workspaceId: automation.workspaceId,
      scheduledForMs: automation.nextRunAtMs ?? 0,
      status: AutomationRunStatus.completed,
      trigger: trigger,
      startedAtMs: 0,
      completedAtMs: 0,
    );
  }
}
```

补 import：`automation_command_executor.dart`、`automation_command_runner.dart`、
`automation_run_accounting.dart`。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_scheduler_test.dart`
Expected: FAIL —— `commandExecutor` 参数不存在 / 补跑未实现。

- [ ] **Step 3: 实现**

```dart
  AutomationScheduler({
    required AutomationRepository repository,
    required AutomationDispatcher dispatcher,
    required AutomationScheduleCalculator scheduleCalculator,
    AutomationCommandExecutor? commandExecutor,
    Duration tickInterval = const Duration(seconds: 30),
    int Function()? nowMs,
  }) : _repository = repository,
       _dispatcher = dispatcher,
       _scheduleCalculator = scheduleCalculator,
       _commandExecutor = commandExecutor,
       _tickInterval = tickInterval,
       _nowMs = nowMs ?? _automationSchedulerDefaultNowMs;
```

`_processMissedRuns` 超时分支改：

```dart
      final graceMs = automation.missedRunGraceMinutes * 60 * 1000;
      if (now - dueAt <= graceMs ||
          (automation.isRunCommand &&
              automation.catchUpPolicy == AutomationCatchUpPolicy.once)) {
        await _dispatchClaimed(automation);
        continue;
      }
```

`_processMissedRuns` 开头加中断清理：

```dart
  Future<void> _processMissedRuns() async {
    _missedRunsProcessed = true;
    final now = _nowMs();
    final automations = await _repository.listAll();
    await _markInterruptedRuns(automations, now);
    // …既有循环
```

```dart
  Future<void> _markInterruptedRuns(
    List<Automation> automations,
    int now,
  ) async {
    for (final automation in automations) {
      if (!automation.isRunCommand) continue;
      final runs = await _repository.runsFor(
        automation.workspaceId,
        automationId: automation.id,
      );
      final limitMs = automation.timeoutSeconds * 1000 + 60 * 1000;
      for (final run in runs) {
        if (run.status != AutomationRunStatus.pending &&
            run.status != AutomationRunStatus.dispatching) {
          continue;
        }
        final startedAtMs = run.startedAtMs ?? run.scheduledForMs;
        if (now - startedAtMs <= limitMs) continue;
        await _repository.upsertRun(
          automation.workspaceId,
          run.copyWith(
            status: AutomationRunStatus.dispatchFailed,
            error: 'interrupted',
            completedAtMs: now,
          ),
        );
      }
    }
  }
```

`_dispatchClaimed` 改为：

```dart
  Future<void> _dispatchClaimed(
    Automation automation, {
    AutomationRunTrigger trigger = AutomationRunTrigger.scheduled,
  }) async {
    if (automation.isRunLimitReached) return;
    final now = _nowMs();
    final next = automation.enabled
        ? _scheduleCalculator.computeNextRunAtMs(automation, afterMs: now)
        : null;
    final claimed = automation.copyWith(
      nextRunAtMs: automation.enabled ? next : automation.nextRunAtMs,
      clearNextRunAtMs: automation.enabled && next == null,
      updatedAtMs: now,
    );
    await _repository.upsert(claimed);

    final executor = _commandExecutor;
    if (automation.isRunCommand) {
      if (executor == null) return;
      if (trigger == AutomationRunTrigger.manual) {
        await executor.enqueue(claimed, trigger: trigger);
      } else {
        unawaited(executor.enqueue(claimed, trigger: trigger));
      }
      return;
    }
    await _dispatcher.dispatch(claimed, trigger: trigger);
  }
```

> 注意：现有实现把原始 `automation` 传给 `dispatch`；这里保持语义不变——`dispatch` 会再次读
> `automation.enabled`，把 `claimed` 传进去等价（`claimed.enabled` 未改变）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_scheduler_test.dart test/services/automation/automation_dispatcher_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/automation/automation_scheduler.dart client/test/services/automation/automation_scheduler_test.dart
git commit -m "feat(automation): dispatch commands off the scheduler queue with catch-up"
```

---

### Task 7: dispatcher 拒绝 runCommand

**Files:**
- Modify: `client/lib/services/automation/automation_dispatcher.dart:91-96`
- Test: `client/test/services/automation/automation_dispatcher_test.dart`

**Interfaces:**
- Produces: `AutomationDispatcher.dispatch` 对 `runCommand` 抛 `ArgumentError`。

- [ ] **Step 1: 写失败测试**

```dart
test('rejects runCommand automations', () async {
  final automation = Automation(
    id: 'a1',
    name: 'nightly',
    action: AutomationAction.runCommand,
    workspaceId: 'ws1',
    command: 'echo hi',
    message: '',
    preset: AutomationSchedulePreset.daily,
    hourMinute: '02:00',
    timezone: 'Asia/Shanghai',
    dtstartMs: 0,
    createdAtMs: 0,
    updatedAtMs: 0,
  );
  expect(
    () => env.dispatcher.dispatch(automation),
    throwsA(isA<ArgumentError>()),
  );
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_dispatcher_test.dart`
Expected: FAIL —— 未抛错。

- [ ] **Step 3: 实现**

在 `dispatch` 方法体第一行 `automation.validate();` 之后加：

```dart
    if (automation.isRunCommand) {
      throw ArgumentError(
        'runCommand automations are executed by AutomationCommandExecutor',
      );
    }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_dispatcher_test.dart`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/automation/automation_dispatcher.dart client/test/services/automation/automation_dispatcher_test.dart
git commit -m "feat(automation): keep command runs out of the session dispatcher"
```

---

### Task 8: MCP 工具支持 runCommand

**Files:**
- Modify: `client/lib/services/catalog/modules/automation_catalog_tools.dart`
- Modify: `client/lib/services/catalog/modules/automation_catalog_module.dart`
- Test: `client/test/services/catalog/automation_catalog_module_test.dart`

**Interfaces:**
- Consumes: `AutomationCatalogModule` 构造函数新增可选
  `List<WorkspaceFolder>? Function(String workspaceId)? workspaceFolders`。
- Produces: `create_automation` 接受 `action: "runCommand"` + `command` / `working_directory` /
  `timeout_seconds` / `catch_up` / `enabled`；`update_automation` 接受同样的 patch 字段。

- [ ] **Step 1: 写失败测试**

```dart
test('create runCommand defaults to disabled', () async {
  final result = await module.handle(
    CatalogOp.create,
    req({
      'name': 'nightly',
      'action': 'runCommand',
      'command': 'npm ci && npm run build',
      'schedule': {'type': 'daily', 'time': '02:00'},
    }),
  );
  final data = result.data['automation']! as Map<String, Object?>;
  expect(data['enabled'], isFalse);
  expect(data['command'], 'npm ci && npm run build');
  expect(data['timeoutSeconds'], 300);
  expect(data['catchUpPolicy'], 'none');
});

test('create runCommand honours enabled true', () async {
  final result = await module.handle(
    CatalogOp.create,
    req({
      'name': 'nightly',
      'action': 'runCommand',
      'command': 'make',
      'enabled': true,
      'schedule': {'type': 'daily', 'time': '02:00'},
    }),
  );
  final data = result.data['automation']! as Map<String, Object?>;
  expect(data['enabled'], isTrue);
  expect(data['nextRunAtMs'], isNotNull);
});

test('create runCommand rejects an empty command', () async {
  await expectLater(
    module.handle(
      CatalogOp.create,
      req({
        'name': 'nightly',
        'action': 'runCommand',
        'command': '   ',
        'schedule': {'type': 'daily', 'time': '02:00'},
      }),
    ),
    throwsA(
      isA<CatalogException>().having((e) => e.code, 'code', 'command_invalid'),
    ),
  );
});

test('create runCommand rejects a working directory outside the workspace',
    () async {
  await expectLater(
    module.handle(
      CatalogOp.create,
      req({
        'name': 'nightly',
        'action': 'runCommand',
        'command': 'make',
        'working_directory': '/elsewhere',
        'schedule': {'type': 'daily', 'time': '02:00'},
      }),
    ),
    throwsA(
      isA<CatalogException>()
          .having((e) => e.code, 'code', 'working_directory_invalid'),
    ),
  );
});

test('update patches command and timeout', () async {
  final created = await module.handle(
    CatalogOp.create,
    req({
      'name': 'nightly',
      'action': 'runCommand',
      'command': 'make',
      'schedule': {'type': 'daily', 'time': '02:00'},
    }),
  );
  final id = (created.data['automation']! as Map<String, Object?>)['id'] as String;

  final updated = await module.handle(
    CatalogOp.update,
    req({
      'id': id,
      'command': 'make release',
      'timeout_seconds': 900,
      'catch_up': 'once',
    }),
  );
  final data = updated.data['automation']! as Map<String, Object?>;
  expect(data['command'], 'make release');
  expect(data['timeoutSeconds'], 900);
  expect(data['catchUpPolicy'], 'once');
});
```

模块测试的 fixture 需要注入 workspace folders，在构造 `AutomationCatalogModule(...)` 处加：
`workspaceFolders: (_) => const [WorkspaceFolder(path: '/repo')],`。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/catalog/automation_catalog_module_test.dart`
Expected: FAIL —— 未知 action / 未识别的参数。

- [ ] **Step 3: 实现工具 schema**

`automation_catalog_tools.dart` 两处 `enum: ['scheduledMessage', 'launchPrompt']`（create 与 update 用同一份）
改为：

```dart
        'action': {
          'type': 'string',
          'enum': ['scheduledMessage', 'launchPrompt', 'runCommand'],
        },
```

`create_automation` 的 properties 增加：

```dart
        'command': {'type': 'string'},
        'working_directory': {'type': 'string'},
        'timeout_seconds': {'type': 'integer'},
        'catch_up': {
          'type': 'string',
          'enum': ['none', 'once'],
        },
        'enabled': {'type': 'boolean'},
```

并把 `required` 从 `['name', 'message', 'schedule']` 改为 `['name', 'schedule']`，
description 补一句：`runCommand requires command; message is ignored for it`。

`update_automation` properties 同样增加这四个字段（无需 `enabled`，已有）。

- [ ] **Step 4: 实现 module 分支**

构造函数与字段：

```dart
    this.workspaceFolders,
```

```dart
  /// Folders of a workspace, used to validate `working_directory`.
  final List<WorkspaceFolder>? Function(String workspaceId)? workspaceFolders;
```

`_create` 里把现有的 `final message = _requireText(req, 'message');` 一行替换为：

```dart
    final message = action == AutomationAction.runCommand
        ? (_text(req.arguments['message']) ?? '')
        : _requireText(req, 'message');
```

（`action` 与 `name` 已有声明，不要重复声明。）

`_create` 在 `if (action == AutomationAction.scheduledMessage) { … } else { … }` 之前插入：

```dart
    if (action == AutomationAction.runCommand) {
      final command = _requireCommand(req);
      final workingDirectory = _workingDirectory(req);
      final timeoutSeconds = _timeoutSeconds(req);
      final catchUp = _catchUpPolicy(req);
      final wantsEnabled = _boolArg(req, 'enabled') ?? false;
      draft = _baseAutomation(
        id: id,
        name: name,
        action: action,
        workspaceId: req.workspaceId,
        message: '',
        schedule: schedule,
        now: now,
        maxRunCount: maxRunCount,
        missedRunGraceMinutes: missedRunGraceMinutes,
      ).copyWith(
        command: command,
        timeoutSeconds: timeoutSeconds,
        catchUpPolicy: catchUp,
        workingDirectoryPath: workingDirectory,
        enabled: wantsEnabled,
      );
      final (saved, preview) = await _commit(
        draft,
        now,
        scheduleNextRun: wantsEnabled,
        requireEnabled: wantsEnabled,
      );
      _emit(CatalogOp.create, req, [saved.id]);
      return _ok(
        req,
        [saved.id],
        {
          'automation': saved.toJson(),
          'summary': scheduleCalculator.formatScheduleSummary(saved),
          'enabled': saved.enabled,
          'next_run_at_ms': preview,
        },
        message: saved.enabled
            ? 'Created and enabled. It will run on the resolved schedule.'
            : _createdDisabledMessage,
      );
    }
```

`_update` 追加 patch 分支（放在 `if (req.arguments.containsKey('message'))` 之后）：

```dart
    if (req.arguments.containsKey('command')) {
      final command = _text(req.arguments['command']) ?? '';
      if (command.isEmpty || command.length > 2000) {
        throw CatalogException(
          'command_invalid',
          'command must be 1..2000 characters',
        );
      }
      next = next.copyWith(command: command);
    }
    if (req.arguments.containsKey('working_directory')) {
      final workingDirectory = _workingDirectory(req);
      next = next.copyWith(
        workingDirectoryPath: workingDirectory,
        clearWorkingDirectoryPath: workingDirectory == null,
      );
    }
    if (req.arguments.containsKey('timeout_seconds')) {
      next = next.copyWith(timeoutSeconds: _timeoutSeconds(req));
    }
    if (req.arguments.containsKey('catch_up')) {
      next = next.copyWith(catchUpPolicy: _catchUpPolicy(req));
    }
```

新增私有 helper（放在 `_graceMinutes` 附近）：

```dart
  String _requireCommand(CatalogRequest req) {
    final command = _text(req.arguments['command']) ?? '';
    if (command.isEmpty) {
      throw CatalogException('command_invalid', 'command is required');
    }
    if (command.length > 2000) {
      throw CatalogException(
        'command_invalid',
        'command must be at most 2000 characters',
      );
    }
    return command;
  }

  String? _workingDirectory(CatalogRequest req) {
    final raw = _text(req.arguments['working_directory']);
    if (raw == null) return null;
    final folders = workspaceFolders?.call(req.workspaceId) ?? const [];
    if (!folders.any((folder) => _isUnder(raw, folder.path))) {
      throw CatalogException(
        'working_directory_invalid',
        'working_directory must be inside this workspace: $raw',
      );
    }
    return raw;
  }

  int _timeoutSeconds(CatalogRequest req) {
    final raw = req.arguments['timeout_seconds'];
    if (raw == null) return 300;
    final value = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (value == null || value < 30 || value > 1800) {
      throw CatalogException(
        'invalid_argument',
        'timeout_seconds must be 30..1800',
      );
    }
    return value;
  }

  AutomationCatchUpPolicy _catchUpPolicy(CatalogRequest req) {
    final raw = _text(req.arguments['catch_up']);
    if (raw == null) return AutomationCatchUpPolicy.none;
    for (final value in AutomationCatchUpPolicy.values) {
      if (value.name == raw) return value;
    }
    throw CatalogException('invalid_argument', 'unknown catch_up: $raw');
  }

  bool _isUnder(String child, String parent) {
    final ctx = p.Context(
      style: Platform.isWindows && !parent.startsWith('/')
          ? p.Style.windows
          : p.Style.posix,
    );
    final normalizedChild = ctx.normalize(child);
    final normalizedParent = ctx.normalize(parent);
    if (normalizedChild == normalizedParent) return true;
    final prefix = normalizedParent.endsWith(ctx.separator)
        ? normalizedParent
        : '$normalizedParent${ctx.separator}';
    return normalizedChild.startsWith(prefix);
  }
```

`_baseAutomation` 增加可选参数并透传（`enabled` 默认 false 由调用方 `copyWith` 覆盖）：

```dart
    String? command,
    int timeoutSeconds = 300,
    AutomationCatchUpPolicy catchUpPolicy = AutomationCatchUpPolicy.none,
```

```dart
      command: command,
      timeoutSeconds: timeoutSeconds,
      catchUpPolicy: catchUpPolicy,
```

补 import：`dart:io`、`package:path/path.dart as p`、`../../../models/workspace_folder.dart`。

- [ ] **Step 5: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/catalog/automation_catalog_module_test.dart test/services/catalog/catalog_mcp_policy_test.dart`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/catalog/modules/automation_catalog_tools.dart client/lib/services/catalog/modules/automation_catalog_module.dart client/test/services/catalog/automation_catalog_module_test.dart
git commit -m "feat(catalog): create and patch runCommand automations over MCP"
```

---

### Task 9: app_shell 接线

**Files:**
- Modify: `client/lib/app/app_shell.dart:2578-2640`

**Interfaces:**
- Consumes: 已有的 `repoCloneSshSpawner`、`defaultTargetResolver`、`chatCubit.state.workspaces`。

- [ ] **Step 1: 先跑现状测试作为基线**

Run: `cd client && dart run tool/run_tests.dart test/app/app_shell_test.dart`
Expected: PASS（若该文件不存在，改为跑 `test/services/catalog/automation_catalog_module_test.dart` 作为基线）

- [ ] **Step 2: 接线**

在 `final scheduleCalculator = AutomationScheduleCalculator();` 之后插入：

```dart
    final automationCommandRunner = HostAutomationCommandRunner(
      workspaceById: (workspaceId) => chatCubit.state.workspaces
          .where((w) => w.workspaceId == workspaceId)
          .firstOrNull,
      resolver: RunTargetResolver(homeTarget: defaultTargetResolver),
      executor: ProcessRunExecutor(sshSpawner: repoCloneSshSpawner),
    );
    final automationCommandExecutor = AutomationCommandExecutor(
      repository: automationRepo,
      accounting: AutomationRunAccounting(scheduleCalculator),
      runner: automationCommandRunner,
      onAfterRun: () {
        if (!automationCubit.isClosed) {
          unawaited(automationCubit.reloadPreservingScope());
        }
      },
    );
```

`AutomationScheduler(...)` 调用加一行：

```dart
      commandExecutor: automationCommandExecutor,
```

`AutomationCatalogModule(...)` 调用加一行：

```dart
        workspaceFolders: (workspaceId) => chatCubit.state.workspaces
            .where((w) => w.workspaceId == workspaceId)
            .firstOrNull
            ?.folders,
```

> `onAfterRun` 里引用 `automationCubit` 时它还晚于 executor 构造——把 executor 的构造移到
> `automationCubit = AutomationCubit(...)` 之后、`refreshAutomations` 定义之前，再用
> `refreshAutomations` 作为回调，避免前向引用。

补 import：

```dart
import '../services/automation/automation_command_executor.dart';
import '../services/automation/automation_command_runner.dart';
import '../services/automation/automation_run_accounting.dart';
import '../services/run/process_run_executor.dart';
import '../services/run/run_target_resolver.dart';
```

- [ ] **Step 3: 静态检查**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues found

- [ ] **Step 4: 提交**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(app): wire command automation executor into the shell"
```

---

### Task 10: 编辑器与列表 UI

**Files:**
- Modify: `client/lib/pages/automations/automation_editor_dialog.dart`
- Modify: `client/lib/pages/automations/automation_editor_form_body.dart`
- Modify: `client/lib/pages/automations/automations_list_body.dart:171-181`
- Modify: `client/lib/pages/automations/automations_dialog.dart:29-38`
- Modify: `client/lib/l10n/app_en.arb`、`client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/automations/automation_editor_dialog_test.dart`

**Interfaces:**
- Produces: `AutomationEditorKind { scheduledMessage, launchPrompt, runCommand }`；
  `AutomationEditorKind kindForAutomation(Automation automation)`；
  表单新增 `commandController` / `timeoutController` / `catchUpOnce`。

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('runCommand editor saves a command automation', (tester) async {
  final setup = testAutomationSetup();
  addTearDown(setup.cubit.close);

  await tester.pumpWidget(
    RepositoryProvider<HomeStorage>.value(
      value: testHomeStorage,
      child: _host(
        cubit: setup.cubit,
        child: const AutomationEditorDialog(
          kind: AutomationEditorKind.runCommand,
          workspaceId: 'ws1',
          defaultName: 'Nightly',
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));

  final l10n = AppLocalizations.of(
    tester.element(find.byType(AutomationEditorDialog)),
  );

  await tester.enterText(
    find.byKey(const Key('automationCommandField')),
    'echo hi',
  );
  await tester.tap(find.text(l10n.save));
  await tester.pump();
  await pumpUntilClosed(tester);

  final saved = (await setup.repo.listForWorkspace('ws1')).single;
  expect(saved.action, AutomationAction.runCommand);
  expect(saved.command, 'echo hi');
  expect(saved.timeoutSeconds, 300);
  expect(saved.catchUpPolicy, AutomationCatchUpPolicy.none);
  expect(saved.message, isEmpty);
});

testWidgets('runCommand editor blocks an empty command', (tester) async {
  final setup = testAutomationSetup();
  addTearDown(setup.cubit.close);

  await tester.pumpWidget(
    RepositoryProvider<HomeStorage>.value(
      value: testHomeStorage,
      child: _host(
        cubit: setup.cubit,
        child: const AutomationEditorDialog(
          kind: AutomationEditorKind.runCommand,
          workspaceId: 'ws1',
          defaultName: 'Nightly',
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));

  final l10n = AppLocalizations.of(
    tester.element(find.byType(AutomationEditorDialog)),
  );

  await tester.tap(find.text(l10n.save));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));

  expect(find.text(l10n.automationsCommandRequired), findsOneWidget);
  expect(find.byType(AutomationEditorDialog), findsOneWidget);
  expect(await setup.repo.listForWorkspace('ws1'), isEmpty);
});

test('kindForAutomation maps every action', () {
  expect(
    kindForAutomation(sampleAutomation(id: 'a', workspaceId: 'ws1')),
    AutomationEditorKind.launchPrompt,
  );
  expect(
    kindForAutomation(
      sampleAutomation(id: 'b', workspaceId: 'ws1', sessionId: 'sess-1'),
    ),
    AutomationEditorKind.scheduledMessage,
  );
  expect(
    kindForAutomation(
      Automation(
        id: 'c',
        name: 'Nightly',
        action: AutomationAction.runCommand,
        workspaceId: 'ws1',
        command: 'make',
        message: '',
        preset: AutomationSchedulePreset.daily,
        hourMinute: '02:00',
        timezone: 'UTC',
        dtstartMs: 1,
        createdAtMs: 1,
        updatedAtMs: 1,
      ),
    ),
    AutomationEditorKind.runCommand,
  );
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/pages/automations/automation_editor_dialog_test.dart`
Expected: FAIL —— 枚举缺少 `runCommand`。

- [ ] **Step 3: 改编辑器**

`automation_editor_dialog.dart`：

```dart
enum AutomationEditorKind { scheduledMessage, launchPrompt, runCommand }

AutomationEditorKind kindForAutomation(Automation automation) {
  return switch (automation.action) {
    AutomationAction.scheduledMessage => AutomationEditorKind.scheduledMessage,
    AutomationAction.launchPrompt => AutomationEditorKind.launchPrompt,
    AutomationAction.runCommand => AutomationEditorKind.runCommand,
  };
}
```

State 增加：

```dart
  late final TextEditingController _commandCtl = TextEditingController(
    text: widget.initial?.command ?? '',
  );
  late final TextEditingController _timeoutCtl = TextEditingController(
    text: '${widget.initial?.timeoutSeconds ?? 300}',
  );
  late bool _catchUpOnce =
      widget.initial?.catchUpPolicy == AutomationCatchUpPolicy.once;
  String? _commandError;

  bool get _isRunCommand => widget.kind == AutomationEditorKind.runCommand;

  @override
  void dispose() {
    _commandCtl.dispose();
    _timeoutCtl.dispose();
    super.dispose();
  }
```

保存逻辑（`automation_editor_dialog.dart:433` 附近）改为：

```dart
    if (_isRunCommand) {
      final command = _commandCtl.text.trim();
      if (command.isEmpty) {
        setState(() => _commandError = context.l10n.automationsCommandRequired);
        return;
      }
      _commandError = null;
      final timeout = int.tryParse(_timeoutCtl.text.trim()) ?? 300;
      var automation = Automation(
        id: widget.initial?.id ?? const Uuid().v4(),
        name: name,
        action: AutomationAction.runCommand,
        workspaceId: workspaceId,
        command: command,
        timeoutSeconds: timeout,
        catchUpPolicy: _catchUpOnce
            ? AutomationCatchUpPolicy.once
            : AutomationCatchUpPolicy.none,
        workingDirectoryPath: workingDirectoryPath,
        message: '',
        preset: schedule.preset,
        customCron: isOnceSchedule ? null : _schedule.customCron,
        dayOfWeek: isOnceSchedule ? null : _schedule.dayOfWeek,
        minute: _schedule.minute,
        hourMinute: hourMinute,
        timezone: _schedule.timezone,
        dtstartMs: isOnceSchedule ? schedule.runAtMs! : (widget.initial?.dtstartMs ?? nowMs),
        runAtMs: schedule.runAtMs,
        enabled: _enabled,
        nextRunAtMs: widget.initial?.nextRunAtMs,
        lastRunAtMs: widget.initial?.lastRunAtMs,
        maxRunCount: maxRunCount,
        runCount: schedule.runCount,
        createdAtMs: widget.initial?.createdAtMs ?? nowMs,
        updatedAtMs: nowMs,
      );
      try {
        automation.validate();
      } on ArgumentError catch (e) {
        form.setFieldError('name', e.message?.toString() ?? e.toString());
        return;
      }
      final nextRun = _enabled && !_runLimitReached
          ? _calculator.computeNextRunAtMs(automation, afterMs: nowMs)
          : null;
      final saved = automation.copyWith(
        nextRunAtMs: nextRun,
        clearNextRunAtMs: nextRun == null,
        enabled: _enabled && !_runLimitReached,
      );
      await cubit.save(saved);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
      return;
    }
```

并在原 `action:` 三目处保持二值分支（`runCommand` 已在上面提前 return）。

`_seedLaunchDefaults()` 与 `_seedLocationDefaults()` 首行加 `if (_isRunCommand) return;`
（沿用现有 `_isScheduledMessage` 短路写法：`if (_isScheduledMessage || _isRunCommand) return;`）。

`automation_editor_form_body.dart`：

- 把 `required this.isScheduledMessage` 换成 `required this.kind`，字段类型 `AutomationEditorKind`，
  内部加 `bool get isScheduledMessage => kind == AutomationEditorKind.scheduledMessage;`。
- 构造函数新增：

```dart
    this.commandController,
    this.commandError,
    this.timeoutController,
    this.catchUpOnce = false,
    this.onCatchUpChanged,
```

- 表单顶部在“名称”之后插入命令区块：

```dart
        if (kind == AutomationEditorKind.runCommand) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('automationCommandField'),
            controller: commandController,
            minLines: 3,
            maxLines: 8,
            style: monospaceStyle,
            decoration: InputDecoration(
              labelText: l10n.automationsCommand,
              helperText: l10n.automationsCommandHelp,
              errorText: commandError,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('automationTimeoutField'),
                  controller: timeoutController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.automationsCommandTimeout,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SwitchListTile(
                value: catchUpOnce,
                onChanged: onCatchUpChanged,
                title: Text(l10n.automationsCatchUpOnce),
              ),
            ],
          ),
        ],
```

> `monospaceStyle` 用 `Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace')`。

对话框里构造 `AutomationEditorFormBody` 处同步改：`isScheduledMessage: _isScheduledMessage` 换成
`kind: widget.kind`，并补 `commandController: _commandCtl`、`commandError: _commandError`、
`timeoutController: _timeoutCtl`、`catchUpOnce: _catchUpOnce`、
`onCatchUpChanged: (value) => setState(() => _catchUpOnce = value)`。

`automations_list_body.dart:176` 改为 `kind: kindForAutomation(automation),`。

`automations_dialog.dart:29 _create()` 改为弹出三项菜单（`showMenu` 或 `PopupMenuButton`），
选中后调用 `AutomationEditorDialog.show(context, kind: <selected>, workspaceId: …, sessionId: …)`。

- [ ] **Step 4: 加 l10n 并生成**

`app_en.arb`：

```json
  "automationsCommand": "Command",
  "automationsCommandHelp": "Runs only while TeamPilot is running. Missed runs older than the grace window are skipped unless catch-up is on.",
  "automationsCommandTimeout": "Timeout (seconds)",
  "automationsCommandRequired": "Command is required",
  "automationsCatchUpOnce": "Catch up once after startup",
  "automationsRunStatusFailed": "Failed",
  "automationsRunStatusTimedOut": "Timed out",
  "automationsRunStatusSkippedOverlap": "Skipped (still running)",
  "automationsExitCode": "Exit code {code}",
```

`app_zh.arb`：

```json
  "automationsCommand": "命令",
  "automationsCommandHelp": "仅在 TeamPilot 运行时执行。超过宽限期的错过运行会被跳过，除非开启了补跑。",
  "automationsCommandTimeout": "超时（秒）",
  "automationsCommandRequired": "命令不能为空",
  "automationsCatchUpOnce": "启动后补跑一次",
  "automationsRunStatusFailed": "失败",
  "automationsRunStatusTimedOut": "超时",
  "automationsRunStatusSkippedOverlap": "已跳过（上次仍在运行）",
  "automationsExitCode": "退出码 {code}",
```

Run: `cd client && flutter gen-l10n`
Expected: `lib/l10n/app_localizations*.dart` 重新生成，无报错。

- [ ] **Step 5: 跑测试**

Run: `cd client && dart run tool/run_tests.dart test/pages/automations/automation_editor_dialog_test.dart`
Expected: PASS

- [ ] **Step 6: 提交**

```bash
git add client/lib/pages/automations client/lib/l10n
git commit -m "feat(automation-ui): add the command action to the editor and run history"
```

---

### Task 11: 技能文档与收尾验证

**Files:**
- Modify: `client/lib/services/catalog/managed_skills/teampilot-catalog/SKILL.md`

- [ ] **Step 1: 补 skill 说明**

在 automation 段落补：

```markdown
- 执行命令：`create_automation` 传 `action: "runCommand"` + `command`（一行 shell，最长 2000 字符），
  可选 `working_directory`（必须在该 workspace 的某个 folder 下）、`timeout_seconds`（30–1800，默认 300）、
  `catch_up`（`none` / `once`）、`enabled`（默认 false）。命令跑在 workspace 所在运行时
  （本地 / WSL / SSH / Termux），输出只写运行历史，不回投会话。
- 只在 TeamPilot 运行期间执行；关掉应用期间错过的运行默认跳过，`catch_up: "once"` 时启动补跑一次。
```

- [ ] **Step 2: 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues found

Run: `cd client && dart run tool/run_tests.dart`
Expected: 全绿

- [ ] **Step 3: 提交**

```bash
git add client/lib/services/catalog/managed_skills/teampilot-catalog/SKILL.md
git commit -m "docs(skill): document runCommand automations"
```

---

## 完成标准

- `AutomationAction.runCommand` 可从 UI 和 MCP 创建，默认禁用；MCP 显式 `enabled: true` 时立即启用。
- 到点执行真的跑在 workspace 的运行时上，exit code、输出尾部、耗时写进运行历史。
- 超时会杀掉进程，且不会阻塞其他 automation 的调度。
- `catch_up: once` 在应用启动时补跑一次；`none` 维持原来的 `skippedMissed`。
- 同一条 automation 不会并发跑两份（`skippedOverlap`）。
- `flutter analyze` 无问题，`dart run tool/run_tests.dart` 全绿。
