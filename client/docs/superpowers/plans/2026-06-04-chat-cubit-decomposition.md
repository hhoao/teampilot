# ChatCubit 拆分重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 1883 行的 `chat_cubit.dart` 拆成「唯一持有并 emit `ChatState` 的编排器 + 各自内聚的协作者 + 一个独立的存活 Cubit」，每个文件落在 500 行软上限内，且行为零回归。

**Architecture:** `ChatCubit` 退化为编排器（DI 装配 + 连接流 + 门面 + getter），唯一调用 `emit`；A 会话工厂、B Tab 仓储、C 数据仓储、E Team Bus 三大域下沉为**不 emit、返回结果**的协作者对象；D 连接状态机用 **mixin** 留在 cubit（本质就是对 `ChatState` 的 emit 编排）；F 成员存活升级为**独立 `MemberPresenceCubit`**（真解耦、仅 2 个 widget 消费）。`memberPresence` 字段从 `ChatState` 移除。

**Tech Stack:** Dart / Flutter，`flutter_bloc`（Cubit），`equatable`，`flutter_test` + `fake_async`。验证命令：`flutter analyze --no-fatal-infos --no-fatal-warnings` 与 `flutter test --exclude-tags integration`（在 `client/` 下运行）。

**全部路径以 `client/` 为根。** 重构的 TDD 纪律：**每一步先保证既有测试全绿**（它们就是回归网），新可纯测的协作者再补单测。每个 Task 结束必须 `flutter analyze` + 相关 `flutter test` 通过后才 commit。

---

## File Structure（拆分后的文件职责）

| 文件 | 职责 | 来源 |
|------|------|------|
| `lib/cubits/chat/model/chat_tab_info.dart` | `ChatTabInfo`（UI 面向，进 `ChatState`） | 现 56–91 行 |
| `lib/cubits/chat/model/chat_tab.dart` | `ChatTab`（`_InternalTab` 改公开，协作者共享的 per-tab 运行时聚合） | 现 93–134 行 |
| `lib/cubits/chat/model/chat_state.dart` | `ChatState` + typedefs（**删 `memberPresence`**） | 现 39–54、136–252 行 |
| `lib/cubits/chat/chat_session_shell_factory.dart` | A：`TerminalSession` 工厂 + CLI/ssh 解析 | 现 324–387、315–322、335 行 |
| `lib/cubits/chat/chat_tab_store.dart` | B：独占 `List<ChatTab>`，查/改/派生 infos | 现 288、440–451、991–996、816–825、766–832 部分等 |
| `lib/cubits/chat/session_data_store.dart` | C：独占 scoping，封 `SessionRepository`，返回 `ChatDataSnapshot` | 现 297–298、411–438、472–555、1648–1662 |
| `lib/cubits/chat/tab_team_bus_coordinator.dart` | E：独占 bus/mcp/idle-watch，实现 `MemberMaterializer` | 现 313、887–899、998–1040、1362–1394、1849–1864 |
| `lib/cubits/chat/chat_connect_state_mixin.dart` | D：连接状态机（mixin on `ChatCubit`） | 现 1678–1762、1834–1847、1546–1553 |
| `lib/cubits/member_presence_cubit.dart` | F：独立 Cubit + `MemberPresenceState` + `PresenceTarget` | 现 289–294、1220–1360 |
| `lib/cubits/chat_cubit.dart` | 编排器：DI + 连接流 + 门面 + getter + `close()` | 其余 |

新增测试：`test/cubits/member_presence_cubit_test.dart`、`test/cubits/chat/chat_tab_store_test.dart`、`test/cubits/chat/session_data_store_test.dart`、`test/cubits/chat/chat_session_shell_factory_test.dart`。

> **导入路径注意**：`chat_cubit.dart` 从 `lib/cubits/` 移动其内部类到 `lib/cubits/chat/`，新文件相对 `lib/models/...` 的导入要写成 `../../models/...`（多一层）。`chat_cubit.dart` 自身不移动，仍在 `lib/cubits/`，对外导入路径不变，所以 **18 个消费文件的 `import '../cubits/chat_cubit.dart'` 全部不动**。`chat_cubit.dart` 用 `export 'chat/model/chat_state.dart';` 等重导出，让消费方继续从 `chat_cubit.dart` 拿到 `ChatState`/`ChatTabInfo`。

---

## Task 1: 抽出模型层（ChatTabInfo / ChatTab / ChatState）

纯搬移，零逻辑变更。先建立可被协作者共享的模型基座。

**Files:**
- Create: `lib/cubits/chat/model/chat_tab_info.dart`
- Create: `lib/cubits/chat/model/chat_tab.dart`
- Create: `lib/cubits/chat/model/chat_state.dart`
- Modify: `lib/cubits/chat_cubit.dart`（删除内联类，改为 import + export，`_InternalTab`→`ChatTab` 全量改名）

- [ ] **Step 1: 先跑基线，确认起点全绿**

Run: `cd client && flutter test test/cubits/chat_cubit_test.dart test/cubits/chat_cubit_presence_test.dart test/cubits/chat_cubit_team_bus_test.dart`
Expected: PASS（记录通过用例数，作为后续每步的回归基线）

- [ ] **Step 2: 创建 `chat_tab_info.dart`**（搬现 56–91 行，原样）

```dart
import 'package:equatable/equatable.dart';

class ChatTabInfo extends Equatable {
  const ChatTabInfo({
    required this.id,
    required this.title,
    required this.subtitle,
    this.isRunning = false,
    this.launchError,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool isRunning;

  /// User-facing summary when the last connect attempt failed (placeholder P0).
  final String? launchError;

  ChatTabInfo copyWith({
    String? title,
    String? subtitle,
    bool? isRunning,
    String? launchError,
    bool clearLaunchError = false,
  }) {
    return ChatTabInfo(
      id: id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      isRunning: isRunning ?? this.isRunning,
      launchError: clearLaunchError ? null : (launchError ?? this.launchError),
    );
  }

  @override
  List<Object?> get props => [id, title, subtitle, isRunning, launchError];
}
```

- [ ] **Step 3: 创建 `chat_tab.dart`**（搬现 93–134 行，`_InternalTab`→`ChatTab`，补导入）

```dart
import 'dart:async';

import '../../../models/app_session.dart';
import '../../../services/team_bus/mcp/teammate_bus_mcp_server.dart';
import '../../../services/team_bus/team_bus.dart';
import '../../../services/terminal/terminal_session.dart';
import 'chat_tab_info.dart';

/// Per-tab runtime aggregate shared by ChatCubit and its collaborators.
/// (Formerly the private `_InternalTab`.)
class ChatTab {
  ChatTab({
    required this.info,
    required this.cliTeamName,
    this.selectedMemberId = '',
  });

  ChatTabInfo info;
  TerminalSession? resumeSession;
  String selectedMemberId;

  /// CLI `--team-name` and config-profiles runtime id ([AppSession.cliTeamName]).
  final String cliTeamName;

  /// Persisted session for team member connect (may be absent before index load).
  AppSession? persistedSession;

  /// Shared [LaunchPlan.memberConfigDir] from first successful member connect.
  String? memberToolConfigDir;

  final Map<String, TerminalSession> memberShells = {};

  /// mixed 模式：本 team 会话的进程内总线与其 loopback MCP server（随 tab 建/销）。
  TeamBus? teamBus;
  TeammateBusMcpServer? mcpServer;

  Future<void> disposeBus() async {
    await mcpServer?.stop();
    teamBus = null;
    mcpServer = null;
  }

  /// Member ids with a scheduled or in-flight member connect.
  final Set<String> membersPendingConnect = {};

  Iterable<TerminalSession> get sessions sync* {
    if (resumeSession != null) yield resumeSession!;
    yield* memberShells.values;
  }

  bool get isRunning => sessions.any((session) => session.isRunning);
}
```

- [ ] **Step 4: 创建 `chat_state.dart`**（搬 typedefs 39–54 + `ChatState` 136–252，原样，导入指向新模型）

```dart
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';

import '../../../models/app_project.dart';
import '../../../models/app_session.dart';
import '../../../models/member_presence.dart';
import '../../../models/team_config.dart';
import '../../../services/terminal/terminal_session.dart';
import 'chat_tab_info.dart';

typedef TerminalSessionFactory =
    TerminalSession Function({required String executable, int scrollbackLines});

TerminalSession defaultTerminalSessionFactory({
  required String executable,
  int scrollbackLines = 10000,
}) {
  return TerminalSession(
    executable: executable,
    scrollbackLines: scrollbackLines,
  );
}

typedef PostFrameScheduler = void Function(VoidCallback callback);
typedef SshActiveProfileResolver = SshProfile? Function();
typedef CliExecutableResolver = String Function(TeamCli cli);

class ChatState extends Equatable {
  // ... 原 136–252 行整体搬入，但移除 memberPresence（见下一步）
}
```

> 注意：`SshActiveProfileResolver` 依赖 `SshProfile`，补 `import '../../../models/ssh_profile.dart';`。本步**先保留** `memberPresence` 字段，确保编译；它在 Task 4 才移除。把现 136–252 行整体复制进来。

- [ ] **Step 5: 改 `chat_cubit.dart`：删内联类，import + export，改名**

删除 `chat_cubit.dart` 现 39–252 行（typedefs/`ChatTabInfo`/`_InternalTab`/`ChatState`），在 import 区加：

```dart
import 'chat/model/chat_state.dart';
import 'chat/model/chat_tab.dart';
import 'chat/model/chat_tab_info.dart';

export 'chat/model/chat_state.dart';
export 'chat/model/chat_tab_info.dart';
```

全文件把 `_InternalTab` 改名为 `ChatTab`（`final List<_InternalTab> _internalTabs` → `final List<ChatTab> _internalTabs`，所有 `_InternalTab` 引用同改）。

- [ ] **Step 6: analyze + 回归测试**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/cubits/chat_cubit.dart lib/cubits/chat/ && flutter test test/cubits/chat_cubit_test.dart test/cubits/chat_cubit_presence_test.dart test/cubits/chat_cubit_team_bus_test.dart`
Expected: analyze 无 error；测试 PASS（用例数与 Step 1 一致）

- [ ] **Step 7: Commit**

```bash
cd client && git add lib/cubits/chat_cubit.dart lib/cubits/chat/model/
git commit -m "refactor(chat): extract ChatState/ChatTab/ChatTabInfo models"
```

---

## Task 2: 抽出会话工厂 `ChatSessionShellFactory`

纯工厂，零状态回写，第一个可独立单测的协作者。

**Files:**
- Create: `lib/cubits/chat/chat_session_shell_factory.dart`
- Test: `test/cubits/chat/chat_session_shell_factory_test.dart`
- Modify: `lib/cubits/chat_cubit.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/cubits/chat/chat_session_shell_factory_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_session_shell_factory.dart';
import 'package:teampilot/models/connection_mode.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

void main() {
  test('newSession uses local factory when not in ssh mode', () {
    var seenExecutable = '';
    final factory = ChatSessionShellFactory(
      executableResolver: () => 'flashskyai',
      cliExecutableResolver: (cli) => 'exec-${cli.value}',
      terminalSessionFactory: ({required executable, scrollbackLines = 10000}) {
        seenExecutable = executable;
        return TerminalSession(executable: executable);
      },
      connectionModeResolver: () => ConnectionMode.localPty,
    );

    final session = factory.newSession(TeamCli.claude);

    expect(session, isA<TerminalSession>());
    expect(seenExecutable, 'exec-claude');
  });

  test('cliForMember resolves member-specific cli', () {
    final factory = ChatSessionShellFactory(
      executableResolver: () => 'flashskyai',
      terminalSessionFactory: ({required executable, scrollbackLines = 10000}) =>
          TerminalSession(executable: executable),
    );
    const team = TeamConfig(id: 't', name: 'T', members: []);

    expect(factory.cliForMember(team, 'missing'), team.cli);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/cubits/chat/chat_session_shell_factory_test.dart`
Expected: FAIL（`chat_session_shell_factory.dart` 不存在）

- [ ] **Step 3: 实现 `ChatSessionShellFactory`**（搬现 315–387 行逻辑）

```dart
import '../../models/connection_mode.dart';
import '../../models/launch_target.dart';
import '../../models/ssh_profile.dart';
import '../../models/team_config.dart';
import '../../services/terminal/terminal_session.dart';
import '../../services/terminal/terminal_transport_factory.dart';
import 'model/chat_state.dart';

/// Builds [TerminalSession]s with the right executable / transport for the
/// active connection mode. Pure factory — owns no ChatState.
class ChatSessionShellFactory {
  ChatSessionShellFactory({
    required String Function() executableResolver,
    CliExecutableResolver? cliExecutableResolver,
    TerminalSessionFactory terminalSessionFactory =
        defaultTerminalSessionFactory,
    TerminalTransportFactory? transportFactory,
    SshActiveProfileResolver? sshProfileResolver,
    String Function()? sshDefaultWorkingDirectoryResolver,
    bool Function()? sshUseLoginShellResolver,
    ConnectionMode Function()? connectionModeResolver,
    int Function()? terminalScrollbackLinesResolver,
  })  : _executableResolver = executableResolver,
        _cliExecutableResolver = cliExecutableResolver,
        _terminalSessionFactory = terminalSessionFactory,
        _transportFactory = transportFactory,
        _sshProfileResolver = sshProfileResolver,
        _sshDefaultWorkingDirectoryResolver = sshDefaultWorkingDirectoryResolver,
        _sshUseLoginShellResolver = sshUseLoginShellResolver,
        _connectionModeResolver = connectionModeResolver,
        _terminalScrollbackLinesResolver = terminalScrollbackLinesResolver;

  final String Function() _executableResolver;
  final CliExecutableResolver? _cliExecutableResolver;
  final TerminalSessionFactory _terminalSessionFactory;
  final TerminalTransportFactory? _transportFactory;
  final SshActiveProfileResolver? _sshProfileResolver;
  final String Function()? _sshDefaultWorkingDirectoryResolver;
  final bool Function()? _sshUseLoginShellResolver;
  final ConnectionMode Function()? _connectionModeResolver;
  final int Function()? _terminalScrollbackLinesResolver;

  ConnectionMode get _connectionMode =>
      _connectionModeResolver?.call() ?? ConnectionMode.localPty;

  bool get _useSsh =>
      _connectionMode == ConnectionMode.ssh &&
      _transportFactory != null &&
      _sshProfileResolver != null &&
      _sshProfileResolver!() != null;

  int get _scrollbackLines => _terminalScrollbackLinesResolver?.call() ?? 10000;

  String _resolveExecutableFor(TeamCli cli) =>
      _cliExecutableResolver?.call(cli) ?? _executableResolver();

  TeamCli cliForMember(TeamConfig team, String memberId) {
    for (final m in team.members) {
      if (m.id == memberId) return m.cliWithin(team);
    }
    return team.cli;
  }

  TerminalSession newSession([TeamCli cli = TeamCli.flashskyai]) {
    // ... 搬现 337–387 行函数体（_newSession），把内部对私有 resolver 的引用
    //     原样保留（它们现在是本类字段）。
    final executable = _resolveExecutableFor(cli);
    final scrollback = _scrollbackLines;
    if (_useSsh) {
      final profile = _sshProfileResolver?.call();
      if (profile == null) {
        return _terminalSessionFactory(
          executable: executable,
          scrollbackLines: scrollback,
        );
      }
      return TerminalSession(
        executable: executable,
        scrollbackLines: scrollback,
        validateLaunch: false,
        parseExecutable: false,
        transportStarter:
            (
              String executable, {
              required List<String> arguments,
              required String workingDirectory,
              required int columns,
              required int rows,
              Map<String, String>? environment,
            }) async {
              final remoteEnvironment = <String, String>{
                if (environment != null) ...environment,
              };
              final remoteWorkingDirectory = workingDirectory.isNotEmpty
                  ? workingDirectory
                  : (_sshDefaultWorkingDirectoryResolver?.call() ?? '');
              return _transportFactory!.startTransport(
                LaunchTarget.ssh(
                  sshProfileId: profile.id,
                  remoteExecutable: executable,
                  remoteWorkingDirectory: remoteWorkingDirectory,
                  remoteEnvironment: remoteEnvironment,
                  useLoginShell: _sshUseLoginShellResolver?.call() ?? false,
                ),
                arguments: arguments,
                columns: columns,
                rows: rows,
              );
            },
      );
    }
    return _terminalSessionFactory(
      executable: executable,
      scrollbackLines: scrollback,
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && flutter test test/cubits/chat/chat_session_shell_factory_test.dart`
Expected: PASS

- [ ] **Step 5: 在 `chat_cubit.dart` 接入工厂，删除原逻辑**

构造函数体内新增 `_shellFactory` 装配（用现有 ctor 参数透传）：

```dart
_shellFactory = ChatSessionShellFactory(
  executableResolver: executableResolver,
  cliExecutableResolver: cliExecutableResolver,
  terminalSessionFactory: terminalSessionFactory,
  transportFactory: transportFactory,
  sshProfileResolver: sshProfileResolver,
  sshDefaultWorkingDirectoryResolver: sshDefaultWorkingDirectoryResolver,
  sshUseLoginShellResolver: sshUseLoginShellResolver,
  connectionModeResolver: connectionModeResolver,
  terminalScrollbackLinesResolver: terminalScrollbackLinesResolver,
),
```

加字段 `final ChatSessionShellFactory _shellFactory;`，删除字段 `_terminalSessionFactory`/`_executableResolver`/`_cliExecutableResolver`/`_transportFactory`/`_sshProfileResolver`/`_sshDefaultWorkingDirectoryResolver`/`_sshUseLoginShellResolver`/`_connectionModeResolver`/`_terminalScrollbackLinesResolver`，删除方法 `_resolveExecutableFor`/`_cliForMember`/`_newSession`/`_scrollbackLines`/`_connectionMode`/`_useSsh`。

全文件替换调用：`_newSession(` → `_shellFactory.newSession(`；`_cliForMember(` → `_shellFactory.cliForMember(`。加 `import 'chat/chat_session_shell_factory.dart';`。

- [ ] **Step 6: analyze + 全量回归**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/cubits/ && flutter test test/cubits/`
Expected: analyze 无 error；测试 PASS

- [ ] **Step 7: Commit**

```bash
cd client && git add lib/cubits/chat_cubit.dart lib/cubits/chat/chat_session_shell_factory.dart test/cubits/chat/chat_session_shell_factory_test.dart
git commit -m "refactor(chat): extract ChatSessionShellFactory"
```

---

## Task 3: 抽出独立的 `MemberPresenceCubit`（收益最高）

把存活整域升级为独立 Cubit，从 `ChatState` 删 `memberPresence`，2 个 widget 改监听新 cubit。

**Files:**
- Create: `lib/cubits/member_presence_cubit.dart`
- Test: `test/cubits/member_presence_cubit_test.dart`（由 `chat_cubit_presence_test.dart` 改写）
- Modify: `lib/cubits/chat_cubit.dart`、`lib/cubits/chat/model/chat_state.dart`
- Modify: `lib/app/app_shell.dart`、`lib/main.dart`
- Modify: `lib/widgets/right_tools/right_tools_panel.dart`
- Delete: `test/cubits/chat_cubit_presence_test.dart`

- [ ] **Step 1: 创建 `member_presence_cubit.dart`**（搬现 289–294 字段 + 1220–1360 方法）

```dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/member_presence.dart';
import '../models/team_config.dart';
import '../services/team/member_presence_service.dart';
import '../services/terminal/terminal_session.dart';

/// Snapshot of the active tab the presence poller needs. Pushed by ChatCubit
/// whenever the active tab / its shells change. Decouples presence from tabs.
class PresenceTarget {
  const PresenceTarget({
    required this.cliTeamName,
    required this.memberToolConfigDir,
    required this.memberShells,
  });

  final String cliTeamName;
  final String? memberToolConfigDir;
  final Map<String, TerminalSession> memberShells;

  bool get eligible =>
      memberShells.isNotEmpty ||
      (memberToolConfigDir?.trim().isNotEmpty ?? false);
}

class MemberPresenceState extends Equatable {
  const MemberPresenceState({this.presence = const {}});

  final Map<String, MemberPresence> presence;

  MemberPresenceState copyWith({Map<String, MemberPresence>? presence}) =>
      MemberPresenceState(presence: presence ?? this.presence);

  @override
  List<Object?> get props => [presence];
}

class MemberPresenceCubit extends Cubit<MemberPresenceState> {
  MemberPresenceCubit({MemberPresenceService? memberPresenceService})
      : _memberPresenceService =
            memberPresenceService ?? MemberPresenceService(),
        super(const MemberPresenceState());

  final MemberPresenceService _memberPresenceService;
  Timer? _presencePollTimer;
  TeamConfig? _presenceTeam;
  PresenceTarget? _target;
  int _presencePollGeneration = 0;
  bool _presenceUiAttached = false;
  bool _presenceTickInFlight = false;

  MemberPresence memberPresenceFor(String memberId) =>
      state.presence[memberId] ?? const MemberPresence.offline();

  /// Pushed by ChatCubit when the active tab / shells change.
  void updateTarget(PresenceTarget? target) {
    _target = target;
    _schedulePresencePollingRestart();
  }

  // ====== 以下全部搬现 1224–1360 行，把对 `_activeTab` 的依赖替换为 `_target`，
  //         把 `_emitMemberPresence(next)` 改为对本 cubit state 的 emit。======

  void attachPresenceUi() {
    if (_presenceUiAttached) return;
    _presenceUiAttached = true;
    _schedulePresencePollingRestart();
  }

  void detachPresenceUi() {
    if (!_presenceUiAttached) return;
    _presenceUiAttached = false;
    _invalidatePresencePolls();
    if (state.presence.isNotEmpty) _emitMemberPresence(const {});
  }

  void stopPresencePolling() {
    _presenceTeam = null;
    _presenceUiAttached = false;
    _invalidatePresencePolls();
    if (state.presence.isNotEmpty) _emitMemberPresence(const {});
  }

  void _invalidatePresencePolls() {
    _presencePollGeneration++;
    _presencePollTimer?.cancel();
    _presencePollTimer = null;
  }

  void syncPresenceTeam(TeamConfig? team) {
    if (_samePresenceTeam(_presenceTeam, team)) return;
    _presenceTeam = team;
    _schedulePresencePollingRestart();
  }

  void refreshPresencePolling() => _schedulePresencePollingRestart();

  void _schedulePresencePollingRestart() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (isClosed) return;
      _restartPresencePolling();
    });
  }

  void _emitMemberPresence(Map<String, MemberPresence> next) {
    if (isClosed || mapEquals(next, state.presence)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (isClosed || mapEquals(next, state.presence)) return;
      emit(state.copyWith(presence: next));
    });
  }

  bool _shouldPollPresence() {
    if (!_presenceUiAttached || _presenceTeam == null) return false;
    final target = _target;
    if (target == null) return false;
    return target.eligible;
  }

  static bool _samePresenceTeam(TeamConfig? a, TeamConfig? b) {
    if (a == null || b == null) return a == b;
    if (a.id != b.id || a.cli != b.cli) return false;
    if (a.members.length != b.members.length) return false;
    for (var i = 0; i < a.members.length; i++) {
      if (a.members[i].id != b.members[i].id) return false;
    }
    return true;
  }

  void _restartPresencePolling() {
    _presencePollTimer?.cancel();
    _presencePollTimer = null;
    final team = _presenceTeam;
    if (team == null || team.members.isEmpty) {
      if (state.presence.isNotEmpty) _emitMemberPresence(const {});
      return;
    }
    if (!_shouldPollPresence()) {
      if (state.presence.isNotEmpty) _emitMemberPresence(const {});
      return;
    }
    final generation = _presencePollGeneration;
    _presencePollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_tickMemberPresence(team, generation));
    });
    unawaited(_tickMemberPresence(team, generation));
  }

  Future<void> _tickMemberPresence(TeamConfig team, int generation) async {
    if (isClosed || generation != _presencePollGeneration) return;
    if (!_shouldPollPresence()) return;
    if (_presenceTickInFlight) return;
    final target = _target;
    if (target == null) return;

    _presenceTickInFlight = true;
    try {
      final next = await _memberPresenceService.compute(
        teamCli: team.cli,
        members: team.members,
        cliTeamName: target.cliTeamName,
        memberToolConfigDir: target.memberToolConfigDir,
        memberShells: target.memberShells,
      );
      if (isClosed ||
          generation != _presencePollGeneration ||
          !_shouldPollPresence()) {
        return;
      }
      _emitMemberPresence(next);
    } finally {
      _presenceTickInFlight = false;
    }
  }

  @override
  Future<void> close() async {
    _invalidatePresencePolls();
    await super.close();
  }
}
```

- [ ] **Step 2: 从 `ChatState` 移除 `memberPresence`**

在 `lib/cubits/chat/model/chat_state.dart` 删除：字段 `final Map<String, MemberPresence> memberPresence;`、构造参数 `this.memberPresence = const {}`、`copyWith` 的 `memberPresence` 参数与赋值、`props` 里的 `memberPresence`。删除现在无用的 `import '../../../models/member_presence.dart';`（若 `ChatState` 不再引用）。

- [ ] **Step 3: 从 `chat_cubit.dart` 删除存活逻辑，改为持有 presence cubit 引用并推送 target**

删除字段 `_memberPresenceService`/`_presencePollTimer`/`_presenceTeam`/`_presencePollGeneration`/`_presenceUiAttached`/`_presenceTickInFlight`；删除方法 `attachPresenceUi`/`detachPresenceUi`/`stopPresencePolling`/`_invalidatePresencePolls`/`syncPresenceTeam`/`refreshPresencePolling`/`_schedulePresencePollingRestart`/`_emitMemberPresence`/`_shouldPollPresence`/`_tabEligibleForPresencePoll`/`_samePresenceTeam`/`_restartPresencePolling`/`_tickMemberPresence`/`memberPresenceFor`；删除 ctor 参数 `memberPresenceService`。

新增字段与 setter：

```dart
MemberPresenceCubit? _presenceCubit;

/// Wired by app_shell after both cubits are constructed.
void bindPresenceCubit(MemberPresenceCubit cubit) => _presenceCubit = cubit;

void _pushPresenceTarget() {
  final cubit = _presenceCubit;
  if (cubit == null) return;
  final tab = _activeTab;
  cubit.updateTarget(
    tab == null
        ? null
        : PresenceTarget(
            cliTeamName: tab.cliTeamName,
            memberToolConfigDir: tab.memberToolConfigDir,
            memberShells: tab.memberShells,
          ),
  );
}
```

全文件把原 `refreshPresencePolling();` 调用点（现 611、1134、1158、1181、1194、1690 行）替换为 `_pushPresenceTarget();`，让 active-tab 变化时把新 target 推给 presence cubit。把现 610 行 `_presenceTeam = team;` 删除（presence team 由 right_tools_panel 经 `syncPresenceTeam` 驱动，保持原触发源）；其后 mixed 模式分支里对 `_presenceTeam` 的读取改为方法参数 `team`（现 1005 行 `materializeMember` 的 `_presenceTeam` 在 Task 5 处理，本步先在 cubit 内保留一个 `TeamConfig? _activeTeam` 字段承接 `team`，赋值点同原 `_presenceTeam = team`）。加 `import 'member_presence_cubit.dart';`。

> **承接说明**：现 `_presenceTeam` 在 cubit 内还被 `materializeMember`/`injectMemberStdin`（1005、1029 行）当作"当前 team"使用。为不破坏这条路径，在 cubit 内引入 `TeamConfig? _activeTeam;`，在原先 `_presenceTeam = team;`（610 行）处改为 `_activeTeam = team;`，并把 1005、1029 行的 `_presenceTeam` 改为 `_activeTeam`。Task 5 会把它随 bus 协作者迁走。

- [ ] **Step 4: app_shell 构造并绑定 presence cubit**

在 `lib/app/app_shell.dart` 现 481 行（`chatCubit = ChatCubit(...)` 之后）加：

```dart
memberPresenceCubit = MemberPresenceCubit();
chatCubit.bindPresenceCubit(memberPresenceCubit);
```

在 `AppShell` 字段区（仿 106、230 行 `chatCubit`）加 `final MemberPresenceCubit memberPresenceCubit;` / `late final MemberPresenceCubit memberPresenceCubit;`，构造与 `buildAppShell` 返回的 `AppShell(...)`（现 511 行起）补 `memberPresenceCubit: memberPresenceCubit,`，并在 `buildAppShell` 顶部声明 `late final MemberPresenceCubit memberPresenceCubit;`。加 `import '../cubits/member_presence_cubit.dart';`。

- [ ] **Step 5: main.dart 注入 BlocProvider**

在 `lib/main.dart` 现 175 行（`BlocProvider.value(value: shell.chatCubit),`）下一行加：

```dart
BlocProvider.value(value: shell.memberPresenceCubit),
```

- [ ] **Step 6: right_tools_panel 改用 presence cubit**

编辑 `lib/widgets/right_tools/right_tools_panel.dart`：
- 字段 `ChatCubit? _chatCubit;` 旁加 `MemberPresenceCubit? _presenceCubit;`
- `didChangeDependencies`（46–54 行）：`detach/attachPresenceUi` 的接收者由 `_chatCubit` 改为 `context.read<MemberPresenceCubit>()`，并缓存到 `_presenceCubit`
- `dispose`（57–60 行）：`_chatCubit?.detachPresenceUi();` → `_presenceCubit?.detachPresenceUi();`
- `build` 内 `syncPresenceTeam`（74 行）接收者改为 `_presenceCubit`
- `MembersPanel(... memberPresence: chatCubit.state.memberPresence ...)`（96 行）改为 `memberPresence: context.watch<MemberPresenceCubit>().state.presence,`
- 加 `import '../../cubits/member_presence_cubit.dart';`

- [ ] **Step 7: 改写 presence 测试为 cubit 直测**

把 `test/cubits/chat_cubit_presence_test.dart` 重命名为 `test/cubits/member_presence_cubit_test.dart`，针对 `MemberPresenceCubit` 直接构造 + `attachPresenceUi()` + `syncPresenceTeam(team)` + `updateTarget(PresenceTarget(...))` 驱动，断言 `cubit.state.presence`。复用原文件里的 `_DelayedPresenceService` 与 `fake_async` 时序逻辑；把对 `ChatState.memberPresence` 的断言改为 `MemberPresenceState.presence`。删除原文件。

```bash
cd client && git mv test/cubits/chat_cubit_presence_test.dart test/cubits/member_presence_cubit_test.dart
```

- [ ] **Step 8: analyze + 全量回归**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyze 无 error；测试 PASS

- [ ] **Step 9: Commit**

```bash
cd client && git add -A
git commit -m "refactor(chat): extract MemberPresenceCubit, drop memberPresence from ChatState"
```

---

## Task 4: 抽出 `ChatTabStore`（独占 List<ChatTab>）

把 tab 列表的查/改/派生收进一个可纯测的仓储；cubit 仅在其变更后 emit。

**Files:**
- Create: `lib/cubits/chat/chat_tab_store.dart`
- Test: `test/cubits/chat/chat_tab_store_test.dart`
- Modify: `lib/cubits/chat_cubit.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/cubits/chat/chat_tab_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/chat_tab_store.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';

ChatTab _tab(String id) =>
    ChatTab(info: ChatTabInfo(id: id, title: id, subtitle: ''), cliTeamName: id);

void main() {
  test('append + bySessionId + toInfos', () {
    final store = ChatTabStore();
    store.append(_tab('a'));
    store.append(_tab('b'));

    expect(store.length, 2);
    expect(store.bySessionId('b')!.cliTeamName, 'b');
    expect(store.toInfos().map((i) => i.id).toList(), ['a', 'b']);
  });

  test('activeTab clamps index', () {
    final store = ChatTabStore()..append(_tab('a'))..append(_tab('b'));
    expect(store.activeTab(99)!.info.id, 'b');
    expect(store.activeTab(-1)!.info.id, 'a');
  });

  test('defaultMemberId prefers team-lead', () {
    final store = ChatTabStore();
    // team with members [member-1, team-lead] -> picks team-lead
    // (uses TeamConfig fixture; see helper below)
    expect(store.length, 0);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/cubits/chat/chat_tab_store_test.dart`
Expected: FAIL（`chat_tab_store.dart` 不存在）

- [ ] **Step 3: 实现 `ChatTabStore`**

搬现以下成员的纯逻辑部分（去掉所有 `emit`/`state.copyWith`，改为返回值或纯内存操作）：`_internalTabs`、`_activeTab`(440–444)、`_tabBySessionId`(991–996)、`_visibleTabs`(1830–1832)、`_appendLocalTab` 的列表部分(1786–1805)、`_ensureActiveSessionTab`(1807–1814)、`_localSessionInfo`(1816–1822)、`_defaultMemberId`(1824–1828)、`_workingDirectoryAndAddDirsForTab`(1766–1784)、`_sessionForTab`(816–825)。

```dart
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../services/storage/app_storage.dart';
import 'model/chat_tab.dart';
import 'model/chat_tab_info.dart';

/// Owns the open-tab list and all pure queries/derivations over it.
/// Never emits — callers read results and update ChatState themselves.
class ChatTabStore {
  final List<ChatTab> _tabs = [];

  List<ChatTab> get tabs => _tabs;
  int get length => _tabs.length;
  bool get isEmpty => _tabs.isEmpty;

  List<ChatTabInfo> toInfos() => _tabs.map((t) => t.info).toList();

  ChatTab? activeTab(int activeTabIndex) {
    if (_tabs.isEmpty) return null;
    final index = activeTabIndex.clamp(0, _tabs.length - 1);
    return _tabs[index];
  }

  ChatTab? bySessionId(String id) {
    for (final tab in _tabs) {
      if (tab.info.id == id) return tab;
    }
    return null;
  }

  int indexOfSession(String id) =>
      _tabs.indexWhere((t) => t.info.id == id);

  void append(ChatTab tab) => _tabs.add(tab);
  ChatTab removeAt(int index) => _tabs.removeAt(index);

  String defaultMemberId(TeamConfig team) {
    if (team.members.isEmpty) return '';
    final lead = team.members.where((m) => m.id == 'team-lead');
    return lead.isEmpty ? team.members.first.id : lead.first.id;
  }

  ChatTabInfo localSessionInfo(TeamConfig team) => ChatTabInfo(
        id: 'local-${team.id}',
        title: team.name,
        subtitle: 'local session',
      );

  ChatTab appendLocalTab(TeamConfig team, {required String cliTeamName}) {
    final tab = ChatTab(
      info: localSessionInfo(team),
      cliTeamName: cliTeamName,
      selectedMemberId: defaultMemberId(team),
    );
    _tabs.add(tab);
    return tab;
  }

  (String, List<String>) workingDirectoryAndAddDirsForTab(
    ChatTab tab,
    List<AppSession> sessions,
  ) {
    // ... 搬现 1766–1784 行函数体，把 state.sessions 改为参数 sessions。
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) {
      return (AppStorage.cwd, const <String>[]);
    }
    for (final s in sessions) {
      if (s.sessionId != tabId) continue;
      final wd = s.primaryPath.trim();
      final addl = s.additionalPaths
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      return (wd.isNotEmpty ? wd : AppStorage.cwd, addl);
    }
    return (AppStorage.cwd, const <String>[]);
  }

  AppSession? sessionForTab(ChatTab tab, List<AppSession> sessions) {
    final cached = tab.persistedSession;
    if (cached != null) return cached;
    final tabId = tab.info.id;
    if (tabId.startsWith('local-')) return null;
    for (final s in sessions) {
      if (s.sessionId == tabId) return s;
    }
    return null;
  }
}
```

- [ ] **Step 4: 跑测试确认通过**（补全 `defaultMemberId` 测试的 `TeamConfig` fixture）

Run: `cd client && flutter test test/cubits/chat/chat_tab_store_test.dart`
Expected: PASS

- [ ] **Step 5: 在 `chat_cubit.dart` 接入 store**

加字段 `final ChatTabStore _tabStore = ChatTabStore();`，删除字段 `_internalTabs`。全文件替换：
- `_internalTabs` → `_tabStore.tabs`
- `_internalTabs.length` → `_tabStore.length`
- `_internalTabs.isEmpty` → `_tabStore.isEmpty`
- `_activeTab` → `_tabStore.activeTab(state.activeTabIndex)`（注意原 `_activeTab` getter 内用了 `state.activeTabIndex`，现传入）
- `_tabBySessionId(x)` → `_tabStore.bySessionId(x)`
- `_visibleTabs()` → `_tabStore.toInfos()`
- `_localSessionInfo` → `_tabStore.localSessionInfo`
- `_defaultMemberId` → `_tabStore.defaultMemberId`
- `_sessionForTab(tab)` → `_tabStore.sessionForTab(tab, state.sessions)`
- `_workingDirectoryAndAddDirsForTab(tab)` → `_tabStore.workingDirectoryAndAddDirsForTab(tab, state.sessions)`

删除 cubit 内这些方法定义。`_appendLocalTab`/`_ensureActiveSessionTab` 保留为 cubit 私有薄封装（调用 `_tabStore.appendLocalTab(team, cliTeamName: _uuid.v4())` 后按 `emitChange` 决定是否 emit）。加 `import 'chat/chat_tab_store.dart';`。

- [ ] **Step 6: analyze + 全量回归**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
cd client && git add lib/cubits/chat_cubit.dart lib/cubits/chat/chat_tab_store.dart test/cubits/chat/chat_tab_store_test.dart
git commit -m "refactor(chat): extract ChatTabStore"
```

---

## Task 5: 抽出 `TabTeamBusCoordinator`（bus / mcp / idle-watch）

**Files:**
- Create: `lib/cubits/chat/tab_team_bus_coordinator.dart`
- Modify: `lib/cubits/chat_cubit.dart`、`test/cubits/chat_cubit_team_bus_test.dart`

- [ ] **Step 1: 定义窄接口 + 协作者骨架**

```dart
// lib/cubits/chat/tab_team_bus_coordinator.dart
import 'dart:async';

import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../services/team_bus/agent_node.dart';
import '../../services/team_bus/chat_cubit_member_launcher.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_config.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_server.dart';
import '../../services/team_bus/persistence/bus_message_store_factory.dart';
import '../../services/team_bus/team_bus.dart';
import '../../services/team_bus/teammate_roster_profile.dart';
import '../../utils/team_member_naming.dart';
import 'chat_session_shell_factory.dart';
import 'chat_tab_store.dart';
import 'model/chat_tab.dart';

/// Edge ChatCubit must implement so the coordinator can drive member connects
/// from the bus (materialize) path.
abstract interface class MemberConnector {
  void scheduleMemberConnect(TeamConfig team, TeamMemberConfig member, ChatTab tab);
}

/// Owns per-tab TeamBus + MCP server lifecycle and the cross-tab idle watch.
/// Implements [MemberMaterializer] (was ChatCubit's role).
class TabTeamBusCoordinator implements MemberMaterializer {
  TabTeamBusCoordinator({
    required ChatTabStore tabStore,
    required ChatSessionShellFactory shellFactory,
    required MemberConnector connector,
    required TeamConfig? Function() activeTeam,
    required bool Function() isClosed,
  })  : _tabStore = tabStore,
        _shellFactory = shellFactory,
        _connector = connector,
        _activeTeam = activeTeam,
        _isClosed = isClosed;

  final ChatTabStore _tabStore;
  final ChatSessionShellFactory _shellFactory;
  final MemberConnector _connector;
  final TeamConfig? Function() _activeTeam;
  final bool Function() _isClosed;

  final Map<(String, String), Completer<void>> _memberReady = {};
  Timer? _idleWatchTimer;
  final Map<String, bool> _lastWorking = {};
}
```

- [ ] **Step 2: 迁移 bus 安装 + 路由 + 物化 + idle**

把以下成员从 cubit 搬入协作者（去掉 `_` 前缀使其可被 cubit 调用，逻辑原样）：
- `installBusForTab(ChatTab tab, TeamConfig team, AppSession session)`：抽现 612–661 行（建 `TeamBus` + `installSessionContext` + `declareMember` 循环 + `rehydrateUnread` + `TeammateBusMcpServer.start` + 赋值 `tab.teamBus/mcpServer` + `ensureIdleWatch()`）。其中 `ChatCubitMemberLauncher(materializer: this, ...)` 的 `this` 改为 `this`（协作者自身现在实现 `MemberMaterializer`）。
- `busUserInputRouting`（887–899）
- `materializeMember`（998–1021，`@override`）：`_tabBySessionId` → `_tabStore.bySessionId`；`_presenceTeam` → `_activeTeam()`；`_scheduleMemberConnect(...)` → `_connector.scheduleMemberConnect(...)`；`_memberReady` 为本类字段。
- `injectMemberStdin`（1023–1040，`@override`）：`_tabBySessionId` → `_tabStore.bySessionId`；`_cliForMember` → `_shellFactory.cliForMember`；`_presenceTeam` → `_activeTeam()`。
- `markMemberReady(String sessionId, String memberId)`：封装现 974 行 `_memberReady.remove((tab.info.id, member.id))?.complete();`，供 `_connectMemberShell` 的 `onProcessStarted` 调用。
- `ensureIdleWatch`/`maybeStopIdleWatch`/`_tickIdleWatch`（1362–1394）：`_internalTabs` → `_tabStore.tabs`；`isClosed` → `_isClosed()`。
- `hasTeamBusResources`/`teammateBusMcpEndpointForSession`（1849–1864）：`_tabBySessionId` → `_tabStore.bySessionId`。
- `disposeIdleWatch()`：封装 `_idleWatchTimer?.cancel(); _idleWatchTimer = null; _lastWorking.clear();`，供 cubit `close()` 调用。

- [ ] **Step 3: cubit 接入协作者，删除原逻辑**

加字段（在 `_tabStore`、`_shellFactory` 之后构造）：

```dart
late final TabTeamBusCoordinator _busCoordinator = TabTeamBusCoordinator(
  tabStore: _tabStore,
  shellFactory: _shellFactory,
  connector: this,
  activeTeam: () => _activeTeam,
  isClosed: () => isClosed,
);
```

让 `ChatCubit ... implements MemberConnector`（移除原 `implements MemberMaterializer`）。新增：

```dart
@override
void scheduleMemberConnect(TeamConfig team, TeamMemberConfig member, ChatTab tab) =>
    _scheduleMemberConnect(team, member, tab);
```

删除 cubit 内字段 `_memberReady`/`_idleWatchTimer`/`_lastWorking` 与方法 `materializeMember`/`injectMemberStdin`/`_busUserInputRouting`/`_ensureIdleWatch`/`_maybeStopIdleWatch`/`_tickIdleWatch`/`hasTeamBusResources`/`teammateBusMcpEndpointForSession`。

替换调用点：
- `openSessionTab` 现 612–661 整段 → `await _busCoordinator.installBusForTab(internalTab, team, session);`
- `_connectMemberShell` 内 `busUserInputRouting: _busUserInputRouting(tab, team, member)` → `_busCoordinator.busUserInputRouting(tab, team, member)`
- `_connectMemberShell` `onProcessStarted` 内 `_memberReady.remove((tab.info.id, member.id))?.complete();` → `_busCoordinator.markMemberReady(tab.info.id, member.id);`
- `closeTab`/`closeOtherTabs`/`closeRightTabs`/`deleteSession` 内 `_maybeStopIdleWatch()` → `_busCoordinator.maybeStopIdleWatch()`
- `close()` 内 idle 清理三行 → `_busCoordinator.disposeIdleWatch();`

加 `import 'chat/tab_team_bus_coordinator.dart';`。

- [ ] **Step 4: 调整 team bus 测试**

`test/cubits/chat_cubit_team_bus_test.dart` 内对 `hasTeamBusResources`/`teammateBusMcpEndpointForSession` 的断言：若它们曾通过 `ChatCubit` 暴露（`@visibleForTesting`），现改为 cubit 上保留两个转发 getter（薄封装 `_busCoordinator.hasTeamBusResources(id)`），保持测试 API 不变；或直接断言协作者。优先保留 cubit 转发以最小化测试改动：

```dart
@visibleForTesting
bool hasTeamBusResources(String sessionId) =>
    _busCoordinator.hasTeamBusResources(sessionId);

@visibleForTesting
Uri? teammateBusMcpEndpointForSession(String sessionId) =>
    _busCoordinator.teammateBusMcpEndpointForSession(sessionId);
```

- [ ] **Step 5: analyze + 全量回归**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: PASS（特别确认 `chat_cubit_team_bus_test.dart` 全绿）

- [ ] **Step 6: Commit**

```bash
cd client && git add lib/cubits/chat_cubit.dart lib/cubits/chat/tab_team_bus_coordinator.dart test/cubits/chat_cubit_team_bus_test.dart
git commit -m "refactor(chat): extract TabTeamBusCoordinator (bus/mcp/idle-watch)"
```

---

## Task 6: 抽出连接状态机 `ChatConnectStateMixin`

把纯 `ChatState` emit 编排收成 mixin，给 cubit 瘦身但保持 emit 单写者。

**Files:**
- Create: `lib/cubits/chat/chat_connect_state_mixin.dart`
- Modify: `lib/cubits/chat_cubit.dart`

- [ ] **Step 1: 创建 mixin**

```dart
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../services/session_launch_error.dart' as _;
import '../../utils/session_display_title.dart';
import '../../utils/session_launch_error.dart';
import 'chat_tab_store.dart';
import 'model/chat_state.dart';

/// Launch-error / connecting state machine over ChatState. Mixed into ChatCubit
/// so it can call emit/state/isClosed directly (kept as the single emit owner).
mixin ChatConnectStateMixin on Cubit<ChatState> {
  ChatTabStore get tabStore;
  void onTabRunningChanged(); // ChatCubit pushes presence target after emit.

  void beginSessionConnect(String sessionId) {
    clearLaunchError(sessionId);
    if (state.sessionConnectingId == sessionId) return;
    emit(state.copyWith(
      sessionConnectingId: sessionId,
      stateVersion: state.stateVersion + 1,
    ));
  }

  void setLaunchError(String sessionId, String rawMessage) {
    // ... 搬现 1704–1727 行；_internalTabs → tabStore.tabs；_visibleTabs() → tabStore.toInfos()
    final message = formatSessionLaunchError(rawMessage);
    if (message.isEmpty) return;
    final idx = tabStore.indexOfSession(sessionId);
    if (idx != -1) {
      tabStore.tabs[idx].info =
          tabStore.tabs[idx].info.copyWith(launchError: message);
      emit(state.copyWith(
        tabs: tabStore.toInfos(),
        clearSessionLaunchError: true,
        stateVersion: state.stateVersion + 1,
      ));
      return;
    }
    emit(state.copyWith(
      sessionLaunchError: message,
      stateVersion: state.stateVersion + 1,
    ));
  }

  void clearLaunchError(String sessionId) {
    // ... 搬现 1729–1746 行（同样替换 _internalTabs / _visibleTabs）
    var tabChanged = false;
    final idx = tabStore.indexOfSession(sessionId);
    if (idx != -1 && tabStore.tabs[idx].info.launchError != null) {
      tabStore.tabs[idx].info =
          tabStore.tabs[idx].info.copyWith(clearLaunchError: true);
      tabChanged = true;
    }
    if (!tabChanged && state.sessionLaunchError == null) return;
    emit(state.copyWith(
      tabs: tabChanged ? tabStore.toInfos() : state.tabs,
      clearSessionLaunchError: true,
      stateVersion: state.stateVersion + 1,
    ));
  }

  void failSessionConnect(String sessionId, String rawMessage) {
    setLaunchError(sessionId, rawMessage);
    finishSessionConnect(sessionId);
  }

  void finishSessionConnect(String sessionId) {
    updateTabRunning(sessionId);
    if (state.sessionConnectingId != sessionId) return;
    emit(state.copyWith(
      clearSessionConnectingId: true,
      stateVersion: state.stateVersion + 1,
    ));
  }

  void updateTabRunning(String tabId) {
    final idx = tabStore.indexOfSession(tabId);
    if (idx == -1) return;
    tabStore.tabs[idx].info =
        tabStore.tabs[idx].info.copyWith(isRunning: tabStore.tabs[idx].isRunning);
    emit(state.copyWith(
      tabs: tabStore.toInfos(),
      stateVersion: state.stateVersion + 1,
    ));
    onTabRunningChanged();
  }

  void emitLaunchWarnings(List<String> warnings) {
    if (warnings.isEmpty || isClosed) return;
    emit(state.copyWith(
      snackbarMessage: warnings.first,
      stateVersion: state.stateVersion + 1,
    ));
  }

  void clearSnackbarMessage() {
    if (isClosed || state.snackbarMessage == null) return;
    emit(state.copyWith(clearSnackbarMessage: true));
  }
}
```

> 删除顶部那行占位 `import '... session_launch_error.dart' as _;`——只保留真正用到的 `import '../../utils/session_launch_error.dart';`。

- [ ] **Step 2: cubit 混入并改调用点**

`class ChatCubit extends Cubit<ChatState> with ChatConnectStateMixin implements MemberConnector`。实现接口要求：

```dart
@override
ChatTabStore get tabStore => _tabStore;

@override
void onTabRunningChanged() => _pushPresenceTarget();
```

删除 cubit 内方法 `_beginSessionConnect`/`_setLaunchError`/`_clearLaunchError`/`_failSessionConnect`/`_finishSessionConnect`/`_updateTabRunning`/`_emitLaunchWarnings`/`clearSnackbarMessage`。全文件替换调用：`_beginSessionConnect`→`beginSessionConnect`、`_failSessionConnect`→`failSessionConnect`、`_finishSessionConnect`→`finishSessionConnect`、`_clearLaunchError`→`clearLaunchError`、`_setLaunchError`→`setLaunchError`、`_updateTabRunning`→`updateTabRunning`、`_emitLaunchWarnings`→`emitLaunchWarnings`。原 `_updateTabRunning` 末尾的 `refreshPresencePolling()` 行为已由 mixin 的 `onTabRunningChanged()` 承接，删除原行。加 `import 'chat/chat_connect_state_mixin.dart';`。

- [ ] **Step 3: analyze + 全量回归**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
cd client && git add lib/cubits/chat_cubit.dart lib/cubits/chat/chat_connect_state_mixin.dart
git commit -m "refactor(chat): extract ChatConnectStateMixin"
```

---

## Task 7: 抽出 `SessionDataStore`（repo CRUD + 可见性）

**Files:**
- Create: `lib/cubits/chat/session_data_store.dart`
- Test: `test/cubits/chat/session_data_store_test.dart`
- Modify: `lib/cubits/chat_cubit.dart`

- [ ] **Step 1: 写失败测试（可见性计算是纯函数，最值得测）**

```dart
// test/cubits/chat/session_data_store_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/session_data_store.dart';
import 'package:teampilot/models/app_project.dart';
import 'package:teampilot/models/app_session.dart';

void main() {
  test('unscoped snapshot exposes all', () {
    final store = SessionDataStore();
    final projects = [AppProject(projectId: 'p', primaryPath: '/p')];
    final sessions = [
      AppSession(sessionId: 's', projectId: 'p', primaryPath: '/p',
          sessionTeam: 't1', createdAt: 0),
    ];
    final snap = store.deriveSnapshot(projects: projects, sessions: sessions);
    expect(snap.visibleSessions, sessions);
    expect(snap.visibleProjects, projects);
  });

  test('team scope filters by sessionTeam', () {
    final store = SessionDataStore()
      ..setScope(scopeSessionsToSelectedTeam: true, selectedTeamId: 't1');
    final projects = [
      AppProject(projectId: 'p1', primaryPath: '/p1'),
      AppProject(projectId: 'p2', primaryPath: '/p2'),
    ];
    final sessions = [
      AppSession(sessionId: 's1', projectId: 'p1', primaryPath: '/p1',
          sessionTeam: 't1', createdAt: 0),
      AppSession(sessionId: 's2', projectId: 'p2', primaryPath: '/p2',
          sessionTeam: 't2', createdAt: 0),
    ];
    final snap = store.deriveSnapshot(projects: projects, sessions: sessions);
    expect(snap.visibleSessions.map((s) => s.sessionId).toList(), ['s1']);
    expect(snap.visibleProjects.map((p) => p.projectId).toList(), ['p1']);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd client && flutter test test/cubits/chat/session_data_store_test.dart`
Expected: FAIL（文件不存在）

- [ ] **Step 3: 实现 `SessionDataStore` + `ChatDataSnapshot`**

```dart
import 'package:equatable/equatable.dart';

import '../../models/app_project.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../repositories/session_repository.dart';
import '../../utils/project_path_utils.dart';

class ChatDataSnapshot extends Equatable {
  const ChatDataSnapshot({
    required this.projects,
    required this.sessions,
    required this.visibleProjects,
    required this.visibleSessions,
  });

  final List<AppProject> projects;
  final List<AppSession> sessions;
  final List<AppProject> visibleProjects;
  final List<AppSession> visibleSessions;

  @override
  List<Object?> get props =>
      [projects, sessions, visibleProjects, visibleSessions];
}

/// Owns team-scope flags and wraps SessionRepository. Returns snapshots;
/// ChatCubit emits them (single emit owner).
class SessionDataStore {
  bool _scopeSessionsToSelectedTeam = false;
  String? _selectedTeamId;

  /// Returns true when scope actually changed (caller then re-derives/emits).
  bool setScope({
    required bool scopeSessionsToSelectedTeam,
    String? selectedTeamId,
  }) {
    final normalized =
        (selectedTeamId != null && selectedTeamId.isNotEmpty) ? selectedTeamId : null;
    if (_scopeSessionsToSelectedTeam == scopeSessionsToSelectedTeam &&
        _selectedTeamId == normalized) {
      return false;
    }
    _scopeSessionsToSelectedTeam = scopeSessionsToSelectedTeam;
    _selectedTeamId = normalized;
    return true;
  }

  List<AppSession> _computeVisibleSessions(List<AppSession> all) {
    if (!_scopeSessionsToSelectedTeam) return all;
    final tid = _selectedTeamId;
    if (tid == null || tid.isEmpty) return [];
    return all.where((s) => s.sessionTeam == tid).toList();
  }

  List<AppProject> _computeVisibleProjects(
    List<AppProject> all, List<AppSession> visibleSessions) {
    if (!_scopeSessionsToSelectedTeam) return all;
    return all
        .where((p) => visibleSessions.any((s) => s.projectId == p.projectId))
        .toList();
  }

  ChatDataSnapshot deriveSnapshot({
    required List<AppProject> projects,
    required List<AppSession> sessions,
  }) {
    final visS = _computeVisibleSessions(sessions);
    final visP = _computeVisibleProjects(projects, visS);
    return ChatDataSnapshot(
      projects: projects,
      sessions: sessions,
      visibleProjects: visP,
      visibleSessions: visS,
    );
  }

  Future<ChatDataSnapshot> loadProjectData(SessionRepository repo) async {
    final projects = await repo.loadProjects();
    final sessions = await repo.loadSessions();
    return deriveSnapshot(projects: projects, sessions: sessions);
  }

  Future<AppSession> createSession(
    String projectId, SessionRepository repo,
    {String sessionTeamId = '', List<TeamMemberConfig> rosterMembers = const []}) {
    return repo.createSession(projectId,
        sessionTeam: sessionTeamId, rosterMembers: rosterMembers);
  }

  // createProjectWithFirstSession / addProjectDirectory / updateProjectMetadata /
  // deleteProject 的 repo 调用部分照搬现 508–555、1648–1662 行，返回值改为
  // Future<ChatDataSnapshot>（内部末尾 return loadProjectData(repo)）。
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd client && flutter test test/cubits/chat/session_data_store_test.dart`
Expected: PASS

- [ ] **Step 5: cubit 接入 data store**

加字段 `final SessionDataStore _dataStore = SessionDataStore();`，删除字段 `_scopeSessionsToSelectedTeam`/`_selectedTeamId` 与方法 `_computeVisibleSessions`/`_computeVisibleProjects`/`_emitWithDerivedSessionsAndProjects`/`_refreshVisibleLists`。

新增 cubit 私有 helper（保持 emit 在 cubit）：

```dart
void _emitSnapshot(ChatDataSnapshot snap, {ChatState? base}) {
  final s = base ?? state;
  emit(s.copyWith(
    projects: snap.projects,
    sessions: snap.sessions,
    visibleProjects: snap.visibleProjects,
    visibleSessions: snap.visibleSessions,
  ));
}
```

改写门面方法委托 + emit：
- `setTeamSessionScope` → `if (_dataStore.setScope(...)) _emitSnapshot(_dataStore.deriveSnapshot(projects: state.projects, sessions: state.sessions));`
- `loadProjectData(repo)` → `_emitSnapshot(await _dataStore.loadProjectData(repo));`
- `ingestProjectSessionSnapshot` → `_emitSnapshot(_dataStore.deriveSnapshot(projects: projects, sessions: sessions));`
- `createSession`/`createProjectWithFirstSession`/`addProjectDirectory`/`updateProjectMetadata`/`deleteProject` → 委托 `_dataStore.*` 取回 snapshot 后 `_emitSnapshot`
- `_persistSessionStarted`(827–842)：末尾 `_emitWithDerivedSessionsAndProjects(state.copyWith(sessions: sessions))` → `_emitSnapshot(_dataStore.deriveSnapshot(projects: state.projects, sessions: sessions));`
- `renameSession`(1574–1596) / `deleteSession`(1598–1646)：emit 处同样改用 `_emitSnapshot(_dataStore.deriveSnapshot(...), base: state.copyWith(tabs: ..., activeTabIndex: ..., ...))` —— 即 tab 相关字段先放进 `base`，再叠加 data snapshot。

加 `import 'chat/session_data_store.dart';`。

- [ ] **Step 6: analyze + 全量回归**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
cd client && git add lib/cubits/chat_cubit.dart lib/cubits/chat/session_data_store.dart test/cubits/chat/session_data_store_test.dart
git commit -m "refactor(chat): extract SessionDataStore"
```

---

## Task 8: 收尾 — 行数核对、最终全量验证

**Files:**
- Modify: 视情况微调（不应再有大改动）

- [ ] **Step 1: 核对每个文件落在软上限内**

Run: `cd client && wc -l lib/cubits/chat_cubit.dart lib/cubits/member_presence_cubit.dart lib/cubits/chat/*.dart lib/cubits/chat/model/*.dart`
Expected: `chat_cubit.dart` ≤ ~500；其余各文件 ≤ ~200。若 `chat_cubit.dart` 仍 >550，复核连接流是否夹带了应属协作者的纯逻辑。

- [ ] **Step 2: 全量 analyze（含 infos 审视新文件）**

Run: `cd client && flutter analyze`
Expected: 无 error；新文件无未用 import / 死代码告警

- [ ] **Step 3: 全量测试（含新增三个单测 + 改写的 presence 测试）**

Run: `cd client && flutter test --exclude-tags integration`
Expected: ALL PASS

- [ ] **Step 4: 跑相关 widget 测试确认 UI 接线正确**

Run: `cd client && flutter test test/widget_test.dart`
Expected: PASS（验证 `MemberPresenceCubit` 的 `BlocProvider` 与 right_tools_panel 接线无回归）

- [ ] **Step 5: Commit（若有微调）**

```bash
cd client && git add -A
git commit -m "refactor(chat): finalize ChatCubit decomposition"
```

---

## Self-Review

**1. Spec coverage（对照第二节六域 A–F）：**
- A 会话工厂 → Task 2 ✅；B Tab 仓储 → Task 4 ✅；C 数据仓储 → Task 7 ✅；D 连接状态机 → Task 6 ✅；E Team Bus → Task 5 ✅；F 存活 → Task 3 ✅；模型层 → Task 1 ✅；`memberPresence` 出 `ChatState` → Task 3 ✅；UI 消费迁移（members_panel/right_tools_panel/main.dart/app_shell）→ Task 3 ✅。

**2. Placeholder scan：** 大段「搬现 X–Y 行」均给出**精确源行号 + 替换规则**（`_internalTabs`→`_tabStore.tabs` 等），非空泛 TODO；新类型/接口/测试均给完整代码。

**3. Type consistency（关键签名锁定，全程一致）：**
- `ChatTab`（非 `_InternalTab`）；`ChatTabStore.activeTab(int)` / `bySessionId(String)` / `toInfos()` / `indexOfSession(String)` / `tabs` getter
- `ChatSessionShellFactory.newSession(TeamCli)` / `cliForMember(TeamConfig,String)`
- `MemberPresenceCubit` + `MemberPresenceState.presence` + `PresenceTarget(cliTeamName,memberToolConfigDir,memberShells)` + `updateTarget` / `bindPresenceCubit` / `_pushPresenceTarget`
- `TabTeamBusCoordinator` implements `MemberMaterializer`；`MemberConnector.scheduleMemberConnect(TeamConfig,TeamMemberConfig,ChatTab)`；`installBusForTab` / `busUserInputRouting` / `markMemberReady` / `maybeStopIdleWatch` / `disposeIdleWatch` / `hasTeamBusResources` / `teammateBusMcpEndpointForSession`
- `ChatConnectStateMixin`：`beginSessionConnect` / `setLaunchError` / `clearLaunchError` / `failSessionConnect` / `finishSessionConnect` / `updateTabRunning` / `emitLaunchWarnings` / `clearSnackbarMessage`；要求宿主提供 `tabStore` getter 与 `onTabRunningChanged()`
- `SessionDataStore` + `ChatDataSnapshot(projects,sessions,visibleProjects,visibleSessions)`；`setScope` / `deriveSnapshot` / `loadProjectData`

**已知风险点（执行时重点验证）：**
- Task 3 的 `_activeTeam` 承接：确保 `materializeMember`/`injectMemberStdin` 在 Task 5 迁走后，cubit 仍正确给协作者喂 `activeTeam`。
- emit 时序：presence 改为独立 cubit 后，原先「tab 变更 → 同帧刷新 presence」改为 `_pushPresenceTarget()` 推送；`member_presence_cubit_test.dart` 必须覆盖 `updateTarget` 后轮询启动的时序（沿用 `fake_async`）。
- `renameSession`/`deleteSession` 同时改 tab + data，Task 7 用 `_emitSnapshot(..., base: ...)` 合并，注意 `activeTabIndex`/`activeSessionId`/`selectedMemberId` 必须进 `base` 不被 snapshot 覆盖。
