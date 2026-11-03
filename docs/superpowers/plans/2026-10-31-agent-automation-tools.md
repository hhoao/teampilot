# Agent 定时任务工具（automation catalog kind）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `teampilot` catalog MCP 暴露 5 个 automation 工具，agent 可查看/创建/修改/删除/启停/试跑定时任务。

**Architecture:** 在 catalog 的 kind 注册表里新增第 4 个 `automation` module，复用现有 transport / policy / gateway；module 只依赖 `AutomationRepository`、`AutomationScheduleCalculator` 与少量回调，写操作串行化，成功后向 `CatalogMutationBus` 发 `kind: 'automation'` 事件驱动 UI 刷新。

**Tech Stack:** Flutter / Dart 3、flutter_bloc（仅接线）、MCP JSON-RPC（复用）、`flutter_test`。

**Spec:** `docs/superpowers/specs/2026-10-31-agent-automation-tools-design.md`

## Global Constraints

- 绝不直接跑 `flutter test`：一律 `cd client && dart run tool/run_tests.dart <paths>`。
- 收尾必须 `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`（先跑改动文件，最后全量一次）。
- 所有 automation 写入必须经 `AutomationRepository`，不得直接操作 `automations.json`。
- `workspace_id` 只取 `CatalogRequest.workspaceId`，不接受模型传参。
- `create` 恒写 `enabled: false`；`enabled` 只在 `update` 显式传参时改变。
- 注释、日志、工具描述用英文；用户可见文案走 l10n（本计划不新增 UI 文案，因此不涉及 arb）。
- 不用 `print`，诊断走 `AppLogger`。
- 单文件超过约 400 行视为信号，模块拆成 tools / module 两个文件。

---

## 文件结构

- Create `client/lib/services/catalog/modules/automation_catalog_tools.dart`：5 个 `CatalogToolSpec` 常量。
- Create `client/lib/services/catalog/modules/automation_catalog_module.dart`：`AutomationCatalogModule`。
- Modify `client/lib/services/catalog/catalog_kind.dart`：`CatalogOp` 加 `run`。
- Modify `client/lib/services/catalog/catalog_kind_registry.dart`：`run_` 前缀。
- Modify `client/lib/services/catalog/modules/{skill,plugin,mcp}_catalog_module.dart`：穷尽 switch 补 `run` 分支。
- Modify `client/lib/services/catalog/catalog_mcp_policy.dart`：静态登记 automation 工具。
- Modify `client/lib/app/app_shell.dart`：注册 module、订阅 bus。
- Modify `client/lib/services/catalog/managed_skills/teampilot-catalog/SKILL.md` 与 `client/lib/services/catalog/providers/teampilot_catalog_skill_md.dart`：同步文档。
- Create `client/test/services/catalog/automation_catalog_module_test.dart`。
- Modify `client/test/services/catalog/support/fake_catalog_module.dart`、`catalog_kind_registry_test.dart`、`catalog_mcp_handler_test.dart`。

---

### Task 1: 增加 `CatalogOp.run` 与 `run_` 路由

**Files:**
- Modify: `client/lib/services/catalog/catalog_kind.dart:4-14`
- Modify: `client/lib/services/catalog/catalog_kind_registry.dart:16-25`
- Modify: `client/lib/services/catalog/modules/skill_catalog_module.dart:62-73`
- Modify: `client/lib/services/catalog/modules/plugin_catalog_module.dart`（`handle` 的 switch）
- Modify: `client/lib/services/catalog/modules/mcp_catalog_module.dart:49-61`
- Test: `client/test/services/catalog/support/fake_catalog_module.dart`
- Test: `client/test/services/catalog/catalog_kind_registry_test.dart`

**Interfaces:**
- Produces: `CatalogOp.run`；`run_<kind>` 工具名路由到 `(kind, CatalogOp.run)`。后续 Task 2 的 module 依赖它。

- [ ] **Step 1: 写失败测试**

在 `fake_catalog_module.dart` 的 `advertise()` 列表末尾加：

```dart
    if (kind == 'automation')
      CatalogToolSpec(
        name: 'run_automation',
        description: 'Run automation now',
        inputSchema: const {'type': 'object', 'properties': {}},
        mutating: true,
      ),
```

在 `catalog_kind_registry_test.dart` 的 `main()` 末尾加：

```dart
  test('dispatch maps run_automation to automation run op', () async {
    final module = FakeCatalogModule(kind: 'automation');
    final registry = CatalogKindRegistry()..register(module);
    final result = await registry.dispatch('run_automation', req());
    expect(module.lastOp, CatalogOp.run);
    expect(result.kind, 'automation');
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/catalog/catalog_kind_registry_test.dart`
Expected: 编译失败，`CatalogOp.run` 未定义。

- [ ] **Step 3: 加枚举值与路由**

`catalog_kind.dart` 的 `enum CatalogOp` 末尾加 `run,`：

```dart
enum CatalogOp {
  search,
  list,
  read,
  install,
  importPath,
  create,
  update,
  unbind,
  delete,
  run,
}
```

`catalog_kind_registry.dart` 的 `_opPrefixes` 加一行：

```dart
const _opPrefixes = <String, CatalogOp>{
  'search_': CatalogOp.search,
  'read_': CatalogOp.read,
  'install_': CatalogOp.install,
  'import_': CatalogOp.importPath,
  'create_': CatalogOp.create,
  'update_': CatalogOp.update,
  'unbind_': CatalogOp.unbind,
  'delete_': CatalogOp.delete,
  'run_': CatalogOp.run,
};
```

- [ ] **Step 4: 补三个 module 的穷尽 switch**

skill / plugin / mcp 三个 module 的 `switch (op)` 各加一个分支（`<kind>` 分别换成 `skill`、`plugin`、`mcp`）：

```dart
      CatalogOp.run => throw CatalogException(
        'unsupported_op',
        '<kind> does not support run',
      ),
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/catalog/catalog_kind_registry_test.dart`
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/catalog/catalog_kind.dart client/lib/services/catalog/catalog_kind_registry.dart client/lib/services/catalog/modules/skill_catalog_module.dart client/lib/services/catalog/modules/plugin_catalog_module.dart client/lib/services/catalog/modules/mcp_catalog_module.dart client/test/services/catalog/support/fake_catalog_module.dart client/test/services/catalog/catalog_kind_registry_test.dart
git commit -m "feat(catalog): add run op and run_ tool routing"
```

---

### Task 2: tools 常量 + module 的 list/read/create

**Files:**
- Create: `client/lib/services/catalog/modules/automation_catalog_tools.dart`
- Create: `client/lib/services/catalog/modules/automation_catalog_module.dart`
- Test: `client/test/services/catalog/automation_catalog_module_test.dart`

**Interfaces:**
- Consumes: `CatalogOp.run`（Task 1）。
- Produces:
  - `automationCatalogTools`（`List<CatalogToolSpec>`）
  - `AutomationCatalogModule({required AutomationRepository repository, required AutomationScheduleCalculator scheduleCalculator, required CatalogMutationBus bus, required AutomationRunNow runNow, AutomationSessionExists? sessionExists, bool Function(String)? teamExists, bool Function(String)? presetExists, int Function()? nowMs, String Function()? newId, String Function()? defaultTimezone})`
  - `typedef AutomationRunNow = Future<void> Function(String workspaceId, String automationId);`
  - `typedef AutomationSessionExists = Future<bool> Function(String sessionId, String workspaceId);`
  - `kind == 'automation'`

- [ ] **Step 1: 写失败测试**

创建 `automation_catalog_module_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/repositories/automation_repository.dart';
import 'package:teampilot/services/automation/automation_schedule_calculator.dart';
import 'package:teampilot/services/catalog/catalog_kind.dart';
import 'package:teampilot/services/catalog/catalog_mutation_bus.dart';
import 'package:teampilot/services/catalog/modules/automation_catalog_module.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  const workspaceId = 'ws1';
  final now = DateTime.utc(2026, 10, 31, 8).millisecondsSinceEpoch;

  late AutomationRepository repo;
  late AutomationCatalogModule module;
  late List<String> dispatched;
  late List<CatalogMutationEvent> events;

  setUp(() {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    dispatched = <String>[];
    events = <CatalogMutationEvent>[];
    final bus = CatalogMutationBus();
    bus.listen().listen(events.add);
    module = AutomationCatalogModule(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      bus: bus,
      runNow: (workspace, id) async => dispatched.add('$workspace/$id'),
      sessionExists: (sessionId, ws) async =>
          ws == workspaceId && sessionId == 'sess-1',
      teamExists: (teamId) => teamId == 'team-1',
      presetExists: (presetId) => presetId == 'preset-1',
      nowMs: () => now,
      newId: () => 'auto-1',
      defaultTimezone: () => 'UTC',
    );
  });

  CatalogRequest request(Map<String, Object?> args, {String sessionId = 'sess-1'}) {
    return CatalogRequest(
      sessionId: sessionId,
      workspaceId: workspaceId,
      arguments: args,
      workFs: LocalFilesystem(),
      allowedRoots: const [],
    );
  }

  test('create forces disabled and returns the next run preview', () async {
    final result = await module.handle(
      CatalogOp.create,
      request({
        'name': 'Daily standup',
        'message': 'Summarize yesterday',
        'schedule': {'type': 'daily', 'time': '09:00'},
      }),
    );

    expect(result.ok, isTrue);
    expect(result.kind, 'automation');
    expect(result.restartRequired, isFalse);
    expect(result.ids, ['auto-1']);
    expect(result.data!['enabled'], isFalse);
    expect(result.data!['next_run_at_ms'], isNotNull);
    expect(result.message, contains('Created disabled'));

    final stored = await repo.listForWorkspace(workspaceId);
    expect(stored, hasLength(1));
    expect(stored.single.enabled, isFalse);
    expect(stored.single.sessionId, 'sess-1');
    expect(stored.single.timezone, 'UTC');
  });

  test('create rejects an invalid cron', () async {
    await expectLater(
      module.handle(
        CatalogOp.create,
        request({
          'name': 'bad',
          'message': 'x',
          'schedule': {'type': 'custom', 'cron': 'not a cron'},
        }),
      ),
      throwsA(
        isA<CatalogException>().having((e) => e.code, 'code', 'schedule_invalid'),
      ),
    );
  });

  test('create launchPrompt requires a resolvable target', () async {
    await expectLater(
      module.handle(
        CatalogOp.create,
        request({
          'name': 'x',
          'message': 'x',
          'action': 'launchPrompt',
          'team_id': 'missing-team',
          'schedule': {'type': 'daily'},
        }),
      ),
      throwsA(
        isA<CatalogException>().having((e) => e.code, 'code', 'target_invalid'),
      ),
    );
  });

  test('create launchPrompt stores team mode fields', () async {
    final result = await module.handle(
      CatalogOp.create,
      request({
        'name': 'team run',
        'message': 'go',
        'action': 'launchPrompt',
        'team_id': 'team-1',
        'schedule': {'type': 'weekly', 'time': '10:30', 'day_of_week': 3},
      }),
    );
    final stored = (await repo.listForWorkspace(workspaceId)).single;
    expect(result.ok, isTrue);
    expect(stored.isPersonal, isFalse);
    expect(stored.teamId, 'team-1');
    expect(stored.targetMemberId, 'team-lead');
    expect(stored.preset, AutomationSchedulePreset.weekly);
    expect(stored.dayOfWeek, 3);
    expect(stored.hourMinute, '10:30');
  });

  test('list groups automations and their latest run', () async {
    await module.handle(
      CatalogOp.create,
      request({
        'name': 'a',
        'message': 'm',
        'schedule': {'type': 'hourly', 'minute': 5},
      }),
    );
    final result = await module.handle(CatalogOp.list, request(const {}));
    final data = result.data!['automation']! as Map<String, Object?>;
    final items = data['items']! as List;
    expect(items, hasLength(1));
    expect((items.single as Map)['id'], 'auto-1');
    expect((items.single as Map)['summary'], 'Hourly at :05');
    expect((items.single as Map)['last_run'], isNull);
  });

  test('read without id behaves like list', () async {
    final result = await module.handle(CatalogOp.read, request(const {}));
    expect(result.data!.containsKey('automation'), isTrue);
  });

  test('read with a foreign workspace id is not_found', () async {
    final foreign = Automation(
      id: 'other',
      name: 'other',
      action: AutomationAction.scheduledMessage,
      workspaceId: 'ws2',
      sessionId: 'sess-2',
      message: 'x',
      preset: AutomationSchedulePreset.daily,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1,
      enabled: false,
      createdAtMs: 1,
      updatedAtMs: 1,
    );
    await repo.upsert(foreign);
    await expectLater(
      module.handle(CatalogOp.read, request(const {'id': 'other'})),
      throwsA(isA<CatalogException>().having((e) => e.code, 'code', 'not_found')),
    );
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/catalog/automation_catalog_module_test.dart`
Expected: 编译失败，`automation_catalog_module.dart` 不存在。

- [ ] **Step 3: 写 tools 常量**

创建 `automation_catalog_tools.dart`：

```dart
import '../catalog_kind.dart';

const automationCatalogTools = <CatalogToolSpec>[
  CatalogToolSpec(
    name: 'read_automation',
    description:
        'List this workspace automations, or read one automation and its '
        'recent runs when `id` is given',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
    },
    mutating: false,
  ),
  CatalogToolSpec(
    name: 'create_automation',
    description:
        'Create an automation. Always created disabled; enable it in the '
        'Automations page or with update_automation.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'name': {'type': 'string'},
        'message': {'type': 'string'},
        'action': {
          'type': 'string',
          'enum': ['scheduledMessage', 'launchPrompt'],
        },
        'session_id': {'type': 'string'},
        'schedule': {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'enum': [
                'hourly',
                'daily',
                'weekdays',
                'weekly',
                'custom',
                'once',
              ],
            },
            'time': {'type': 'string'},
            'minute': {'type': 'integer'},
            'day_of_week': {'type': 'integer'},
            'cron': {'type': 'string'},
            'at': {'type': ['string', 'integer']},
            'timezone': {'type': 'string'},
            'dtstart_ms': {'type': 'integer'},
          },
          'required': ['type'],
        },
        'max_run_count': {'type': 'integer'},
        'missed_run_grace_minutes': {'type': 'integer'},
        'reuse_session': {'type': 'boolean'},
        'team_id': {'type': 'string'},
        'target_member_id': {'type': 'string'},
        'preset_id': {'type': 'string'},
      },
      'required': ['name', 'message', 'schedule'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'update_automation',
    description:
        'Patch an automation. Only the provided fields change; `enabled` '
        'toggles scheduling on or off.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
        'name': {'type': 'string'},
        'message': {'type': 'string'},
        'schedule': {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'enum': [
                'hourly',
                'daily',
                'weekdays',
                'weekly',
                'custom',
                'once',
              ],
            },
            'time': {'type': 'string'},
            'minute': {'type': 'integer'},
            'day_of_week': {'type': 'integer'},
            'cron': {'type': 'string'},
            'at': {'type': ['string', 'integer']},
            'timezone': {'type': 'string'},
            'dtstart_ms': {'type': 'integer'},
          },
          'required': ['type'],
        },
        'enabled': {'type': 'boolean'},
        'max_run_count': {'type': 'integer'},
        'missed_run_grace_minutes': {'type': 'integer'},
        'reuse_session': {'type': 'boolean'},
        'target_member_id': {'type': 'string'},
      },
      'required': ['id'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'delete_automation',
    description: 'Delete an automation and its run history',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
      'required': ['id'],
    },
    mutating: true,
  ),
  CatalogToolSpec(
    name: 'run_automation',
    description:
        'Dispatch an automation immediately, even when it is disabled. '
        'Does not enable the automation.',
    inputSchema: {
      'type': 'object',
      'properties': {
        'id': {'type': 'string'},
      },
      'required': ['id'],
    },
    mutating: true,
  ),
];
```

- [ ] **Step 4: 写 module（list/read/create 实现，其余抛 unsupported）**

创建 `automation_catalog_module.dart`：

```dart
import 'dart:async';

import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../../../models/automation.dart';
import '../../../repositories/automation_repository.dart';
import '../../automation/automation_schedule_calculator.dart';
import '../../automation/automation_schedule_defaults.dart';
import '../catalog_kind.dart';
import '../catalog_mutation_bus.dart';
import 'automation_catalog_tools.dart';

typedef AutomationRunNow =
    Future<void> Function(String workspaceId, String automationId);
typedef AutomationSessionExists =
    Future<bool> Function(String sessionId, String workspaceId);

const _createdDisabledMessage =
    'Created disabled. Enable it in Automations, or call update_automation '
    'with enabled:true.';

class AutomationCatalogModule implements CatalogKindModule {
  AutomationCatalogModule({
    required this.repository,
    required this.scheduleCalculator,
    required this.bus,
    required this.runNow,
    this.sessionExists,
    this.teamExists,
    this.presetExists,
    int Function()? nowMs,
    String Function()? newId,
    String Function()? defaultTimezone,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _newId = newId ?? (() => const Uuid().v4()),
       _defaultTimezone = defaultTimezone ?? resolveDeviceTimezoneIdentifier;

  final AutomationRepository repository;
  final AutomationScheduleCalculator scheduleCalculator;
  final CatalogMutationBus bus;
  final AutomationRunNow runNow;
  final AutomationSessionExists? sessionExists;
  final bool Function(String teamId)? teamExists;
  final bool Function(String presetId)? presetExists;
  final int Function() _nowMs;
  final String Function() _newId;
  final String Function() _defaultTimezone;

  Future<void> _writes = Future<void>.value();

  @override
  String get kind => 'automation';

  @override
  bool get supportsCreate => true;

  @override
  bool get supportsImport => false;

  @override
  bool get supportsInstall => false;

  @override
  List<CatalogToolSpec> advertise() => automationCatalogTools;

  @override
  Future<CatalogResult> handle(CatalogOp op, CatalogRequest req) {
    return switch (op) {
      CatalogOp.list => _list(req),
      CatalogOp.read => _read(req),
      CatalogOp.create => _serialized(() => _create(req)),
      CatalogOp.update => _serialized(() => _update(req)),
      CatalogOp.delete => _serialized(() => _delete(req)),
      CatalogOp.run => _serialized(() => _run(req)),
      CatalogOp.search ||
      CatalogOp.install ||
      CatalogOp.importPath ||
      CatalogOp.unbind =>
        throw CatalogException(
          'unsupported_op',
          'automation does not support ${op.name}',
        ),
    };
  }

  Future<CatalogResult> _serialized(Future<CatalogResult> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<CatalogResult> _list(CatalogRequest req) async {
    final automations = await repository.listForWorkspace(req.workspaceId);
    final runs = await repository.runsForWorkspace(req.workspaceId);
    final latest = <String, AutomationRun>{};
    for (final run in runs) {
      final current = latest[run.automationId];
      if (current == null || run.startedAtMs >= current.startedAtMs) {
        latest[run.automationId] = run;
      }
    }
    return _ok(req, [for (final a in automations) a.id], {
      'automation': {
        'items': [
          for (final automation in automations)
            {
              ...automation.toJson(),
              'summary': scheduleCalculator.formatScheduleSummary(automation),
              'last_run': latest[automation.id]?.toJson(),
            },
        ],
      },
    });
  }

  Future<CatalogResult> _read(CatalogRequest req) async {
    final id = _optionalId(req);
    if (id == null) return _list(req);
    final automation = await _require(req.workspaceId, id);
    final runs = await repository.runsFor(
      req.workspaceId,
      automationId: automation.id,
    );
    final recent = [...runs]
      ..sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));
    return _ok(req, [automation.id], {
      'automation': {
        ...automation.toJson(),
        'summary': scheduleCalculator.formatScheduleSummary(automation),
        'recent_runs': [for (final run in recent.take(5)) run.toJson()],
      },
    });
  }

  Future<CatalogResult> _create(CatalogRequest req) async {
    final now = _nowMs();
    final schedule = _parseSchedule(req.arguments['schedule'], now: now);
    final action = _parseAction(req.arguments['action']);
    final name = _requireText(req, 'name');
    final message = _requireText(req, 'message');
    final id = _newId();

    final Automation draft;
    if (action == AutomationAction.scheduledMessage) {
      final sessionId = _text(req.arguments['session_id']) ?? req.sessionId;
      final exists = sessionExists;
      if (exists != null && !await exists(sessionId, req.workspaceId)) {
        throw CatalogException(
          'invalid_argument',
          'session not found in this workspace: $sessionId',
        );
      }
      draft = _baseAutomation(
        id: id,
        name: name,
        action: action,
        workspaceId: req.workspaceId,
        message: message,
        schedule: schedule,
        now: now,
      ).copyWith(sessionId: sessionId);
    } else {
      final teamId = _text(req.arguments['team_id']);
      final presetId = _text(req.arguments['preset_id']);
      if (teamId == null && presetId == null) {
        throw CatalogException(
          'target_invalid',
          'launchPrompt requires team_id or preset_id',
        );
      }
      if (teamId != null) {
        final exists = teamExists;
        if (exists != null && !exists(teamId)) {
          throw CatalogException('target_invalid', 'unknown team: $teamId');
        }
      } else {
        final exists = presetExists;
        if (exists != null && !exists(presetId!)) {
          throw CatalogException('target_invalid', 'unknown preset: $presetId');
        }
      }
      draft = _baseAutomation(
        id: id,
        name: name,
        action: action,
        workspaceId: req.workspaceId,
        message: message,
        schedule: schedule,
        now: now,
        isPersonal: teamId == null,
        presetId: teamId == null ? presetId : null,
        teamId: teamId,
        targetMemberId:
            _text(req.arguments['target_member_id']) ?? 'team-lead',
        reuseSession: req.arguments['reuse_session'] == true,
      );
    }

    draft.validate();
    final preview = scheduleCalculator.computeNextRunAtMs(
      draft.copyWith(enabled: true),
      afterMs: now,
    );
    final saved = await repository.upsert(draft);
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
      message: _createdDisabledMessage,
    );
  }

  Automation _baseAutomation({
    required String id,
    required String name,
    required AutomationAction action,
    required String workspaceId,
    required String message,
    required _ScheduleSpec schedule,
    required int now,
    bool isPersonal = true,
    String? presetId,
    String? teamId,
    String targetMemberId = 'team-lead',
    bool reuseSession = false,
  }) {
    return Automation(
      id: id,
      name: name,
      action: action,
      workspaceId: workspaceId,
      isPersonal: isPersonal,
      presetId: presetId,
      teamId: teamId,
      targetMemberId: targetMemberId,
      message: message,
      reuseSession: reuseSession,
      preset: schedule.preset,
      customCron: schedule.customCron,
      dayOfWeek: schedule.dayOfWeek,
      minute: schedule.minute,
      hourMinute: schedule.hourMinute,
      timezone: schedule.timezone,
      dtstartMs: schedule.dtstartMs,
      runAtMs: schedule.runAtMs,
      enabled: false,
      missedRunGraceMinutes: 15,
      createdAtMs: now,
      updatedAtMs: now,
    );
  }

  Future<CatalogResult> _update(CatalogRequest req) => throw UnsupportedError(
    'implemented in Task 3',
  );

  Future<CatalogResult> _delete(CatalogRequest req) => throw UnsupportedError(
    'implemented in Task 3',
  );

  Future<CatalogResult> _run(CatalogRequest req) => throw UnsupportedError(
    'implemented in Task 3',
  );

  Future<Automation> _require(String workspaceId, String id) async {
    final automations = await repository.listForWorkspace(workspaceId);
    final match = automations.where((a) => a.id == id).firstOrNull;
    if (match == null) {
      throw CatalogException('not_found', 'automation not found: $id');
    }
    return match;
  }

  void _emit(CatalogOp op, CatalogRequest req, List<String> ids) {
    bus.emit(
      CatalogMutationEvent(
        kind: kind,
        op: op,
        ids: ids,
        workspaceId: req.workspaceId,
      ),
    );
  }

  CatalogResult _ok(
    CatalogRequest req,
    List<String> ids,
    Map<String, Object?> data, {
    String? message,
  }) {
    return CatalogResult.ok(
      kind: kind,
      ids: ids,
      workspaceId: req.workspaceId,
      restartRequired: false,
      data: data,
      message: message,
    );
  }

  _ScheduleSpec _parseSchedule(Object? raw, {required int now}) {
    if (raw is! Map) {
      throw CatalogException('schedule_invalid', 'schedule is required');
    }
    final map = raw.cast<String, Object?>();
    final type = _text(map['type'])?.toLowerCase();
    if (type == null) {
      throw CatalogException('schedule_invalid', 'schedule.type is required');
    }
    final timezone = _text(map['timezone']) ?? _defaultTimezone();
    final dtstartMs = _int(map['dtstart_ms']) ?? now;
    const defaultTime = '09:00';
    try {
      switch (type) {
        case 'hourly':
          final minute = _int(map['minute']) ?? 0;
          if (minute < 0 || minute > 59) {
            throw ArgumentError('minute must be 0..59');
          }
          return _ScheduleSpec(
            preset: AutomationSchedulePreset.hourly,
            minute: minute,
            hourMinute: defaultTime,
            timezone: timezone,
            dtstartMs: dtstartMs,
          );
        case 'daily':
        case 'weekdays':
          final time = _text(map['time']) ?? defaultTime;
          parseHourMinute(time);
          return _ScheduleSpec(
            preset: type == 'daily'
                ? AutomationSchedulePreset.daily
                : AutomationSchedulePreset.weekdays,
            hourMinute: time,
            timezone: timezone,
            dtstartMs: dtstartMs,
          );
        case 'weekly':
          final time = _text(map['time']) ?? defaultTime;
          parseHourMinute(time);
          final day = _int(map['day_of_week']) ?? 1;
          if (day < 1 || day > 7) {
            throw ArgumentError('day_of_week must be 1..7');
          }
          return _ScheduleSpec(
            preset: AutomationSchedulePreset.weekly,
            hourMinute: time,
            dayOfWeek: day,
            timezone: timezone,
            dtstartMs: dtstartMs,
          );
        case 'custom':
          final cron = _text(map['cron']);
          if (cron == null || !scheduleCalculator.isValidCron(cron)) {
            throw ArgumentError('invalid cron expression');
          }
          return _ScheduleSpec(
            preset: AutomationSchedulePreset.custom,
            customCron: cron,
            timezone: timezone,
            dtstartMs: dtstartMs,
          );
        case 'once':
          final at = _runAtMs(map['at']);
          if (at == null || at <= now) {
            throw ArgumentError('at must be a future timestamp');
          }
          return _ScheduleSpec(
            preset: AutomationSchedulePreset.once,
            runAtMs: at,
            timezone: timezone,
            dtstartMs: dtstartMs,
          );
        default:
          throw ArgumentError('unknown schedule type: $type');
      }
    } on ArgumentError catch (error) {
      throw CatalogException(
        'schedule_invalid',
        error.message?.toString() ?? 'invalid schedule',
      );
    }
  }

  int? _runAtMs(Object? raw) {
    if (raw is int) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim())?.millisecondsSinceEpoch;
    }
    return null;
  }

  AutomationAction _parseAction(Object? raw) {
    final name = _text(raw) ?? AutomationAction.scheduledMessage.name;
    for (final value in AutomationAction.values) {
      if (value.name == name) return value;
    }
    throw CatalogException('invalid_argument', 'unknown action: $name');
  }

  String _requireText(CatalogRequest req, String key) {
    final value = _text(req.arguments[key]);
    if (value == null) {
      throw CatalogException('invalid_argument', '$key is required');
    }
    return value;
  }

  String _requireId(CatalogRequest req) {
    final id = _text(req.arguments['id']);
    if (id == null) {
      throw CatalogException('invalid_argument', 'id is required');
    }
    return id;
  }

  String? _optionalId(CatalogRequest req) => _text(req.arguments['id']);

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}

class _ScheduleSpec {
  const _ScheduleSpec({
    required this.preset,
    required this.timezone,
    required this.dtstartMs,
    this.customCron,
    this.dayOfWeek,
    this.minute = 0,
    this.hourMinute = '09:00',
    this.runAtMs,
  });

  final AutomationSchedulePreset preset;
  final String? customCron;
  final int? dayOfWeek;
  final int minute;
  final String hourMinute;
  final String timezone;
  final int dtstartMs;
  final int? runAtMs;
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/catalog/automation_catalog_module_test.dart`
Expected: 8 个测试全部 PASS。

- [ ] **Step 6: 提交**

```bash
git add client/lib/services/catalog/modules/automation_catalog_tools.dart client/lib/services/catalog/modules/automation_catalog_module.dart client/test/services/catalog/automation_catalog_module_test.dart
git commit -m "feat(catalog): add automation module list/read/create"
```

---

### Task 3: update / delete / run_automation

**Files:**
- Modify: `client/lib/services/catalog/modules/automation_catalog_module.dart`（替换三个 stub）
- Test: `client/test/services/catalog/automation_catalog_module_test.dart`

**Interfaces:**
- Consumes: 全部来自 Task 2。
- Produces: 完整 5 个工具行为。

- [ ] **Step 1: 写失败测试**

在 `automation_catalog_module_test.dart` 的 `main()` 末尾加：

```dart
  Future<String> createDaily() async {
    final result = await module.handle(
      CatalogOp.create,
      request({
        'name': 'daily',
        'message': 'm',
        'schedule': {'type': 'daily', 'time': '09:00'},
      }),
    );
    return result.ids.single;
  }

  test('update keeps unspecified fields and recomputes on enable', () async {
    final id = await createDaily();
    await module.handle(
      CatalogOp.update,
      request({'id': id, 'name': 'renamed', 'enabled': true}),
    );
    final stored = (await repo.listForWorkspace(workspaceId)).single;
    expect(stored.name, 'renamed');
    expect(stored.message, 'm');
    expect(stored.enabled, isTrue);
    expect(stored.nextRunAtMs, isNotNull);
  });

  test('update to disabled clears the next run', () async {
    final id = await createDaily();
    await module.handle(
      CatalogOp.update,
      request({'id': id, 'enabled': true}),
    );
    await module.handle(
      CatalogOp.update,
      request({'id': id, 'enabled': false}),
    );
    final stored = (await repo.listForWorkspace(workspaceId)).single;
    expect(stored.enabled, isFalse);
    expect(stored.nextRunAtMs, isNull);
  });

  test('update can switch a daily schedule to a cron schedule', () async {
    final id = await createDaily();
    await module.handle(
      CatalogOp.update,
      request({
        'id': id,
        'schedule': {'type': 'custom', 'cron': '*/15 * * * *'},
      }),
    );
    final stored = (await repo.listForWorkspace(workspaceId)).single;
    expect(stored.preset, AutomationSchedulePreset.custom);
    expect(stored.customCron, '*/15 * * * *');
    expect(stored.dayOfWeek, isNull);
  });

  test('delete removes the automation and its runs', () async {
    final id = await createDaily();
    await repo.upsertRun(
      workspaceId,
      AutomationRun(
        id: 'run-1',
        automationId: id,
        workspaceId: workspaceId,
        scheduledForMs: now,
        status: AutomationRunStatus.completed,
        trigger: AutomationRunTrigger.manual,
        startedAtMs: now,
        completedAtMs: now,
      ),
    );
    await module.handle(CatalogOp.delete, request({'id': id}));
    expect(await repo.listForWorkspace(workspaceId), isEmpty);
    expect(await repo.runsForWorkspace(workspaceId), isEmpty);
  });

  test('run_automation dispatches and returns the newest run', () async {
    final id = await createDaily();
    await repo.upsertRun(
      workspaceId,
      AutomationRun(
        id: 'run-1',
        automationId: id,
        workspaceId: workspaceId,
        scheduledForMs: now,
        status: AutomationRunStatus.completed,
        trigger: AutomationRunTrigger.manual,
        startedAtMs: now,
        completedAtMs: now,
      ),
    );
    final result = await module.handle(CatalogOp.run, request({'id': id}));
    expect(dispatched, ['$workspaceId/$id']);
    expect((result.data!['run']! as Map)['id'], 'run-1');
  });

  test('run_automation rejects a run-limit-reached automation', () async {
    final id = await createDaily();
    final stored = (await repo.listForWorkspace(workspaceId)).single;
    await repo.upsert(
      stored.copyWith(
        preset: AutomationSchedulePreset.once,
        runAtMs: now + 60000,
        runCount: 1,
      ),
    );
    await expectLater(
      module.handle(CatalogOp.run, request({'id': id})),
      throwsA(
        isA<CatalogException>().having(
          (e) => e.code,
          'code',
          'run_limit_reached',
        ),
      ),
    );
  });

  test('every mutation emits an automation bus event', () async {
    await createDaily();
    await Future<void>.delayed(Duration.zero);
    expect(events, isNotEmpty);
    expect(events.every((e) => e.kind == 'automation'), isTrue);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/catalog/automation_catalog_module_test.dart`
Expected: FAIL，`UnsupportedError: implemented in Task 3`。

- [ ] **Step 3: 实现三个方法**

把 Task 2 里的三个 stub 整体替换成：

```dart
  Future<CatalogResult> _update(CatalogRequest req) async {
    final id = _requireId(req);
    final existing = await _require(req.workspaceId, id);
    final now = _nowMs();
    var next = existing;

    if (req.arguments.containsKey('name')) {
      next = next.copyWith(name: _requireText(req, 'name'));
    }
    if (req.arguments.containsKey('message')) {
      next = next.copyWith(message: _requireText(req, 'message'));
    }
    if (req.arguments.containsKey('schedule')) {
      final schedule = _parseSchedule(req.arguments['schedule'], now: now);
      next = next.copyWith(
        preset: schedule.preset,
        customCron: schedule.customCron,
        clearCustomCron: schedule.customCron == null,
        dayOfWeek: schedule.dayOfWeek,
        clearDayOfWeek: schedule.dayOfWeek == null,
        minute: schedule.minute,
        hourMinute: schedule.hourMinute,
        timezone: schedule.timezone,
        dtstartMs: schedule.dtstartMs,
        runAtMs: schedule.runAtMs,
        clearRunAtMs: schedule.runAtMs == null,
      );
    }
    if (req.arguments.containsKey('max_run_count')) {
      final maxRunCount = _maxRunCount(req);
      next = next.copyWith(
        maxRunCount: maxRunCount,
        clearMaxRunCount: maxRunCount == null,
      );
    }
    if (req.arguments.containsKey('missed_run_grace_minutes')) {
      next = next.copyWith(missedRunGraceMinutes: _graceMinutes(req));
    }
    if (req.arguments.containsKey('reuse_session')) {
      next = next.copyWith(reuseSession: req.arguments['reuse_session'] == true);
    }
    if (req.arguments.containsKey('target_member_id')) {
      next = next.copyWith(
        targetMemberId:
            _text(req.arguments['target_member_id']) ?? 'team-lead',
      );
    }
    if (req.arguments.containsKey('enabled')) {
      next = next.copyWith(enabled: req.arguments['enabled'] == true);
    }

    next = next.copyWith(updatedAtMs: now);
    next.validate();
    if (next.enabled) {
      final nextMs = scheduleCalculator.computeNextRunAtMs(next, afterMs: now);
      next = next.copyWith(
        enabled: nextMs != null,
        nextRunAtMs: nextMs,
        clearNextRunAtMs: nextMs == null,
      );
    } else {
      next = next.copyWith(clearNextRunAtMs: true);
    }

    final saved = await repository.upsert(next);
    _emit(CatalogOp.update, req, [saved.id]);
    return _ok(req, [saved.id], {
      'automation': saved.toJson(),
      'summary': scheduleCalculator.formatScheduleSummary(saved),
      'enabled': saved.enabled,
      'next_run_at_ms': saved.nextRunAtMs,
    });
  }

  Future<CatalogResult> _delete(CatalogRequest req) async {
    final id = _requireId(req);
    final existing = await _require(req.workspaceId, id);
    await repository.delete(existing.workspaceId, existing.id);
    _emit(CatalogOp.delete, req, [existing.id]);
    return _ok(
      req,
      [existing.id],
      {
        'automation': {'id': existing.id, 'deleted': true},
      },
      message: 'Automation deleted.',
    );
  }

  Future<CatalogResult> _run(CatalogRequest req) async {
    final id = _requireId(req);
    final automation = await _require(req.workspaceId, id);
    if (automation.isRunLimitReached) {
      throw CatalogException(
        'run_limit_reached',
        'automation has reached its run limit: $id',
      );
    }
    await runNow(automation.workspaceId, automation.id);
    final runs = await repository.runsFor(
      automation.workspaceId,
      automationId: automation.id,
    );
    final latest = [...runs]
      ..sort((a, b) => b.startedAtMs.compareTo(a.startedAtMs));
    return _ok(req, [automation.id], {
      'run': latest.isEmpty ? null : latest.first.toJson(),
      'automation': (await _require(req.workspaceId, id)).toJson(),
    });
  }

  int? _maxRunCount(CatalogRequest req) {
    final raw = _int(req.arguments['max_run_count']);
    if (raw == null || raw == 0) return null;
    if (raw < 0) {
      throw CatalogException('invalid_argument', 'max_run_count must be >= 1');
    }
    return raw;
  }

  int _graceMinutes(CatalogRequest req) {
    final raw = _int(req.arguments['missed_run_grace_minutes']) ?? 15;
    if (raw < 0) {
      throw CatalogException(
        'invalid_argument',
        'missed_run_grace_minutes must be >= 0',
      );
    }
    return raw;
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/catalog/automation_catalog_module_test.dart`
Expected: 15 个测试全部 PASS。

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/catalog/modules/automation_catalog_module.dart client/test/services/catalog/automation_catalog_module_test.dart
git commit -m "feat(catalog): add automation update/delete/run tools"
```

---

### Task 4: policy 登记与 handler 暴露

**Files:**
- Modify: `client/lib/services/catalog/catalog_mcp_policy.dart:20-31,62-82`
- Test: `client/test/services/catalog/catalog_kind_registry_test.dart`
- Test: `client/test/services/catalog/catalog_mcp_handler_test.dart`

**Interfaces:**
- Consumes: `automationCatalogTools`（Task 2）。
- Produces: Claude/Cursor allow-list 里出现 `read_automation`（读），写工具落进 mutate 集合；`tools/list` 含 5 个名字。

- [ ] **Step 1: 写失败测试**

在 `catalog_kind_registry_test.dart` 末尾加：

```dart
  test('advertised policy includes automation read and mutate tools', () {
    final registry = CatalogMcpPolicy.advertisedRegistry();
    expect(CatalogMcpPolicy.readToolNames(registry), contains('read_automation'));
    expect(
      CatalogMcpPolicy.mutateToolNames(registry),
      containsAll([
        'create_automation',
        'update_automation',
        'delete_automation',
        'run_automation',
      ]),
    );
    expect(
      CatalogMcpPolicy.claudeAllowEntries(registry),
      contains('mcp__teampilot__read_automation'),
    );
    expect(
      CatalogMcpPolicy.claudeAllowEntries(registry),
      isNot(contains('mcp__teampilot__create_automation')),
    );
  });
```

在 `catalog_mcp_handler_test.dart` 的 `main()` 里追加（并补 import
`catalog_mcp_policy.dart`、`chat/team_bus/mcp/mcp_method.dart`）：

```dart
  test('tools/list advertises the automation tools', () async {
    final handler = CatalogMcpHandler(
      registry: CatalogMcpPolicy.advertisedRegistry(),
    );
    final response = await handler.handle(
      const JsonRpcRequest(method: McpMethod.toolsList, id: 1),
      CatalogMcpSession(
        sessionId: 's',
        workspaceId: 'w',
        workFs: LocalFilesystem(),
        allowedRoots: const [],
      ),
    );
    final tools = (response!.result!['tools']! as List)
        .map((tool) => (tool as Map)['name'])
        .toList();
    expect(
      tools,
      containsAll([
        'read_automation',
        'create_automation',
        'update_automation',
        'delete_automation',
        'run_automation',
      ]),
    );
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && dart run tool/run_tests.dart test/services/catalog/catalog_kind_registry_test.dart test/services/catalog/catalog_mcp_handler_test.dart`
Expected: FAIL，`read_automation` 不在列表中。

- [ ] **Step 3: 登记到 policy**

`catalog_mcp_policy.dart` 顶部 import 加：

```dart
import 'modules/automation_catalog_tools.dart';
```

`advertisedRegistry()` 里加：

```dart
      ..register(
        const _AdvertisedKind(
          'automation',
          automationCatalogTools,
          supportsImport: false,
          supportsInstall: false,
        ),
      );
```

`_AdvertisedKind` 补两个可选参数：

```dart
class _AdvertisedKind implements CatalogKindModule {
  const _AdvertisedKind(
    this.kind,
    this._tools, {
    this.supportsCreate = true,
    this.supportsImport = true,
    this.supportsInstall = true,
  });

  @override
  final String kind;
  final List<CatalogToolSpec> _tools;
  @override
  final bool supportsCreate;
  @override
  final bool supportsImport;
  @override
  final bool supportsInstall;

  @override
  List<CatalogToolSpec> advertise() => _tools;

  @override
  Future<CatalogResult> handle(CatalogOp op, CatalogRequest req) {
    throw UnsupportedError('advertised-only catalog kind');
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && dart run tool/run_tests.dart test/services/catalog/catalog_kind_registry_test.dart test/services/catalog/catalog_mcp_handler_test.dart`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add client/lib/services/catalog/catalog_mcp_policy.dart client/test/services/catalog/catalog_kind_registry_test.dart client/test/services/catalog/catalog_mcp_handler_test.dart
git commit -m "feat(catalog): advertise automation tools in policy"
```

---

### Task 5: app_shell 注册与 UI 刷新

**Files:**
- Modify: `client/lib/app/app_shell.dart:828-829`（字段）、`:2554-2581`（复用 resolver）、`:2587-2596`（注册 + 订阅）、`:3499-3502`（dispose）

**Interfaces:**
- Consumes: `AutomationCatalogModule`、`CatalogMutationEvent`。
- Produces: 运行中的 shell 里 `teampilot` server 暴露 automation 工具；写操作后 Automations 页面立即刷新。

- [ ] **Step 1: 抽出可复用的 resolver 局部变量**

在 `final scheduleCalculator = AutomationScheduleCalculator();`（`:2554`）之前插入：

```dart
    final teamById = (String teamId) {
      final profile = teamCubit.state.byId(teamId);
      return profile is TeamProfile ? profile : null;
    };
    final resolveCliPreset = (String presetId) => cliPresetsCubit.state.presets
        .where((preset) => preset.id == presetId.trim())
        .firstOrNull;
```

把 dispatcher 里的两处内联闭包替换成这两个变量（`teamById: teamById,`、`resolveCliPreset: resolveCliPreset,`）。

- [ ] **Step 2: 注册 module 并订阅 bus**

在 `automationCubit` 构造与 `chatCubit.bindAutomationsChangeNotifier`（`:2587-2596`）之后插入：

```dart
    final runtime = catalogRuntime;
    if (runtime != null) {
      runtime.registry.register(
        AutomationCatalogModule(
          repository: automationRepo,
          scheduleCalculator: scheduleCalculator,
          bus: runtime.bus,
          runNow: automationScheduler.runNow,
          teamExists: (teamId) => teamById(teamId) != null,
          presetExists: (presetId) => resolveCliPreset(presetId) != null,
          sessionExists: (sessionId, workspaceId) async {
            final session = await sessionRepo.findById(sessionId);
            return session != null && session.workspaceId == workspaceId;
          },
        ),
      );
      _automationCatalogSub = runtime.bus.listen().listen((event) {
        if (event.kind != 'automation') return;
        if (!automationCubit.isClosed) {
          unawaited(automationCubit.reloadPreservingScope());
        }
      });
    }
```

- [ ] **Step 3: 加字段并在 dispose 取消订阅**

字段（`:829` 之后）：

```dart
  StreamSubscription<CatalogMutationEvent>? _automationCatalogSub;
```

`dispose()` 开头（`:3501` 之前）加：

```dart
    _automationCatalogSub?.cancel();
```

imports 补：

```dart
import '../services/catalog/catalog_mutation_bus.dart';
import '../services/catalog/modules/automation_catalog_module.dart';
```

- [ ] **Step 4: 静态检查**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: No issues found。

- [ ] **Step 5: 提交**

```bash
git add client/lib/app/app_shell.dart
git commit -m "feat(shell): register automation catalog module and refresh automations"
```

---

### Task 6: 同步 catalog skill 文档并全量验证

**Files:**
- Modify: `client/lib/services/catalog/managed_skills/teampilot-catalog/SKILL.md`
- Modify: `client/lib/services/catalog/providers/teampilot_catalog_skill_md.dart`

- [ ] **Step 1: 更新两处同源文案（内容必须逐字一致）**

description 改成：

```yaml
description: Install, import, create, update, or remove TeamPilot skills, plugins, MCP servers, and automations. Use when the user wants to add, install, find, or import a skill, plugin, or MCP; search skills.sh or a marketplace; run npx or an install script; schedule a recurring task or reminder; or mentions superpowers, context7, or community agent skills. Never write to ~/.claude/skills, .claude/skills, or ~/.claude.json — those paths are wiped on the next TeamPilot session start.
```

正文第一段改成：

```markdown
Use the `teampilot` MCP to search, install, import, create, update, unbind, or delete TeamPilot skills, plugins, and MCP servers, and to list, create, update, delete, enable/disable, or run automations. Skill/plugin/MCP changes bind to the current workspace and take effect after the user reconnects the session; automation changes take effect immediately.
```

Workflow 里插入一条（放在第 4 条之后，原第 5、6 条顺延）：

```markdown
5. Recurring or scheduled work → `create_automation` (created disabled; the user enables it in Automations, or you call `update_automation` with `enabled:true` only when asked). Read with `read_automation`, test with `run_automation`, clean up with `delete_automation`.
```

- [ ] **Step 2: 校验两份文案一致**

Run: `cd client && dart run tool/run_tests.dart test/services/catalog/managed_catalog_skill_provider_test.dart`
Expected: PASS（该测试比对 `SKILL.md` 与 `teampilotCatalogSkillMd`）。

- [ ] **Step 3: 全量验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`
Expected: analyze 无 issue；测试全绿。

- [ ] **Step 4: 提交**

```bash
git add client/lib/services/catalog/managed_skills/teampilot-catalog/SKILL.md client/lib/services/catalog/providers/teampilot_catalog_skill_md.dart
git commit -m "docs(catalog): document automation tools in teampilot-catalog skill"
```

---

## Self-Review

**Spec coverage：**

| spec 要求 | 落在 |
|---|---|
| catalog 第 4 个 kind、5 个工具 | Task 2 / 3 |
| `CatalogOp.run` + `run_` 前缀 + 三个 module 的 switch | Task 1 |
| `create` 恒 disabled、`enabled` 仅显式更新 | Task 2 Step 4、Task 3 Step 3 |
| schedule 六种 type、timezone 默认、once 校验 | Task 2 Step 4 `_parseSchedule` |
| launchPrompt 目标校验（team/preset） | Task 2 Step 4 `_create` |
| list/detail/最近运行 | Task 2 |
| delete 连带清 run | Task 3 |
| run_now 不受 enabled 限制、上限报错 | Task 3 |
| policy 读/写分流、Codex/OpenCode 说明 | Task 4（代码）+ spec 记录 |
| app_shell 后注册 + bus 刷新 + dispose | Task 5 |
| SKILL.md 双份同步 | Task 6 |
| 错误码六种 | Task 2/3 的 `CatalogException` |
| 串行化写 | Task 2 `_serialized` |
| 测试项 | Task 2 / 3 / 4 |

**类型一致性：** `AutomationRunNow` / `AutomationSessionExists` 只在 Task 2 定义一次；`_ScheduleSpec` 字段在 `_parseSchedule` 与 `_baseAutomation` 中同名；`_maxRunCount` / `_graceMinutes` 在 Task 3 定义、Task 3 使用。

**已知取舍：** `update_automation` 不接收 `action` / `session_id` / `team_id` / `preset_id`——改动作类型等于重建，超出本 spec 范围；需要时 `delete` + `create`。
