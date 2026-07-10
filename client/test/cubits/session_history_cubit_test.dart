import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/session_history_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/cli/registry/capabilities/session_history_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_history_context_builder.dart';
import 'package:teampilot/services/session/session_history_loader.dart';
import 'package:teampilot/services/storage/runtime_layout.dart';

import '../support/post_frame_test_harness.dart';

class _FakeHistoryCap implements SessionHistoryCapability {
  _FakeHistoryCap(this.snapshot);

  SessionHistorySnapshot snapshot;
  var calls = 0;
  final callMemberIds = <String?>[];

  @override
  Future<SessionHistorySnapshot> loadHistory(SessionHistoryContext ctx) async {
    calls++;
    callMemberIds.add(ctx.memberId);
    return snapshot;
  }
}

class _ToolDef implements CliToolDefinition {
  const _ToolDef(this.id, this.capabilities);

  @override
  final CliTool id;

  @override
  final Iterable<CliCapability> capabilities;

  @override
  bool get isLaunchSupported => true;
}

void main() {
  late Directory base;
  late LocalFilesystem fs;
  late RuntimeLayout layout;
  late _FakeHistoryCap fakeCap;
  late SessionHistoryLoader loader;
  late SessionHistoryCubit cubit;
  var mtimeToken = 'mtime-1';

  AppSession simpleSession({String id = 'sess-a'}) => AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work/project')],
    cli: CliTool.claude,
    createdAt: 1,
    updatedAt: 1,
  );

  AppSession teamSession({String id = 'sess-team'}) => AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    folders: const [WorkspaceFolder(path: '/work/project')],
    sessionTeam: 'team-1',
    cli: CliTool.claude,
    members: const [
      SessionMemberBinding(rosterMemberId: 'leader', taskId: 'task-leader'),
      SessionMemberBinding(rosterMemberId: 'dev', taskId: 'task-dev'),
    ],
    createdAt: 1,
    updatedAt: 1,
  );

  setUp(() {
    setUpTestAppStorage();
    base = Directory.systemTemp.createTempSync('session_history_cubit_');
    fs = LocalFilesystem(
      pathContext: p.Context(style: p.Style.posix, current: base.path),
    );
    layout = RuntimeLayout(teampilotRoot: base.path, fs: fs);
    fakeCap = _FakeHistoryCap(
      const SessionHistorySnapshot(
        turns: [
          SessionHistoryTurn(
            role: SessionHistoryRole.user,
            markdown: 'hello',
          ),
        ],
        status: SessionHistoryLoadStatus.ready,
      ),
    );
    final registry = CliToolRegistry()
      ..register(_ToolDef(CliTool.claude, [fakeCap]));
    loader = SessionHistoryLoader(
      registry: registry,
      contextBuilder: const SessionHistoryContextBuilder(),
      fs: () => fs,
      layout: () => layout,
      appDataRoot: () => base.path,
      resolveCacheToken: (_) async => mtimeToken,
    );
    cubit = SessionHistoryCubit(loader: loader);
  });

  tearDown(() async {
    await cubit.close();
    if (base.existsSync()) {
      base.deleteSync(recursive: true);
    }
    tearDownTestAppStorage();
  });

  test('load emits loading then ready', () async {
    final states = <SessionHistoryState>[];
    final sub = cubit.stream.listen(states.add);

    final done = cubit.load(
      session: simpleSession(),
      memberId: '',
    );
    expect(cubit.state.status, SessionHistoryViewStatus.loading);
    await done;
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(fakeCap.calls, 1);
    expect(cubit.state.status, SessionHistoryViewStatus.ready);
    expect(cubit.state.turns.single.markdown, 'hello');
    expect(
      states.map((s) => s.status),
      containsAllInOrder([
        SessionHistoryViewStatus.loading,
        SessionHistoryViewStatus.ready,
      ]),
    );
  });

  test('cache key is sessionId+memberId; member switch reloads', () async {
    final session = teamSession();
    final team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      cli: CliTool.claude,
      members: const [
        TeamMemberConfig(id: 'leader', name: 'Leader'),
        TeamMemberConfig(id: 'dev', name: 'Dev'),
      ],
    );

    await cubit.load(session: session, memberId: 'leader', team: team);
    expect(fakeCap.calls, 1);
    expect(fakeCap.callMemberIds.single, 'leader');
    expect(cubit.state.memberId, 'leader');

    await cubit.load(session: session, memberId: 'dev', team: team);
    expect(fakeCap.calls, 2);
    expect(fakeCap.callMemberIds, ['leader', 'dev']);
    expect(cubit.state.memberId, 'dev');
  });

  test('mtime unchanged reuses cache on reload', () async {
    final session = simpleSession();
    await cubit.load(session: session, memberId: '');
    expect(fakeCap.calls, 1);

    await cubit.load(session: session, memberId: '');
    expect(fakeCap.calls, 1);
    expect(cubit.state.status, SessionHistoryViewStatus.ready);

    mtimeToken = 'mtime-2';
    await cubit.load(session: session, memberId: '');
    expect(fakeCap.calls, 2);
  });
}
