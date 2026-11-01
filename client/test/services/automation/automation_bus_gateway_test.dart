import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/automation/automation_bus_gateway.dart';
import 'package:teampilot/services/chat/launch/session/member_input_ready_wait.dart';
import 'package:teampilot/services/chat/launch/session/tab_member_materializer.dart';
import 'package:teampilot/services/chat/runtime/tab_session_runtime_coordinator.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late List<AcpChatRuntimeCubit> cubits;
  late List<_FakeAcpRuntime> runtimes;

  setUp(() {
    cubits = [];
    runtimes = [];
  });

  tearDown(() async {
    for (final cubit in cubits) {
      if (!cubit.isClosed) await cubit.close();
    }
    for (final runtime in runtimes) {
      await runtime.updatesController.close();
      await runtime.permissionsController.close();
    }
  });

  ({
    AcpChatRuntimeCubit cubit,
    _FakeAcpRuntime runtime,
    ChatTabStore store,
    ChatTab tab,
  })
  startedPersonal({bool attach = true}) {
    final session = _personalAcpSession();
    final tab = _tabFor(session);
    final store = _storeWith(tab);
    final runtime = _FakeAcpRuntime();
    runtimes.add(runtime);
    final cubit = AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: session.sessionId,
      tool: CliTool.claude,
    );
    cubits.add(cubit);
    if (attach) tab.acpRuntime = cubit;
    return (cubit: cubit, runtime: runtime, store: store, tab: tab);
  }

  Future<void> start(AcpChatRuntimeCubit cubit) => cubit.start(
    executable: 'claude-agent-acp',
    sessionToolDir: '/runtime/claude',
    workingDirectory: '/work',
  );

  test('no open tab yields tab_unavailable without side effects', () async {
    final materializer = _FakeMaterializer();
    final sessionRuntime = _FakeRuntime();
    var personalActivations = 0;
    var memberActivations = 0;

    final gateway = TabTeamBusGateway(
      memberMaterializer: materializer,
      sessionRuntime: sessionRuntime,
      tabStore: ChatTabStore(storage: fakeHomeStorage()),
      activatePersonalAcp: (sessionId) async => personalActivations++,
      activateMemberSeat: (sessionId, memberId) async => memberActivations++,
    );

    final outcome = await gateway.deliverUserCommandToMember(
      _personalAcpSession(),
      'sess-acp',
      'hello',
    );

    expect(outcome.delivered, isFalse);
    expect(outcome.reason, 'tab_unavailable');
    expect(personalActivations, 0);
    expect(memberActivations, 0);
    expect(sessionRuntime.ptyCalls, isEmpty);
    expect(materializer.ensureCalls, isEmpty);
  });

  test('personal ACP with an attached runtime sends through the cubit', () async {
    final built = startedPersonal();
    await start(built.cubit);
    var personalActivations = 0;
    var memberActivations = 0;
    final sessionRuntime = _FakeRuntime();

    final gateway = TabTeamBusGateway(
      memberMaterializer: _FakeMaterializer(),
      sessionRuntime: sessionRuntime,
      tabStore: built.store,
      activatePersonalAcp: (sessionId) async => personalActivations++,
      activateMemberSeat: (sessionId, memberId) async => memberActivations++,
    );

    final outcome = await gateway.deliverUserCommandToMember(
      _personalAcpSession(),
      'sess-acp',
      'hello',
    );
    await Future<void>.delayed(Duration.zero);

    expect(outcome.delivered, isTrue);
    expect(built.runtime.prompts, ['hello']);
    expect(sessionRuntime.ptyCalls, isEmpty);
    expect(personalActivations, 0);
    expect(memberActivations, 0);
  });

  test('personal ACP with no runtime activates once, then delivers', () async {
    final built = startedPersonal(attach: false);
    await start(built.cubit);
    var personalActivations = 0;
    final sessionRuntime = _FakeRuntime();

    final gateway = TabTeamBusGateway(
      memberMaterializer: _FakeMaterializer(),
      sessionRuntime: sessionRuntime,
      tabStore: built.store,
      activatePersonalAcp: (sessionId) async {
        personalActivations++;
        built.tab.acpRuntime = built.cubit;
      },
    );

    final outcome = await gateway.deliverUserCommandToMember(
      _personalAcpSession(),
      'sess-acp',
      'hello',
    );
    await Future<void>.delayed(Duration.zero);

    expect(outcome.delivered, isTrue);
    expect(personalActivations, 1);
    expect(built.runtime.prompts, ['hello']);
    expect(sessionRuntime.ptyCalls, isEmpty);
  });

  test('mixed ACP seat activates the member seat and uses its cubit', () async {
    final session = _mixedSession(acp: true);
    final tab = _tabFor(session);
    final store = _storeWith(tab);
    final runtime = _FakeAcpRuntime();
    runtimes.add(runtime);
    final cubit = AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: session.sessionId,
      tool: CliTool.cursor,
    );
    cubits.add(cubit);
    await cubit.start(
      executable: 'cursor-agent-acp',
      sessionToolDir: '/runtime/cursor',
      workingDirectory: '/work',
    );
    var personalActivations = 0;
    var memberActivations = 0;
    final sessionRuntime = _FakeRuntime();

    final gateway = TabTeamBusGateway(
      memberMaterializer: _FakeMaterializer(),
      sessionRuntime: sessionRuntime,
      tabStore: store,
      activatePersonalAcp: (sessionId) async => personalActivations++,
      activateMemberSeat: (sessionId, memberId) async {
        memberActivations++;
        tab.memberAcpRuntimes[memberId] = cubit;
      },
    );

    final outcome = await gateway.deliverUserCommandToMember(
      session,
      'builder-1',
      'hello',
    );
    await Future<void>.delayed(Duration.zero);

    expect(outcome.delivered, isTrue);
    expect(memberActivations, 1);
    expect(personalActivations, 0);
    expect(runtime.prompts, ['hello']);
    expect(sessionRuntime.ptyCalls, isEmpty);
  });

  test('mixed PTY seat uses the PTY seam and never activates ACP', () async {
    final session = _mixedSession(acp: false);
    final tab = _tabFor(session);
    final store = _storeWith(tab);
    var personalActivations = 0;
    var memberActivations = 0;
    final sessionRuntime = _FakeRuntime();

    final gateway = TabTeamBusGateway(
      memberMaterializer: _FakeMaterializer(),
      sessionRuntime: sessionRuntime,
      tabStore: store,
      activatePersonalAcp: (sessionId) async => personalActivations++,
      activateMemberSeat: (sessionId, memberId) async => memberActivations++,
    );

    final outcome = await gateway.deliverUserCommandToMember(
      session,
      'builder-1',
      'hello',
    );

    expect(outcome.delivered, isTrue);
    expect(sessionRuntime.ptyCalls, [
      ('sess-mixed', 'builder-1', 'hello'),
    ]);
    expect(personalActivations, 0);
    expect(memberActivations, 0);
  });
}

AppSession _personalAcpSession() => AppSession(
  sessionId: 'sess-acp',
  workspaceId: 'ws',
  cli: CliTool.claude,
  acp: true,
  createdAt: 1,
);

AppSession _mixedSession({required bool acp}) => AppSession(
  sessionId: 'sess-mixed',
  workspaceId: 'ws',
  sessionTeam: 'team-1',
  members: [
    SessionMemberBinding(
      rosterMemberId: 'builder-1',
      typeId: 'builder',
      taskId: 'task-builder-1',
      cli: CliTool.cursor,
      acp: acp,
    ),
  ],
  createdAt: 1,
);

ChatTab _tabFor(AppSession session) {
  final tab = ChatTab(
    info: ChatTabInfo(
      id: session.sessionId,
      title: 'session',
      subtitle: 'session',
    ),
    cliTeamName: '',
  );
  tab.persistedSession = session;
  return tab;
}

ChatTabStore _storeWith(ChatTab tab) {
  final store = ChatTabStore(storage: fakeHomeStorage());
  store.registerSession(tab);
  return store;
}

class _FakeMaterializer implements TabMemberMaterializer {
  final ensureCalls = <(String, String)>[];

  @override
  Future<void> ensureMemberInputReady(
    String sessionId,
    String memberId, {
    bool directToPty = false,
    Duration waitCap = defaultMemberInputReadyCap,
    bool Function()? aborted,
  }) async {
    ensureCalls.add((sessionId, memberId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRuntime implements TabSessionRuntimeCoordinator {
  final ptyCalls = <(String, String, String)>[];

  @override
  Future<String?> deliverUserCommandToMember(
    String sessionId,
    String memberId,
    String message, {
    bool directToPty = false,
  }) async {
    ptyCalls.add((sessionId, memberId, message));
    return 'delivery-1';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAcpRuntime implements AcpSessionRuntimeApi {
  final updatesController = StreamController<AcpSessionUpdate>.broadcast();
  final permissionsController =
      StreamController<AgentPermissionRequest>.broadcast();
  final prompts = <String>[];
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
  String get sessionId => 'acp-1';

  @override
  Future<void> prompt(String text) async => prompts.add(text);

  @override
  Stream<AcpSessionUpdate> get updates => updatesController.stream;

  @override
  Stream<AgentPermissionRequest> get permissionRequests =>
      permissionsController.stream;

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
