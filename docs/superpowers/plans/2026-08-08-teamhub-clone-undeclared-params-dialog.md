# Team Hub 克隆时补选未声明启动参数 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `team.json` 可以不写 `teamMode` / `cli`；克隆时对未声明的字段弹对话框补选（native/mixed + CLI），取消则中止克隆；已声明的字段直接用、不弹框。

**Architecture:** `DiscoverableTeam` 拆成「声明字段（可空）+ 生效 getter」；克隆链（`TeamCloneService` → `TeamHubCubit` → `TeamLandingSelection`）透传可选覆盖参数；新增一个共享对话框 helper，两个克隆入口（团队中心页 + 落地选择器）复用。

**Tech Stack:** Flutter / flutter_bloc / shared_ui (Tp 设计系统) / l10n (arb → gen-l10n)

## Global Constraints

- 所有新 UI 用 Tp 设计系统组件（`TpDialog` / `TpButton` / `TpCompactSelect` / `TpHover` / `TpTextStyles`）。
- l10n：只编辑 `client/lib/l10n/app_en.arb` 和 `client/lib/l10n/app_zh.arb`，生成的 `app_localizations*.dart` 一起提交。
- 克隆「取消」= 整个克隆中止，不产生任何本地副作用。
- 已声明的字段直接使用，**不**弹框。
- 完成后必须 `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration` 全绿。

---
## File Map

| 文件 | 责任 | 任务 |
|------|------|------|
| `client/lib/models/discoverable_team.dart` | 声明/生效拆分，`cliDeclared` / `teamModeDeclared` | 1 |
| `client/lib/services/team/team_clone_service.dart` | `clone` 接受覆盖参数 | 2 |
| `client/lib/services/team/team_landing_selection.dart` | `resolveHub` + `cloneTeam` 透传覆盖 | 3 |
| `client/lib/cubits/team_hub_cubit.dart` + `client/lib/app/app_shell.dart` | `TeamCloner` typedef + `clone` 透传 + 接线 | 4 |
| `client/lib/pages/team_hub/team_hub_clone_options_dialog.dart`（新增） | 对话框组件 + `resolveTeamHubCloneOptions` | 5 |
| `client/lib/pages/team_hub/team_hub_page.dart` | 团队中心页 Clone 入口接线 | 6 |
| `client/lib/pages/team_hub/team_landing_picker_sheet.dart` | 落地选择器 Confirm 入口接线 | 7 |
| `client/lib/services/team_hub/builtin_team_templates.dart` | Superpowers Quartet 补 `cli: claude` | 8 |

---

### Task 1: `DiscoverableTeam` 声明/生效拆分

**Files:**
- Modify: `client/lib/models/discoverable_team.dart`（`DiscoverableTeam` 类、`fromJson`、`toJson`、`==`/`hashCode`）
- Test: `client/test/models/discoverable_team_test.dart`

**Interfaces:**
- Produces:
  - `bool get cliDeclared`
  - `bool get teamModeDeclared`
  - `CliTool get cli`（生效值，未声明→`CliTool.claude`）
  - `TeamMode get teamMode`（生效值，未声明→`TeamMode.native`）
  - 构造函数参数名不变（`cli` / `teamMode`，类型改为可空）

- [ ] **Step 1: 写失败测试**

在 `client/test/models/discoverable_team_test.dart` 的 `main()` 里追加：

```dart
  test('undeclared teamMode/cli default to native/claude and are omitted on toJson', () {
    final team = DiscoverableTeam.fromJson(const {
      'key': 'o/r/s',
      'name': 'S',
      'description': '',
      'category': 'AI',
      'updatedAt': 1,
    });
    expect(team.teamMode, TeamMode.native);
    expect(team.cli, CliTool.claude);
    expect(team.teamModeDeclared, isFalse);
    expect(team.cliDeclared, isFalse);
    final json = team.toJson();
    expect(json.containsKey('teamMode'), isFalse);
    expect(json.containsKey('cli'), isFalse);
  });

  test('declared teamMode/cli are preserved', () {
    final team = DiscoverableTeam.fromJson(const {
      'key': 'o/r/s',
      'name': 'S',
      'description': '',
      'category': 'AI',
      'updatedAt': 1,
      'cli': 'codex',
      'teamMode': 'mixed',
    });
    expect(team.teamMode, TeamMode.mixed);
    expect(team.cli, CliTool.codex);
    expect(team.teamModeDeclared, isTrue);
    expect(team.cliDeclared, isTrue);
    final json = team.toJson();
    expect(json['teamMode'], 'mixed');
    expect(json['cli'], 'codex');
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/models/discoverable_team_test.dart`
Expected: FAIL — `teamModeDeclared` / `cliDeclared` 未定义。

- [ ] **Step 3: 实现**

在 `DiscoverableTeam` 类里，把 `cli` / `teamMode` 字段改成私有可空字段 + 生效 getter + 声明判断：

```dart
  final CliTool? _cli;
  final TeamMode? _teamMode;

  /// CLI as declared in the manifest; null when not written.
  CliTool get cli => _cli ?? CliTool.claude;

  /// teamMode as declared in the manifest; null when not written.
  TeamMode get teamMode => _teamMode ?? TeamMode.native;

  bool get cliDeclared => _cli != null;
  bool get teamModeDeclared => _teamMode != null;
```

构造函数签名改为（参数名不变，类型可空，`_cli`/`_teamMode` 由 initializer 赋值）：

```dart
  const DiscoverableTeam({
    required this.key,
    required this.name,
    required this.description,
    required this.category,
    required this.updatedAt,
    this.author,
    this.cli,
    this.teamMode,
    this.extraArgs = '',
    this.roster = const [],
    this.skillDeps = const [],
    this.pluginDeps = const [],
    this.mcpDeps = const [],
  }) : _cli = cli,
       _teamMode = teamMode;
```

`fromJson` 改：

```dart
      cli: CliTool.tryParse(json['cli'] as String?),
      teamMode: TeamMode.tryParse(json['teamMode'] as String?),
```

`toJson` 改（未声明则不输出 key）：

```dart
    if (_cli != null) 'cli': _cli!.value,
    if (_teamMode != null) 'teamMode': _teamMode!.value,
```

`==` 与 `hashCode` 改用 `_cli` / `_teamMode`（替换原 `cli` / `teamMode` 引用）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && flutter test test/models/discoverable_team_test.dart`
Expected: PASS（含原有 round-trip 用例——它显式声明了 cli/teamMode，往返一致）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/discoverable_team.dart client/test/models/discoverable_team_test.dart
git commit -m "feat(team-hub): split declared vs effective teamMode/cli on DiscoverableTeam

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: `TeamCloneService.clone` 接受覆盖参数

**Files:**
- Modify: `client/lib/services/team/team_clone_service.dart`（`clone` 方法）
- Test: `client/test/services/team/team_clone_service_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `team.cli` / `team.teamMode`（生效 getter，不变）
- Produces: `Future<CloneResult> clone(DiscoverableTeam team, {void Function(CloneProgress)? onProgress, TeamMode? teamMode, CliTool? cli})`——`createTeam` 用 `teamMode ?? team.teamMode` / `cli ?? team.cli`。

- [ ] **Step 1: 写失败测试**

在 `client/test/services/team/team_clone_service_test.dart` 追加：

```dart
  test('explicit teamMode/cli overrides the manifest values', () async {
    TeamMode? createdMode;
    CliTool? createdCli;
    final service = TeamCloneService(
      installSkill: (d) async => 's',
      installPlugin: (d) async => 'p',
      installMcp: (d) async => 'm',
      expertCloner: ({required expertKey, originTeamKey}) async =>
          ExpertCloneOutcome(cloned: false),
      createTeam:
          ({
            required name,
            required cli,
            required teamMode,
            required roster,
            required skillIds,
            required pluginIds,
            required mcpServerIds,
            required description,
            required extraArgs,
            String? hubSourceKey,
          }) async {
            createdMode = teamMode;
            createdCli = cli;
            return 'squad';
          },
    );

    // team() 的 manifest 是 claude + mixed；覆盖成 codex + native 应优先。
    await service.clone(team(), teamMode: TeamMode.native, cli: CliTool.codex);
    expect(createdMode, TeamMode.native);
    expect(createdCli, CliTool.codex);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/services/team/team_clone_service_test.dart`
Expected: FAIL — `clone` 不接受命名参数 `teamMode`。

- [ ] **Step 3: 实现**

`client/lib/services/team/team_clone_service.dart` 的 `clone` 签名与 `createTeam` 调用改：

```dart
  Future<CloneResult> clone(
    DiscoverableTeam team, {
    void Function(CloneProgress)? onProgress,
    TeamMode? teamMode,
    CliTool? cli,
  }) async {
    // ...（依赖安装部分不变）...
    final teamId = await createTeam(
      name: team.name,
      cli: cli ?? team.cli,
      teamMode: teamMode ?? team.teamMode,
      roster: roster,
      skillIds: skillIds,
      pluginIds: pluginIds,
      mcpServerIds: mcpIds,
      description: team.description,
      extraArgs: team.extraArgs,
      hubSourceKey: team.key,
    );
```

文件顶部已 import `team_config.dart`（含 `TeamMode` / `CliTool`），无需新增 import。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && flutter test test/services/team/team_clone_service_test.dart`
Expected: PASS（原有用例不传覆盖参数，行为不变）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team/team_clone_service.dart client/test/services/team/team_clone_service_test.dart
git commit -m "feat(team-hub): allow clone-time teamMode/cli override in TeamCloneService

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: `TeamLandingSelection` 透传覆盖参数

**Files:**
- Modify: `client/lib/services/team/team_landing_selection.dart`（`cloneTeam` typedef、`TeamLandingSelection` 构造、`resolveHub`）
- Test: `client/test/services/team/team_landing_selection_test.dart`

**Interfaces:**
- Consumes: Task 2 的覆盖参数概念
- Produces:
  - typedef `TeamLandingCloner = Future<CloneResult> Function(DiscoverableTeam team, {TeamMode? teamMode, CliTool? cli})`（本文件内的 `cloneTeam` 回调类型）
  - `Future<TeamLandingResolveSuccess> resolveHub({required DiscoverableTeam team, required List<TeamProfile> teams, TeamMode? teamMode, CliTool? cli})`

- [ ] **Step 1: 写失败测试**

在 `client/test/services/team/team_landing_selection_test.dart` 追加：

```dart
  test('resolveHub forwards teamMode/cli overrides to the cloner', () async {
    TeamMode? seenMode;
    CliTool? seenCli;
    final selection = TeamLandingSelection(
      cloneTeam: (t, {teamMode, cli}) async {
        seenMode = teamMode;
        seenCli = cli;
        return const CloneResult(
          teamId: 'cloned',
          installed: CloneDepInstallSummary(),
          failedDeps: [],
        );
      },
      touchRecent: (_) async {},
    );
    await selection.resolveHub(
      team: hub('o/r/s'),
      teams: const [],
      teamMode: TeamMode.mixed,
      cli: CliTool.opencode,
    );
    expect(seenMode, TeamMode.mixed);
    expect(seenCli, CliTool.opencode);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/services/team/team_landing_selection_test.dart`
Expected: FAIL — `resolveHub` 不接受 `teamMode` / `cli` 命名参数。

- [ ] **Step 3: 实现**

`client/lib/services/team/team_landing_selection.dart`：

`cloneTeam` 回调 typedef（文件里 `TeamLandingSelection` 构造参数上）改为：

```dart
typedef TeamLandingCloner = Future<CloneResult> Function(
  DiscoverableTeam team, {
  TeamMode? teamMode,
  CliTool? cli,
});
```

`TeamLandingSelection` 构造参数 `cloneTeam` 类型用 `TeamLandingCloner`，字段类型同步。`resolveHub` 签名与 `_cloneTeam` 调用改：

```dart
  Future<TeamLandingResolveSuccess> resolveHub({
    required DiscoverableTeam team,
    required List<TeamProfile> teams,
    TeamMode? teamMode,
    CliTool? cli,
  }) async {
    final existing = earliestTeamWithHubSourceKey(teams, team.key);
    if (existing != null) {
      await _touchRecent(existing.id);
      return TeamLandingResolveSuccess(teamId: existing.id);
    }

    try {
      final result = await _cloneTeam(team, teamMode: teamMode, cli: cli);
      await _touchRecent(result.teamId);
      return TeamLandingResolveSuccess(
        teamId: result.teamId,
        cloneResult: result,
      );
    } on CloneException catch (e) {
      throw TeamLandingSelectionException(e.message);
    }
  }
```

顶部已 import `team_config.dart`。注意：`cloneTeam: (_) async => ...` 这类单参数 lambda 仍满足新 typedef（多出的可选命名参数是子类型，无需改现有测试）。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && flutter test test/services/team/team_landing_selection_test.dart`
Expected: PASS（原有用例无需改动）。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team/team_landing_selection.dart client/test/services/team/team_landing_selection_test.dart
git commit -m "feat(team-hub): pass teamMode/cli overrides through TeamLandingSelection

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: `TeamHubCubit.clone` + `TeamCloner` typedef + app_shell 接线

**Files:**
- Modify: `client/lib/cubits/team_hub_cubit.dart`（`TeamCloner` typedef + `clone`）
- Modify: `client/lib/app/app_shell.dart:1004`（`cloneTeam` 接线）
- Test: `client/test/cubits/team_hub_cubit_test.dart`

**Interfaces:**
- Consumes: Task 2 的 `TeamCloneService.clone(team, {teamMode, cli})`
- Produces:
  - `typedef TeamCloner = Future<CloneResult> Function(DiscoverableTeam team, {TeamMode? teamMode, CliTool? cli})`
  - `Future<CloneResult> clone(DiscoverableTeam team, {TeamMode? teamMode, CliTool? cli})`

- [ ] **Step 1: 写失败测试**

在 `client/test/cubits/team_hub_cubit_test.dart` 追加（`setUp` 里已有 `cubit`；这里新建一个能捕获参数的 cubit）：

```dart
  test('clone forwards teamMode/cli overrides to the cloner', () async {
    TeamMode? seenMode;
    CliTool? seenCli;
    final spy = TeamHubCubit(
      source: source,
      loadFavorites: () async => const {},
      saveFavoriteToggle: (_) async => true,
      cloneTeam: (team, {teamMode, cli}) async {
        seenMode = teamMode;
        seenCli = cli;
        return const CloneResult(
          teamId: 'new-id',
          installed: CloneDepInstallSummary(),
          failedDeps: [],
        );
      },
    );
    addTearDown(spy.close);

    await spy.clone(_t('A', 'AI', 1), teamMode: TeamMode.native, cli: CliTool.cursor);
    expect(seenMode, TeamMode.native);
    expect(seenCli, CliTool.cursor);
  });
```

测试顶部已 import `team_config.dart`（`TeamMode` / `CliTool`）。

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/cubits/team_hub_cubit_test.dart`
Expected: FAIL — `clone` 不接受 `teamMode` / `cli` 命名参数。

- [ ] **Step 3: 实现**

`client/lib/cubits/team_hub_cubit.dart`：

typedef（第 14 行）改为：

```dart
typedef TeamCloner = Future<CloneResult> Function(
  DiscoverableTeam team, {
  TeamMode? teamMode,
  CliTool? cli,
});
```

`clone` 方法改为：

```dart
  Future<CloneResult> clone(
    DiscoverableTeam team, {
    TeamMode? teamMode,
    CliTool? cli,
  }) async {
    emit(state.copyWith(cloningKeys: {...state.cloningKeys, team.key}));
    try {
      final result = await _cloneTeam(team, teamMode: teamMode, cli: cli);
      final installed =
          await _loadInstalledDepIds?.call() ?? state.installedDepIds;
      emit(state.copyWith(installedDepIds: installed));
      return result;
    } finally {
      emit(
        state.copyWith(cloningKeys: {...state.cloningKeys}..remove(team.key)),
      );
    }
  }
```

文件顶部已 import `team_config.dart`。

`client/lib/app/app_shell.dart` 第 ~1004 行 `cloneTeam` 接线改为：

```dart
    cloneTeam: (team, {teamMode, cli}) => hubCloneActivityAdapter.runTracked(
      title: 'Clone ${team.name}',
      historyMessageFor: (result) => result.hasFailures
          ? 'Cloned ${team.name} with ${result.failedDeps.length} dependency failures'
          : 'Cloned ${team.name}',
      run: (onProgress) => teamCloneService.clone(
        team,
        teamMode: teamMode,
        cli: cli,
        onProgress: onProgress,
      ),
    ),
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && flutter test test/cubits/team_hub_cubit_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/team_hub_cubit.dart client/lib/app/app_shell.dart client/test/cubits/team_hub_cubit_test.dart
git commit -m "feat(team-hub): thread teamMode/cli overrides through TeamHubCubit

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: 克隆选项对话框组件（含 l10n）

**Files:**
- Create: `client/lib/pages/team_hub/team_hub_clone_options_dialog.dart`
- Modify: `client/lib/l10n/app_en.arb`、`client/lib/l10n/app_zh.arb`（新增 key；运行 gen-l10n 重新生成 `app_localizations*.dart`）
- Test: `client/test/pages/team_hub/team_hub_clone_options_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `teamModeDeclared` / `cliDeclared` / `teamMode` / `cli`
- Produces:
  - `class TeamHubCloneOptions { final TeamMode teamMode; final CliTool cli; }`
  - `Future<TeamHubCloneOptions?> resolveTeamHubCloneOptions(BuildContext context, DiscoverableTeam team)`——两字段都声明时直接返回生效值；否则弹 `TeamHubCloneOptionsDialog`，取消返回 `null`
  - `class TeamHubCloneOptionsDialog extends StatefulWidget`（`required DiscoverableTeam team`）

- [ ] **Step 1: 加 l10n key 并重新生成**

`client/lib/l10n/app_en.arb` 新增：

```json
  "teamHubCloneOptionsTitle": "Clone options",
```

`client/lib/l10n/app_zh.arb` 新增：

```json
  "teamHubCloneOptionsTitle": "克隆选项",
```

重新生成本地化（`client/` 下）：`flutter pub get` 或 `flutter gen-l10n`。提交生成的 `app_localizations*.dart`。

- [ ] **Step 2: 写失败测试**

创建 `client/test/pages/team_hub/team_hub_clone_options_dialog_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/team_hub/team_hub_clone_options_dialog.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';

DiscoverableTeam _undeclared() => const DiscoverableTeam(
  key: 'o/r/s',
  name: 'S',
  description: '',
  category: 'AI',
  updatedAt: 1,
);

DiscoverableTeam _declared() => const DiscoverableTeam(
  key: 'o/r/s',
  name: 'S',
  description: '',
  category: 'AI',
  updatedAt: 1,
  cli: CliTool.codex,
  teamMode: TeamMode.mixed,
);

Future<void> _pumpHost(
  WidgetTester tester, {
  required Widget home,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    CliToolRegistryScope(
      registry: CliToolRegistry.builtIn(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'resolveTeamHubCloneOptions returns effective values without dialog '
    'when both fields are declared',
    (tester) async {
      TeamHubCloneOptions? result;
      await _pumpHost(
        tester,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await resolveTeamHubCloneOptions(context, _declared());
            },
            child: const Text('go'),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(result, isNotNull);
      expect(result!.teamMode, TeamMode.mixed);
      expect(result!.cli, CliTool.codex);
      expect(find.text('Clone options'), findsNothing);
    },
  );

  testWidgets('dialog confirm returns selected mode and cli', (tester) async {
    TeamHubCloneOptions? result;
    await _pumpHost(
      tester,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await resolveTeamHubCloneOptions(context, _undeclared());
          },
          child: const Text('go'),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Team mode'), findsOneWidget);
    expect(find.text('CLI backend'), findsOneWidget);

    await tester.tap(find.text('Mixed (cross-CLI bus)'));
    await tester.pump();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.teamMode, TeamMode.mixed);
    expect(result!.cli, CliTool.claude);
  });

  testWidgets('dialog cancel returns null', (tester) async {
    TeamHubCloneOptions? result;
    await _pumpHost(
      tester,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await resolveTeamHubCloneOptions(context, _undeclared());
          },
          child: const Text('go'),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
```

- [ ] **Step 3: 跑测试确认失败**

Run: `cd client && flutter test test/pages/team_hub/team_hub_clone_options_dialog_test.dart`
Expected: FAIL — 找不到 `team_hub_clone_options_dialog.dart`。

- [ ] **Step 4: 实现对话框**

创建 `client/lib/pages/team_hub/team_hub_clone_options_dialog.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/discoverable_team.dart';
import '../../../models/team_config.dart';
import '../../../services/cli/registry/cli_display_name.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../widgets/app_provider/brand_dropdown_rows.dart';

/// Clone-time launch params resolved for a hub team whose manifest omitted them.
class TeamHubCloneOptions {
  const TeamHubCloneOptions({required this.teamMode, required this.cli});

  final TeamMode teamMode;
  final CliTool cli;
}

/// Resolves the effective teamMode/cli for cloning [team].
///
/// Returns immediately when both fields are declared in the manifest. Otherwise
/// shows [TeamHubCloneOptionsDialog] for the undeclared fields and returns the
/// user's picks — or `null` if the user cancelled.
Future<TeamHubCloneOptions?> resolveTeamHubCloneOptions(
  BuildContext context,
  DiscoverableTeam team,
) async {
  if (team.teamModeDeclared && team.cliDeclared) {
    return TeamHubCloneOptions(teamMode: team.teamMode, cli: team.cli);
  }
  return showTpDialog<TeamHubCloneOptions>(
    context: context,
    maxWidth: 520,
    builder: (_) => TeamHubCloneOptionsDialog(team: team),
  );
}

class TeamHubCloneOptionsDialog extends StatefulWidget {
  const TeamHubCloneOptionsDialog({required this.team, super.key});

  final DiscoverableTeam team;

  @override
  State<TeamHubCloneOptionsDialog> createState() =>
      _TeamHubCloneOptionsDialogState();
}

class _TeamHubCloneOptionsDialogState extends State<TeamHubCloneOptionsDialog> {
  late TeamMode _mode;
  late CliTool _cli;

  @override
  void initState() {
    super.initState();
    _mode = widget.team.teamMode;
    _cli = widget.team.cli;
  }

  void _confirm() => Navigator.of(context).pop(
    TeamHubCloneOptions(teamMode: _mode, cli: _cli),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final team = widget.team;
    final registry = CliToolRegistryScope.of(context);
    final clis = registry.nativeTeamLaunchable.toList()
      ..sort((a, b) => a.id.value.compareTo(b.id.value));

    return TpDialog(
      maxWidth: 520,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpDialogHeader(title: l10n.teamHubCloneOptionsTitle),
          const SizedBox(height: 12),
          if (!team.teamModeDeclared) ...[
            _SectionLabel(title: l10n.teamModeLabel),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _OptionCard(
                    title: l10n.teamModeNative,
                    description: l10n.teamModeNativeDescription,
                    selected: _mode == TeamMode.native,
                    onTap: () => setState(() => _mode = TeamMode.native),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OptionCard(
                    title: l10n.teamModeMixed,
                    description: l10n.teamModeMixedDescription,
                    selected: _mode == TeamMode.mixed,
                    onTap: () => setState(() => _mode = TeamMode.mixed),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (!team.cliDeclared) ...[
            _SectionLabel(title: l10n.teamCliLabel),
            const SizedBox(height: 8),
            TpCompactSelect<CliTool>(
              value: _cli,
              entries: [
                for (final def in clis) (def.id, cliDisplayName(def, l10n)),
              ],
              itemBuilder: cliDropdownItemBuilder(
                registry: registry,
                l10n: l10n,
              ),
              onChanged: (value) {
                if (value != null) setState(() => _cli = value);
              },
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: TpButton(
                  variant: TpButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TpButton(
                  variant: TpButtonVariant.primary,
                  onPressed: _confirm,
                  child: Text(l10n.confirm),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      title,
      style: TpTextStyles.of(context).mdBoldColored(cs.onSurface),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return TpHover(
      onTap: onTap,
      width: double.infinity,
      borderRadius: BorderRadius.circular(10),
      backgroundColor: selected
          ? cs.primary.withValues(alpha: 0.07)
          : cs.surfaceContainerHighest.withValues(alpha: 0.35),
      border: Border.all(
        color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.6),
        width: selected ? 2 : 1,
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 20,
            color: selected ? cs.primary : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: styles.mdBoldColored(cs.onSurface)),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: styles.smColored(cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `cd client && flutter test test/pages/team_hub/team_hub_clone_options_dialog_test.dart`
Expected: PASS。

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/team_hub/team_hub_clone_options_dialog.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations*.dart client/test/pages/team_hub/team_hub_clone_options_dialog_test.dart
git commit -m "feat(team-hub): clone-options dialog for undeclared teamMode/cli

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: 团队中心页 Clone 入口接线

**Files:**
- Modify: `client/lib/pages/team_hub/team_hub_page.dart`（`_clone`）

**Interfaces:**
- Consumes: Task 4 的 `cubit.clone(team, {teamMode, cli})`；Task 5 的 `resolveTeamHubCloneOptions`
- Produces: `_clone` 在克隆前对未声明字段弹框，取消中止

- [ ] **Step 1: 实现**

`client/lib/pages/team_hub/team_hub_page.dart`：
- 顶部加 `import 'team_hub_clone_options_dialog.dart';`
- `_clone` 改为：

```dart
  Future<void> _clone(TeamHubCubit cubit, DiscoverableTeam team) async {
    final l10n = context.l10n;
    try {
      final options = await resolveTeamHubCloneOptions(context, team);
      if (options == null || !mounted) return; // 取消或页面已销毁
      final result = await cubit.clone(
        team,
        teamMode: options.teamMode,
        cli: options.cli,
      );
      if (!mounted) return;
      setState(() => _detail = null);
      AppToast.show(
        context,
        message: teamHubCloneToastMessage(
          l10n,
          teamName: team.name,
          result: result,
        ),
        variant: teamHubCloneToastIsWarning(result)
            ? TpToastVariant.warning
            : TpToastVariant.success,
      );
    } on CloneException {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.teamHubCloneFailed,
        variant: TpToastVariant.error,
      );
    }
  }
```

- [ ] **Step 2: 静态验证**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: 无 error / warning。

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/team_hub/team_hub_page.dart
git commit -m "feat(team-hub): prompt clone options on Team Hub page clone

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 7: 落地选择器 Confirm 入口接线

**Files:**
- Modify: `client/lib/pages/team_hub/team_landing_picker_sheet.dart`（`_selection` getter、`_confirmHub`）
- Test: `client/test/pages/team_hub/team_landing_picker_confirm_test.dart`

**Interfaces:**
- Consumes: Task 3 的 `resolveHub(team, teams, {teamMode, cli})`；Task 5 的 `resolveTeamHubCloneOptions`
- Produces: `_confirmHub` 在确认前对未声明字段弹框，取消恢复 `_confirming = false`

- [ ] **Step 1: 写失败测试**

创建 `client/test/pages/team_hub/team_landing_picker_confirm_test.dart`，参照 `client/test/pages/expert_hub/expert_landing_picker_dialog_test.dart` 的 pump 模式 + `post_frame_test_harness.dart` 的存储 helper：

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/team_hub_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/pages/team_hub/team_landing_picker_sheet.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/team/team_clone_service.dart';
import 'package:teampilot/services/team_hub/team_hub_source.dart';

import '../../support/post_frame_test_harness.dart';

class _FakeSource implements TeamHubSource {
  _FakeSource(this.teams);
  final List<DiscoverableTeam> teams;

  @override
  Future<List<DiscoverableTeam>> fetchTeams({bool forceRefresh = false}) async =>
      teams;

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async =>
      teams.map((t) => t.category).toSet().toList()..sort();
}

DiscoverableTeam _hubTeam() => const DiscoverableTeam(
  key: 'o/r/s',
  name: 'Squad',
  description: 'd',
  category: 'AI',
  updatedAt: 1,
);

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<TeamHubCubit> pumpCubit() async {
    final cubit = TeamHubCubit(
      source: _FakeSource([_hubTeam()]),
      loadFavorites: () async => const {},
      saveFavoriteToggle: (_) async => true,
      cloneTeam: (team, {teamMode, cli}) async {
        return CloneResult(
          teamId: 'cloned-${team.key}',
          installed: const CloneDepInstallSummary(),
          failedDeps: const [],
        );
      },
    );
    await cubit.load();
    return cubit;
  }

  Future<LaunchProfileCubit> pumpLaunch() async {
    final dir = await Directory.systemTemp.createTemp('team-picker-');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException catch (_) {}
    });
    return LaunchProfileCubit(
      repository: testLaunchProfileRepository(dir),
      sessionRepository: SessionRepository(),
      executableResolver: () => 'claude',
    );
  }

  Future<void> pumpHost(
    WidgetTester tester, {
    required TeamHubCubit cubit,
    required LaunchProfileCubit launch,
    required Widget home,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: cubit),
            BlocProvider.value(value: launch),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: home,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('confirm on undeclared team shows clone-options dialog first',
      (tester) async {
    final cubit = await pumpCubit();
    addTearDown(cubit.close);
    final launch = await pumpLaunch();
    addTearDown(launch.close);

    String? pickedTeamId;
    await pumpHost(
      tester,
      cubit: cubit,
      launch: launch,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            pickedTeamId = await showTeamLandingPickerSheet(context);
          },
          child: const Text('open'),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // 进 catalog，点 Squad 卡片 → 详情
    await tester.tap(find.text('Squad'));
    await tester.pumpAndSettle();
    // 详情里点 Confirm → 应弹克隆选项对话框（teamMode 未声明）
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(find.text('Clone options'), findsOneWidget);

    // 取消 → 不克隆，picker 保持打开，pickedTeamId 为 null
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(pickedTeamId, isNull);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/pages/team_hub/team_landing_picker_confirm_test.dart`
Expected: FAIL（`_confirmHub` 尚未接线，点 Confirm 直接克隆、不弹 `Clone options` 对话框）。

- [ ] **Step 3: 实现**

`client/lib/pages/team_hub/team_landing_picker_sheet.dart`：
- 顶部加 `import 'team_hub_clone_options_dialog.dart';`
- `_selection` getter 改（把覆盖透传给 `cubit.clone`）：

```dart
  TeamLandingSelection get _selection => TeamLandingSelection(
    cloneTeam: (team, {teamMode, cli}) =>
        context.read<TeamHubCubit>().clone(team, teamMode: teamMode, cli: cli),
    touchRecent: widget.touchRecent ?? TeamLandingRecentStore().touch,
  );
```

- `_confirmHub` 开头改为（弹框补选，取消恢复并中止）：

```dart
  Future<void> _confirmHub(DiscoverableTeam team) async {
    if (_confirming) return;
    setState(() => _confirming = true);
    final l10n = context.l10n;
    try {
      final options = await resolveTeamHubCloneOptions(context, team);
      if (options == null) {
        if (!mounted) return;
        setState(() => _confirming = false);
        return; // 用户取消：不克隆
      }
      final teams = context.read<LaunchProfileCubit>().state.teams;
      final result = await _selection.resolveHub(
        team: team,
        teams: teams,
        teamMode: options.teamMode,
        cli: options.cli,
      );
      if (!mounted) return;
      final clone = result.cloneResult;
      if (clone != null) {
        AppToast.show(
          context,
          message: teamHubCloneToastMessage(
            l10n,
            teamName: team.name,
            result: clone,
          ),
          variant: teamHubCloneToastIsWarning(clone)
              ? TpToastVariant.warning
              : TpToastVariant.success,
        );
      }
      Navigator.of(context).pop(result.teamId);
    } on TeamLandingSelectionException {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.teamHubCloneFailed,
        variant: TpToastVariant.error,
      );
      setState(() => _confirming = false);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.teamHubCloneFailed,
        variant: TpToastVariant.error,
      );
      setState(() => _confirming = false);
    }
  }
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && flutter test test/pages/team_hub/team_landing_picker_confirm_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/pages/team_hub/team_landing_picker_sheet.dart client/test/pages/team_hub/team_landing_picker_confirm_test.dart
git commit -m "feat(team-hub): prompt clone options in landing picker confirm

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 8: 内置模板补 cli 声明

**Files:**
- Modify: `client/lib/services/team_hub/builtin_team_templates.dart`（`kSuperpowersTrioTeamTemplate`）
- Test: `client/test/services/team_hub/builtin_team_templates_test.dart`

**Interfaces:**
- Produces: `kSuperpowersTrioTeamTemplate.cliDeclared == true` 且 `cli == CliTool.claude`

- [ ] **Step 1: 写失败测试**

在 `client/test/services/team_hub/builtin_team_templates_test.dart` 追加：

```dart
  test('superpowers quartet declares claude as its base CLI', () {
    expect(kSuperpowersTrioTeamTemplate.cliDeclared, isTrue);
    expect(kSuperpowersTrioTeamTemplate.cli, CliTool.claude);
    expect(kSuperpowersTrioTeamTemplate.teamModeDeclared, isTrue);
    expect(kSuperpowersTrioTeamTemplate.teamMode, TeamMode.mixed);
  });
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/services/team_hub/builtin_team_templates_test.dart`
Expected: FAIL — `cliDeclared` 为 false。

- [ ] **Step 3: 实现**

`builtin_team_templates.dart` 的 `kSuperpowersTrioTeamTemplate` 构造参数加 `cli: CliTool.claude,`（已有 `teamMode: TeamMode.mixed`）。文件已 import `team_config.dart`。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && flutter test test/services/team_hub/builtin_team_templates_test.dart`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/team_hub/builtin_team_templates.dart client/test/services/team_hub/builtin_team_templates_test.dart
git commit -m "feat(team-hub): declare base CLI on Superpowers builtin template

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 9: 全量验证

**Files:**（无代码改动）

- [ ] **Step 1: 分析 + 全量测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: 全绿。

- [ ] **Step 2: 人工冒烟（可选）**

Run 应用，进入 团队中心 → 克隆 `gstack-req-dev`（team.json 未写 cli，写了 teamMode）→ 应只弹 CLI 选择；克隆一个 `teamMode`/`cli` 都没写的团队 → 弹两个选择；全部声明的团队 → 不弹。

- [ ] **Step 3: 收尾说明**

把本计划所有任务勾选为完成，向用户汇报最终变更与验证结果。
