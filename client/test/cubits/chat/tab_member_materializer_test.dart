import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/chat/launch/connect/member_connector.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/launch/session/member_input_ready_wait.dart';
import 'package:teampilot/services/chat/launch/session/tab_member_materializer.dart';
import 'package:teampilot/services/chat/runtime/tab_session_runtime_coordinator.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/utils/logging/logger.dart';

import '../../support/post_frame_test_harness.dart';

class _RecordingConnector implements MemberConnector {
  var scheduleCalls = 0;
  String? lastMemberId;
  bool? lastSelectMember;

  @override
  void scheduleMemberConnect(
    TeamProfile team,
    TeamMemberConfig member,
    String sessionId, {
    bool selectMember = true,
  }) {
    scheduleCalls++;
    lastMemberId = member.id;
    lastSelectMember = selectMember;
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'mixed materialize waits without duplicate connect while bus boots',
    () async {
      final store = ChatTabStore(storage: testHomeStorage);
      store.setActiveWorkspaceId('ws-1');
      final tab =
          ChatTab(
              info: const ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
              workspaceId: 'ws-1',
              cliTeamName: 'team-runtime',
            )
            ..persistedSession = AppSession(
              sessionId: 'sess-1',
              workspaceId: 'ws-1',
              sessionTeam: 'team-1',
              cliTeamName: 'team-runtime',
              createdAt: 0,
            );
      store.registerSession(tab);

      const team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        cli: CliTool.cursor,
        teamMode: TeamMode.mixed,
        members: [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
      );

      final connector = _RecordingConnector();
      final materializer = TabMemberMaterializer(
        runtime: TabSessionRuntimeCoordinator(
          tabStore: store,
          shellFactory: ChatSessionShellFactory(
            executableResolver: () => 'true',
          ),
          globalPresets: () => const [],
          activeTeam: () => team,
          isClosed: () => false,
        ),
        tabStore: store,
        connector: connector,
        activeTeam: () => team,
        isClosed: () => false,
        isMixedBusRegistered: (_) => false,
        isMemberConnectOwnedElsewhere: (_, _) => true,
      );

      final pending = materializer.materializeMember('sess-1', 'team-lead', '');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(connector.scheduleCalls, 0);

      materializer.markMemberReady('sess-1', 'team-lead');
      await pending;
    },
  );

  test(
    'materialize exits when its tab is removed while awaiting connect',
    () async {
      final store = ChatTabStore(storage: testHomeStorage);
      store.setActiveWorkspaceId('ws-1');
      final tab =
          ChatTab(
              info: const ChatTabInfo(
                id: 'sess-removed',
                title: 't',
                subtitle: '',
              ),
              workspaceId: 'ws-1',
              cliTeamName: 'team-runtime',
            )
            ..persistedSession = AppSession(
              sessionId: 'sess-removed',
              workspaceId: 'ws-1',
              sessionTeam: 'team-1',
              cliTeamName: 'team-runtime',
              createdAt: 0,
            );
      store.registerSession(tab);

      const team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        cli: CliTool.claude,
        teamMode: TeamMode.native,
        members: [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
      );
      final materializer = TabMemberMaterializer(
        runtime: TabSessionRuntimeCoordinator(
          tabStore: store,
          shellFactory: ChatSessionShellFactory(
            executableResolver: () => 'true',
          ),
          globalPresets: () => const [],
          activeTeam: () => team,
          isClosed: () => false,
        ),
        tabStore: store,
        connector: _RecordingConnector(),
        activeTeam: () => team,
        isClosed: () => false,
        isMixedBusRegistered: (_) => true,
        isMemberConnectOwnedElsewhere: (_, _) => true,
      );

      final pending = materializer.materializeMember(
        'sess-removed',
        'team-lead',
        '',
      );
      await Future<void>.delayed(Duration.zero);
      store.removeSession('sess-removed');

      await pending.timeout(const Duration(milliseconds: 300));
    },
  );

  test(
    'materialize resolves numbered instance ids from session roster',
    () async {
      final store = ChatTabStore(storage: testHomeStorage);
      store.setActiveWorkspaceId('ws-1');
      final tab =
          ChatTab(
              info: const ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
              workspaceId: 'ws-1',
              cliTeamName: 'team-runtime',
            )
            ..persistedSession = AppSession(
              sessionId: 'sess-1',
              workspaceId: 'ws-1',
              sessionTeam: 'team-1',
              cliTeamName: 'team-runtime',
              createdAt: 0,
              members: const [
                SessionMemberBinding(rosterMemberId: 'team-lead', taskId: 't1'),
                SessionMemberBinding(
                  rosterMemberId: 'builder-1',
                  taskId: 't2',
                  typeId: 'builder',
                ),
              ],
            );
      store.registerSession(tab);

      // In-memory team still has type ids only (replicas may even be stale).
      // Use native mode so this unit test does not wait on TeamBus install.
      const team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        cli: CliTool.claude,
        teamMode: TeamMode.native,
        members: [
          TeamMemberConfig(id: 'team-lead', name: 'Lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder', replicas: 1),
        ],
      );

      final connector = _RecordingConnector();
      final materializer = TabMemberMaterializer(
        runtime: TabSessionRuntimeCoordinator(
          tabStore: store,
          shellFactory: ChatSessionShellFactory(
            executableResolver: () => 'true',
          ),
          globalPresets: () => const [],
          activeTeam: () => team,
          isClosed: () => false,
        ),
        tabStore: store,
        connector: connector,
        activeTeam: () => team,
        isClosed: () => false,
        isMixedBusRegistered: (_) => true,
        isMemberConnectOwnedElsewhere: (_, _) => false,
      );

      final pending = materializer.materializeMember('sess-1', 'builder-1', '');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(connector.scheduleCalls, 1);
      expect(connector.lastMemberId, 'builder-1');
      expect(connector.lastSelectMember, isFalse);

      materializer.markMemberReady('sess-1', 'builder-1');
      await pending;
    },
  );

  test(
    'personal materialize hangs until markMemberReady when shell not running',
    () async {
      final store = ChatTabStore(storage: testHomeStorage);
      store.setActiveWorkspaceId('ws-1');
      final tab =
          ChatTab(
              info: const ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
              workspaceId: 'ws-1',
              cliTeamName: '',
            )
            ..persistedSession = AppSession(
              sessionId: 'sess-1',
              workspaceId: 'ws-1',
              sessionTeam: '',
              createdAt: 0,
            );
      store.registerSession(tab);

      final materializer = TabMemberMaterializer(
        runtime: TabSessionRuntimeCoordinator(
          tabStore: store,
          shellFactory: ChatSessionShellFactory(
            executableResolver: () => 'true',
          ),
          globalPresets: () => const [],
          activeTeam: () => null,
          isClosed: () => false,
        ),
        tabStore: store,
        connector: _RecordingConnector(),
        activeTeam: () => null,
        isClosed: () => false,
        isMixedBusRegistered: (_) => false,
        isMemberConnectOwnedElsewhere: (_, _) => false,
      );

      final pending = materializer.materializeMember('sess-1', 'sess-1', '');
      var completed = false;
      unawaited(pending.then((_) => completed = true));
      // Yield so materialize can park on the ready completer without wall delay.
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      materializer.markMemberReady('sess-1', 'sess-1');
      await pending;
      expect(completed, isTrue);
    },
  );

  test('personal ACP materialize completes without a shell', () async {
    final store = ChatTabStore(storage: testHomeStorage);
    store.setActiveWorkspaceId('ws-1');
    final tab =
        ChatTab(
            info: const ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
            workspaceId: 'ws-1',
            cliTeamName: '',
          )
          ..persistedSession = AppSession(
            sessionId: 'sess-1',
            workspaceId: 'ws-1',
            sessionTeam: '',
            cli: CliTool.claude,
            acp: true,
            createdAt: 0,
          );
    store.registerSession(tab);

    final materializer = TabMemberMaterializer(
      runtime: TabSessionRuntimeCoordinator(
        tabStore: store,
        shellFactory: ChatSessionShellFactory(executableResolver: () => 'true'),
        globalPresets: () => const [],
        activeTeam: () => null,
        isClosed: () => false,
      ),
      tabStore: store,
      connector: _RecordingConnector(),
      activeTeam: () => null,
      isClosed: () => false,
      isMixedBusRegistered: (_) => false,
      isMemberConnectOwnedElsewhere: (_, _) => false,
    );

    await expectLater(
      materializer
          .materializeMember('sess-1', 'sess-1', '')
          .timeout(const Duration(milliseconds: 200)),
      completes,
    );
    await expectLater(
      materializer
          .ensureMemberInputReady('sess-1', 'sess-1', directToPty: true)
          .timeout(const Duration(milliseconds: 200)),
      completes,
    );
  });

  test('input readiness exits when the session tab no longer exists', () async {
    final store = ChatTabStore(storage: testHomeStorage);
    store.setActiveWorkspaceId('ws-1');
    final materializer = TabMemberMaterializer(
      runtime: TabSessionRuntimeCoordinator(
        tabStore: store,
        shellFactory: ChatSessionShellFactory(executableResolver: () => 'true'),
        globalPresets: () => const [],
        activeTeam: () => null,
        isClosed: () => false,
      ),
      tabStore: store,
      connector: _RecordingConnector(),
      activeTeam: () => null,
      isClosed: () => false,
      isMixedBusRegistered: (_) => false,
      isMemberConnectOwnedElsewhere: (_, _) => false,
    );

    await expectLater(
      materializer
          .ensureMemberInputReady('missing-session', 'missing-member')
          .timeout(const Duration(milliseconds: 200)),
      completes,
    );
  });

  test(
    'ACP seat injectMemberStdin calls sendPrompt and skips PTY stdin',
    () async {
      final harness = _AcpSeatHarness();
      final worker = _RecordingPromptCubit(memberId: 'worker');
      harness.tab.memberAcpRuntimes['worker'] = worker;
      final before = await appLogger.getPendingLogLines();

      harness.materializer.injectMemberStdin('sess-1', 'worker', 'hello');

      final lines = (await appLogger.getPendingLogLines()).skip(before.length);
      expect(worker.prompts, ['hello']);
      expect(lines.where((line) => line.contains('pty-inject')), isEmpty);
      await worker.close();
    },
  );

  test('non-ACP member injectMemberStdin still delivers PTY stdin', () async {
    final harness = _AcpSeatHarness();
    final worker = _RecordingPromptCubit(memberId: 'worker');
    harness.tab.memberAcpRuntimes['worker'] = worker;
    final before = await appLogger.getPendingLogLines();

    harness.materializer.injectMemberStdin('sess-1', 'pty-worker', 'hello');

    final lines = (await appLogger.getPendingLogLines()).skip(before.length);
    expect(worker.prompts, isEmpty);
    expect(
      lines.where(
        (line) =>
            line.contains('pty-inject skipped no-shell') &&
            line.contains('pty-worker'),
      ),
      isNotEmpty,
    );
    await worker.close();
  });

  test(
    'ACP seat retryDelivery calls sendPrompt and skips PTY retry',
    () async {
      final harness = _AcpSeatHarness();
      final worker = _RecordingPromptCubit(memberId: 'worker');
      harness.tab.memberAcpRuntimes['worker'] = worker;
      final before = await appLogger.getPendingLogLines();

      harness.materializer.retryDelivery('sess-1', 'worker', 'ping');

      final lines = (await appLogger.getPendingLogLines()).skip(before.length);
      expect(worker.prompts, ['ping']);
      expect(
        lines.where((line) => line.contains('retry-delivery')),
        isEmpty,
      );
      await worker.close();
    },
  );

  test(
    'ACP seat ensureMemberInputReady returns when the cubit phase is ready',
    () async {
      final harness = _AcpSeatHarness();
      final worker = harness.liveCubit('worker');
      await worker.start(
        executable: 'claude',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      harness.tab.memberAcpRuntimes['worker'] = worker;
      expect(worker.state.phase, AcpChatPhase.ready);

      await harness.materializer.ensureMemberInputReady(
        'sess-1',
        'worker',
        directToPty: true,
        waitCap: const Duration(milliseconds: 400),
      );

      expect(harness.connector.scheduleCalls, 0);
      await worker.close();
      await harness.runtime.close();
    },
  );

  test(
    'ACP seat ensureMemberInputReady returns when the cubit phase is idle',
    () async {
      final harness = _AcpSeatHarness();
      final worker = harness.liveCubit('worker');
      await worker.start(
        executable: 'claude',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      harness.runtime.add(
        const AcpMessageChunk(
          role: AcpRole.assistant,
          content: 'done',
          isThought: false,
        ),
      );
      harness.runtime.add(const AcpStop(kind: AcpStopKind.endTurn));
      await pumpEventQueue();
      harness.tab.memberAcpRuntimes['worker'] = worker;
      expect(worker.state.phase, AcpChatPhase.idle);

      await harness.materializer.ensureMemberInputReady(
        'sess-1',
        'worker',
        waitCap: const Duration(milliseconds: 400),
      );

      expect(harness.connector.scheduleCalls, 0);
      await worker.close();
      await harness.runtime.close();
    },
  );

  test(
    'ACP seat ensureMemberInputReady waits until the cubit phase is ready',
    () async {
      final harness = _AcpSeatHarness();
      final worker = harness.liveCubit('worker');
      harness.tab.memberAcpRuntimes['worker'] = worker;
      expect(worker.state.phase, AcpChatPhase.launching);

      final pending = harness.materializer.ensureMemberInputReady(
        'sess-1',
        'worker',
        waitCap: const Duration(seconds: 2),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(worker.state.phase, AcpChatPhase.launching);
      await worker.start(
        executable: 'claude',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );

      await pending;
      expect(worker.state.phase, AcpChatPhase.ready);
      expect(harness.connector.scheduleCalls, 0);
      await worker.close();
      await harness.runtime.close();
    },
  );

  test(
    'ACP seat ensureMemberInputReady waits until the cubit exists',
    () async {
      final harness = _AcpSeatHarness();
      final pending = harness.materializer.ensureMemberInputReady(
        'sess-1',
        'worker',
        waitCap: const Duration(seconds: 2),
      );
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(harness.tab.memberAcpRuntimes['worker'], isNull);

      final worker = harness.liveCubit('worker');
      await worker.start(
        executable: 'claude',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      harness.tab.memberAcpRuntimes['worker'] = worker;

      await pending;
      expect(worker.state.phase, AcpChatPhase.ready);
      await worker.close();
      await harness.runtime.close();
    },
  );

  test(
    'ACP seat ensureMemberInputReady aborts when the cubit phase is ended',
    () async {
      final harness = _AcpSeatHarness();
      final worker = harness.liveCubit('worker');
      await worker.start(
        executable: 'claude',
        sessionToolDir: '/tmp/tool',
        workingDirectory: '/w',
      );
      worker.handleProcessExited(1);
      harness.tab.memberAcpRuntimes['worker'] = worker;
      expect(worker.state.phase, AcpChatPhase.ended);

      final started = DateTime.now();
      await expectLater(
        harness.materializer.ensureMemberInputReady(
          'sess-1',
          'worker',
          waitCap: const Duration(seconds: 5),
        ),
        throwsA(
          isA<MemberInputReadyException>().having(
            (e) => e.failure,
            'failure',
            MemberInputReadyFailure.dead,
          ),
        ),
      );
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 2)),
      );
      await worker.close();
      await harness.runtime.close();
    },
  );
}

class _AcpSeatHarness {
  _AcpSeatHarness() {
    store.setActiveWorkspaceId('ws-1');
    tab.persistedSession = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws-1',
      sessionTeam: 'team-1',
      cliTeamName: 'team-runtime',
      createdAt: 0,
      members: const [
        SessionMemberBinding(
          rosterMemberId: 'worker',
          taskId: 't1',
          cli: CliTool.claude,
          acp: true,
        ),
        SessionMemberBinding(
          rosterMemberId: 'pty-worker',
          taskId: 't2',
          cli: CliTool.claude,
        ),
      ],
    );
    store.registerSession(tab);
    materializer = TabMemberMaterializer(
      runtime: TabSessionRuntimeCoordinator(
        tabStore: store,
        shellFactory: ChatSessionShellFactory(executableResolver: () => 'true'),
        globalPresets: () => const [],
        activeTeam: () => null,
        isClosed: () => false,
      ),
      tabStore: store,
      connector: connector,
      activeTeam: () => null,
      isClosed: () => false,
      isMixedBusRegistered: (_) => false,
      isMemberConnectOwnedElsewhere: (_, _) => true,
    );
  }

  final store = ChatTabStore(storage: testHomeStorage);
  final connector = _RecordingConnector();
  final runtime = _StubAcpRuntime();
  final tab = ChatTab(
    info: const ChatTabInfo(id: 'sess-1', title: 't', subtitle: ''),
    workspaceId: 'ws-1',
    cliTeamName: 'team-runtime',
  );
  late final TabMemberMaterializer materializer;

  AcpChatRuntimeCubit liveCubit(String memberId) {
    return AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: 'sess-1',
      tool: CliTool.claude,
      seatMemberId: memberId,
    );
  }
}

class _RecordingPromptCubit extends AcpChatRuntimeCubit {
  _RecordingPromptCubit({required String memberId})
    : super(
        runtime: _StubAcpRuntime(),
        sessionId: 'sess-1',
        tool: CliTool.claude,
        seatMemberId: memberId,
      );

  final prompts = <String>[];

  @override
  bool sendPrompt(String text) {
    prompts.add(text);
    return true;
  }
}

class _StubAcpRuntime implements AcpSessionRuntimeApi {
  final updatesController = StreamController<AcpSessionUpdate>.broadcast();
  var started = false;

  void add(AcpSessionUpdate update) => updatesController.add(update);

  @override
  Future<void> start({
    required CliTool tool,
    required String executable,
    required String sessionToolDir,
    required String workingDirectory,
    Map<String, String> baseEnv = const {},
    List<acpd.McpServer> mcpServers = const [],
  }) async {
    started = true;
  }

  @override
  bool get isStarted => started;

  @override
  String get sessionId => 'acp-session-1';

  @override
  Future<void> prompt(String text) async {}

  @override
  Stream<AcpSessionUpdate> get updates => updatesController.stream;

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
  Future<void> close() async {
    if (!updatesController.isClosed) await updatesController.close();
  }
}
