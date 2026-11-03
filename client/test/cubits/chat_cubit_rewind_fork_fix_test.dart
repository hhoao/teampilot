import 'dart:async';
import 'dart:io';

import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_paths.dart';
import 'package:teampilot/services/chat/rewind/seat_rewind_store.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/expert_hub_catalog.dart';
import 'package:teampilot/services/expert_hub/expert_member_materializer.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/utils/team/team_member_naming.dart';

import '../support/fake_terminal_session.dart';
import '../support/fixed_resume_lifecycle_service.dart';
import '../support/in_memory_filesystem.dart';
import '../support/post_frame_test_harness.dart';

TeamProfile _withBuiltinMembers(TeamProfile team) =>
    ExpertMemberMaterializer.materializeTeam(
      team,
      MemberCatalogSnapshot({for (final m in builtinExpertMembers()) m.key: m}),
    );

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'ACP rewind closes the runtime once and restores only after close finishes',
    () async {
      final env = await _openPersonal(acp: true, cli: CliTool.claude);
      final seeded = await _seedPersonal(
        session: env.session,
        kind: SeatRewindKind.personalAcp,
      );
      final acp = _GatedAcpCubit(
        runtime: _FakeAcpRuntime(),
        sessionId: env.session.sessionId,
        tool: CliTool.claude,
      );
      await acp.start(
        executable: 'claude',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      env.tab.acpRuntime = acp;
      env.tab.persistedSession = env.tab.persistedSession!.copyWith(acp: true);

      final rewind = env.cubit.rewindSeatTo(
        sessionId: env.session.sessionId,
        memberId: env.session.sessionId,
        commit: seeded.first.commit,
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(acp.closeCalls, 1);
      expect(await seeded.liveFile.readAsString(), 'two');

      acp.gate.complete();
      await rewind;

      expect(acp.closeCalls, 1);
      expect(await seeded.liveFile.readAsString(), 'one');
    },
  );

  test(
    'rewind records the checkpoint native session id before relaunch',
    () async {
      final env = await _openPersonal(cli: CliTool.claude);
      final seeded = await _seedPersonal(
        session: env.session,
        kind: SeatRewindKind.personalPty,
        firstNative: 'checkpoint-native',
        secondNative: 'later-native',
      );
      env.tab.persistedSession = env.tab.persistedSession!.withNativeSessionId(
        CliTool.claude.value,
        'live-native',
      );
      env.cubit.replaceSessionSnapshot(env.tab.persistedSession!);

      await env.cubit.rewindSeatTo(
        sessionId: env.session.sessionId,
        memberId: env.session.sessionId,
        commit: seeded.first.commit,
      );

      expect(env.cubit.nativeAtRelaunch, 'checkpoint-native');
      final loaded = await env.repo.loadSession(
        env.session.workspaceId,
        env.session.sessionId,
      );
      expect(
        loaded!.nativeSessionIds[CliTool.claude.value],
        'checkpoint-native',
      );
    },
  );

  test(
    'personal PTY stop disconnects resumeSession and waits until it exits',
    () async {
      final env = await _openPersonal(cli: CliTool.claude);
      final seeded = await _seedPersonal(
        session: env.session,
        kind: SeatRewindKind.personalPty,
      );
      final shell = _GateStopShell();
      env.tab.resumeSession = shell;

      final rewind = env.cubit.rewindSeatTo(
        sessionId: env.session.sessionId,
        memberId: env.session.sessionId,
        commit: seeded.first.commit,
      );
      var completed = false;
      unawaited(rewind.whenComplete(() => completed = true));
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(shell.disconnectCalls, 1);
      expect(shell.isRunning, isTrue);
      expect(completed, isFalse);
      expect(await seeded.liveFile.readAsString(), 'two');

      shell.exitProcess();
      await rewind;

      expect(completed, isTrue);
      expect(await seeded.liveFile.readAsString(), 'one');
    },
  );

  test(
    'mixed relaunch uses the requested member, not the selected one',
    () async {
      final env = await _openMixed();
      final team = env.team!;
      final lead = team.members.first;
      final worker = team.members[1];
      env.tab.selectedMemberId = lead.id;
      final seeded = await _seedMixedAcp(
        session: env.session,
        memberId: worker.id,
      );

      await env.cubit.rewindSeatTo(
        sessionId: env.session.sessionId,
        memberId: worker.id,
        commit: seeded.first.commit,
      );

      expect(env.cubit.relaunchCalls, [
        'ensure:${env.session.sessionId}:${worker.id}',
      ]);
    },
  );

  test('rewind failure sets cubit error and busy clears', () async {
    final env = await _openPersonal(cli: CliTool.claude);
    await _seedPersonal(session: env.session, kind: SeatRewindKind.personalPty);

    await expectLater(
      env.cubit.rewindSeatTo(
        sessionId: env.session.sessionId,
        memberId: env.session.sessionId,
        commit: 'not-a-commit',
      ),
      throwsA(isA<Object>()),
    );

    expect(env.cubit.state.rewindForkError, 'sessionRewindFailed');
    expect(env.cubit.state.rewindForkInProgress, isFalse);
  });

  test(
    'rename failure after create deletes the new session directory',
    () async {
      await _expectForkCleansUp(throwOn: 'rename');
    },
  );

  test(
    'native-id recording failure after create deletes the new session directory',
    () async {
      await _expectForkCleansUp(throwOn: 'native');
    },
  );
}

Future<void> _expectForkCleansUp({required String throwOn}) async {
  final repo = _ThrowingForkRepo(throwOn: throwOn);
  final postFrame = PostFrameTestHarness();
  final cubit = _HarnessCubit(repo: repo, postFrame: postFrame);
  addTearDown(() => tearDownChatCubitWithSessionPersist(cubit, postFrame));

  final workspace = await repo.createWorkspace([
    const WorkspaceFolder(path: '/work'),
  ]);
  final session = (await repo.createSession(
    workspace.workspaceId,
    cli: CliTool.claude,
  )).session;
  await cubit.loadWorkspaceData(repo);
  cubit.activateWorkspaceTab(
    workspaceTabKey: workspace.workspaceId,
    scopeSessionsToSelectedTeam: false,
  );
  await cubit.requestOpenSession(
    SessionOpenRequest(
      session: session,
      workspace: workspace,
      repo: repo,
      connectImmediately: false,
    ),
  );
  await drainPendingAsyncWork();
  await _seedPersonal(session: session, kind: SeatRewindKind.personalPty);

  final layout = testHomeStorage.context.layout;
  final before = Directory(
    layout.workspace.sessionsDir(workspace.workspaceId),
  ).listSync().whereType<Directory>().map((e) => p.basename(e.path)).toSet();

  await expectLater(
    cubit.forkSeatFrom(
      sessionId: session.sessionId,
      memberId: session.sessionId,
      commit: (await SeatRewindStore(
        gitDir: layout.pathContext.join(
          layout.workspace.sessionDir(workspace.workspaceId, session.sessionId),
          'rewind',
          'personal',
        ),
        workTree: layout.workspace.sessionRuntimeDir(
          workspace.workspaceId,
          session.sessionId,
        ),
        target: const SeatRewindTarget(
          kind: SeatRewindKind.personalPty,
          tool: 'claude',
        ),
      ).checkpoints()).first.commit,
    ),
    throwsA(isA<Object>()),
  );

  final after = Directory(
    layout.workspace.sessionsDir(workspace.workspaceId),
  ).listSync().whereType<Directory>().map((e) => p.basename(e.path)).toSet();
  expect(after, before);
  expect(cubit.state.rewindForkError, 'sessionForkFailed');
}

Future<_Env> _openPersonal({CliTool? cli, bool acp = false}) async {
  final repo = SessionRepository(storage: testHomeStorage);
  final postFrame = PostFrameTestHarness();
  final cubit = _HarnessCubit(repo: repo, postFrame: postFrame);
  addTearDown(() => tearDownChatCubitWithSessionPersist(cubit, postFrame));

  final workspace = await repo.createWorkspace([
    const WorkspaceFolder(path: '/work'),
  ]);
  final session = (await repo.createSession(
    workspace.workspaceId,
    cli: cli,
    acp: acp,
  )).session;
  await cubit.loadWorkspaceData(repo);
  cubit.activateWorkspaceTab(
    workspaceTabKey: workspace.workspaceId,
    scopeSessionsToSelectedTeam: false,
  );
  await cubit.requestOpenSession(
    SessionOpenRequest(
      session: session,
      workspace: workspace,
      repo: repo,
      connectImmediately: false,
    ),
  );
  await drainPendingAsyncWork();
  final tab = cubit.tabStore.getOpenTabBySessionId(session.sessionId)!;
  return _Env(
    cubit: cubit,
    repo: repo,
    session: tab.persistedSession ?? session,
    tab: tab,
    team: null,
  );
}

Future<_Env> _openMixed() async {
  final team = _withBuiltinMembers(
    TeamProfile(
      id: LaunchProfileProvisioner.defaultNativeTeamId,
      name: 'Team',
      roster: TeamMemberNaming.defaultRoster(),
    ),
  );
  final repo = SessionRepository(storage: testHomeStorage);
  final postFrame = PostFrameTestHarness();
  final cubit = _HarnessCubit(repo: repo, postFrame: postFrame);
  addTearDown(() => tearDownChatCubitWithSessionPersist(cubit, postFrame));

  final workspace = await repo.createWorkspace([
    const WorkspaceFolder(path: '/work'),
  ]);
  final session = (await repo.createSession(
    workspace.workspaceId,
    sessionTeam: team.id,
    rosterMembers: team.members,
    memberClis: {for (final m in team.members) m.id: CliTool.claude},
  )).session;
  await cubit.loadWorkspaceData(repo);
  cubit.activateWorkspaceTab(
    workspaceTabKey: workspace.workspaceId,
    scopeSessionsToSelectedTeam: false,
  );
  await cubit.requestOpenSession(
    SessionOpenRequest(
      session: session,
      workspace: workspace,
      team: team,
      member: team.members.first,
      repo: repo,
      connectImmediately: false,
    ),
  );
  await drainPendingAsyncWork();
  final tab = cubit.tabStore.getOpenTabBySessionId(session.sessionId)!;
  return _Env(
    cubit: cubit,
    repo: repo,
    session: tab.persistedSession ?? session,
    tab: tab,
    team: team,
  );
}

Future<_Seeded> _seedPersonal({
  required AppSession session,
  required SeatRewindKind kind,
  String firstNative = 'native-1',
  String secondNative = 'native-2',
}) async {
  final layout = testHomeStorage.context.layout;
  final workTree = layout.workspace.sessionRuntimeDir(
    session.workspaceId,
    session.sessionId,
  );
  final gitDir = layout.pathContext.join(
    layout.workspace.sessionDir(session.workspaceId, session.sessionId),
    'rewind',
    'personal',
  );
  await Directory('$workTree/claude/projects').create(recursive: true);
  final live = File('$workTree/claude/projects/a.jsonl');
  await live.writeAsString('one');
  if (kind == SeatRewindKind.personalAcp) {
    await File('$workTree/acp-transcript.jsonl').writeAsString('[]');
    await File('$workTree/acp-session.json').writeAsString('{"v":1}');
  }
  final store = SeatRewindStore(
    gitDir: gitDir,
    workTree: workTree,
    target: SeatRewindTarget(kind: kind, tool: 'claude'),
  );
  final first = await store.commitTurn(
    messageId: 'm1',
    nativeSessionId: firstNative,
  );
  await live.writeAsString('two');
  await store.commitTurn(messageId: 'm2', nativeSessionId: secondNative);
  return _Seeded(first: first, liveFile: live);
}

Future<_Seeded> _seedMixedAcp({
  required AppSession session,
  required String memberId,
}) async {
  final layout = testHomeStorage.context.layout;
  final workTree = layout.workspace.sessionRuntimeDir(
    session.workspaceId,
    session.sessionId,
  );
  final gitDir = layout.pathContext.join(
    layout.workspace.sessionDir(session.workspaceId, session.sessionId),
    'rewind',
    memberId,
  );
  await Directory(
    '$workTree/$memberId/claude/projects',
  ).create(recursive: true);
  final live = File('$workTree/$memberId/claude/projects/a.jsonl');
  await live.writeAsString('one');
  await File('$workTree/acp-transcript-$memberId.jsonl').writeAsString('[]');
  await File('$workTree/acp-session-$memberId.json').writeAsString('{"v":1}');
  final store = SeatRewindStore(
    gitDir: gitDir,
    workTree: workTree,
    target: SeatRewindTarget(
      kind: SeatRewindKind.mixedAcp,
      tool: 'claude',
      memberId: memberId,
    ),
  );
  final first = await store.commitTurn(messageId: 'm1');
  await live.writeAsString('two');
  await store.commitTurn(messageId: 'm2');
  return _Seeded(first: first, liveFile: live);
}

final class _Env {
  const _Env({
    required this.cubit,
    required this.repo,
    required this.session,
    required this.tab,
    required this.team,
  });

  final _HarnessCubit cubit;
  final SessionRepository repo;
  final AppSession session;
  final ChatTab tab;
  final TeamProfile? team;
}

final class _Seeded {
  const _Seeded({required this.first, required this.liveFile});

  final RewindCheckpoint first;
  final File liveFile;
}

final class _HarnessCubit extends ChatCubit {
  _HarnessCubit({
    required SessionRepository repo,
    required PostFrameTestHarness postFrame,
  }) : super(
         executableResolver: () => 'flashskyai',
         automationRepository: testAutomationRepository(),
         sessionRepository: repo,
         terminalSessionFactory:
             ({required String executable, int scrollbackLines = 10000}) =>
                 FakeTerminalSession(
                   executable: executable,
                   scrollbackLines: scrollbackLines,
                   fs: InMemoryFilesystem(),
                 ),
         postFrameScheduler: postFrame.scheduler,
         lifecycleService: FixedResumeLifecycleService(resume: false),
         storage: testHomeStorage,
       );

  final relaunchCalls = <String>[];
  String? nativeAtRelaunch;

  @override
  Future<void> retrySessionLaunch(String sessionId) async {
    AppSession? session;
    for (final candidate in state.sessions) {
      if (candidate.sessionId == sessionId) {
        session = candidate;
        break;
      }
    }
    nativeAtRelaunch = session?.nativeSessionIds[CliTool.claude.value];
    relaunchCalls.add(
      'retry:$sessionId:${tabStore.getOpenTabBySessionId(sessionId)?.selectedMemberId ?? ''}',
    );
  }

  @override
  Future<void> ensureMemberTerminalForView(
    String sessionId,
    String memberId,
  ) async {
    relaunchCalls.add('ensure:$sessionId:$memberId');
  }
}

final class _ThrowingForkRepo extends SessionRepository {
  _ThrowingForkRepo({required this.throwOn}) : super(storage: testHomeStorage);

  final String throwOn;

  @override
  Future<void> renameSession(String sessionId, String newName) async {
    if (throwOn == 'rename') throw StateError('rename failed');
    await super.renameSession(sessionId, newName);
  }

  @override
  Future<void> recordNativeSessionId(
    String sessionId, {
    required String tool,
    required String nativeId,
    String? rosterMemberId,
  }) async {
    if (throwOn == 'native') throw StateError('native failed');
    await super.recordNativeSessionId(
      sessionId,
      tool: tool,
      nativeId: nativeId,
      rosterMemberId: rosterMemberId,
    );
  }
}

final class _GateStopShell extends FakeTerminalSession {
  _GateStopShell() : super(fs: InMemoryFilesystem(), executable: 'claude');

  var disconnectCalls = 0;
  var _running = true;

  @override
  bool get isRunning => _running;

  @override
  bool get isDisposed => false;

  @override
  void disconnect() {
    disconnectCalls++;
  }

  void exitProcess() {
    _running = false;
  }
}

final class _GatedAcpCubit extends AcpChatRuntimeCubit {
  _GatedAcpCubit({
    required super.runtime,
    required super.sessionId,
    required super.tool,
  });

  int closeCalls = 0;
  final gate = Completer<void>();

  @override
  Future<void> close() async {
    closeCalls++;
    await gate.future;
    return super.close();
  }
}

class _FakeAcpRuntime implements AcpSessionRuntimeApi {
  bool started = false;

  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
    List<acpd.McpServer> mcpServers = const [],
    LaunchSecurityPolicy permissionPolicy = LaunchSecurityPolicy.fullAccess,
    String? resumeSessionId,
  }) async {
    started = true;
  }

  @override
  void setPermissionPolicy(LaunchSecurityPolicy policy) {}

  @override
  bool get isStarted => started;

  @override
  String get sessionId => 'acp-session-1';

  @override
  Future<void> prompt(String text) async {}

  @override
  Stream<AcpSessionUpdate> get updates => const Stream.empty();

  @override
  Stream<AgentPermissionRequest> get permissionRequests => const Stream.empty();

  @override
  Stream<AcpPendingClientRequest> get clientRequests => const Stream.empty();

  @override
  AcpAuthNotice? get lastAuthNotice => null;

  @override
  Future<int>? get agentProcessExitCode => null;

  @override
  Future<AgentPermissionReplyKind?> answerPermission(
    AgentPermissionReplyKind reply, {
    AgentPermissionAlwaysOption? always,
  }) async => reply;

  @override
  Future<void> answerAsk(AcpAskHoldReply reply) async {}

  @override
  Future<void> answerPlan(AcpPlanHoldReply reply) async {}

  @override
  void cancel() {}

  @override
  Future<void> close() async {}
}
