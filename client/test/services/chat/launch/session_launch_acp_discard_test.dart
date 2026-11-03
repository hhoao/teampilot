import 'dart:async';
import 'dart:typed_data';

import 'package:acpd/acpd.dart' as acpd;
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/chat/launch/connect/chat_session_shell_factory.dart';
import 'package:teampilot/services/chat/launch/session/tab_member_materializer.dart';
import 'package:teampilot/services/chat/launch/session_launch_service.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/ssh/ssh_member_session.dart';

import '../../../support/in_memory_filesystem.dart';
import '../../../support/stub_tab_member_materializer.dart';

void main() {
  test('discardAcpSeat closes the cubit and marks it reclaimed', () async {
    final tabStore = ChatTabStore(storage: fakeHomeStorage())
      ..setActiveWorkspaceId('w1');
    final tab = ChatTab(
      info: ChatTabInfo(id: 'sess', title: 'S', subtitle: ''),
      cliTeamName: '',
    );
    tabStore.registerSession(tab);
    final host = _Host(tabStore);
    final service = SessionLaunchService(host, storage: fakeHomeStorage());

    final readyCubit = await _readyCubit();
    tab.memberAcpRuntimes['worker-1'] = readyCubit;
    tab.membersPendingConnect.add('worker-1');
    tab.memberSshSessions['worker-1'] = SshMemberSession.testing(
      profile: const SshProfile(
        id: 'p1',
        name: 'host',
        host: 'host',
        username: 'u',
        authType: SshAuthType.password,
      ),
      client: _InstantAuthClient(),
    );

    service.discardAcpSeat('sess', 'worker-1');

    expect(tab.memberAcpRuntimes.containsKey('worker-1'), isFalse);
    expect(tab.membersPendingConnect.contains('worker-1'), isFalse);
    expect(tab.reclaimedMemberIds, contains('worker-1'));
    expect(host.clearedLaunchError, contains('sess'));
    expect(host.updatedTabRunning, contains('sess'));

    await pumpEventQueue();
    expect(readyCubit.isClosed, isTrue);
    expect(
      tab.memberSshSessions.containsKey('worker-1'),
      isFalse,
      reason: 'a reclaimed remote ACP seat must not leak its SSH plane',
    );
  });

  test('discardPersonalAcpRuntime closes the personal cubit and marks it reclaimed',
      () async {
    final tabStore = ChatTabStore(storage: fakeHomeStorage())
      ..setActiveWorkspaceId('w1');
    final tab = ChatTab(
      info: ChatTabInfo(id: 'sess', title: 'S', subtitle: ''),
      cliTeamName: '',
    );
    tab.persistedSession = AppSession(
      sessionId: 'sess',
      workspaceId: 'w1',
      createdAt: 1,
      sessionTeam: '',
      acp: true,
    );
    tabStore.registerSession(tab);
    final host = _Host(tabStore);
    final service = SessionLaunchService(host, storage: fakeHomeStorage());

    final cubit = await _readyCubit();
    tab.acpRuntime = cubit;

    service.discardPersonalAcpRuntime('sess');

    expect(tab.acpRuntime, isNull);
    expect(tab.reclaimedAcpRuntime, isTrue);
    expect(host.clearedLaunchError, contains('sess'));
    expect(host.updatedTabRunning, contains('sess'));

    await pumpEventQueue();
    expect(cubit.isClosed, isTrue);
  });

  test('discardPersonalAcpRuntime is a no-op for non-ACP / missing tabs',
      () async {
    final tabStore = ChatTabStore(storage: fakeHomeStorage())
      ..setActiveWorkspaceId('w1');
    final service = SessionLaunchService(
      _Host(tabStore),
      storage: fakeHomeStorage(),
    );

    service.discardPersonalAcpRuntime('');
    service.discardPersonalAcpRuntime('missing');

    // Team tab (not personal ACP) is never touched by this path.
    final team = ChatTab(
      info: ChatTabInfo(id: 'sess', title: 'S', subtitle: ''),
      cliTeamName: '',
    );
    team.persistedSession = AppSession(
      sessionId: 'sess',
      workspaceId: 'w1',
      createdAt: 1,
      sessionTeam: 't',
    );
    tabStore.registerSession(team);
    team.acpRuntime = await _readyCubit();

    service.discardPersonalAcpRuntime('sess');

    expect(team.acpRuntime, isNotNull);
    expect(team.reclaimedAcpRuntime, isFalse);
  });

  test('discardAcpSeat is a no-op for blank ids / missing tab / missing cubit',
      () async {
    final tabStore = ChatTabStore(storage: fakeHomeStorage())
      ..setActiveWorkspaceId('w1');
    final service = SessionLaunchService(_Host(tabStore), storage: fakeHomeStorage());

    // No tab, blank ids, missing member — all must return without throwing.
    service.discardAcpSeat('', '');
    service.discardAcpSeat('sess', '');
    service.discardAcpSeat('', 'worker-1');
    service.discardAcpSeat('missing', 'worker-1');

    final tab = ChatTab(
      info: ChatTabInfo(id: 'sess', title: 'S', subtitle: ''),
      cliTeamName: '',
    );
    tabStore.registerSession(tab);
    service.discardAcpSeat('sess', 'missing-cubit');
    expect(tab.reclaimedMemberIds, isEmpty);
  });
}

Future<AcpChatRuntimeCubit> _readyCubit() async {
  final cubit = AcpChatRuntimeCubit(
    runtime: _FakeAcpRuntime(),
    sessionId: 'sess',
    tool: CliTool.gemini,
  );
  await cubit.start(
    executable: 'gemini',
    sessionToolDir: '/tmp/tool',
    workingDirectory: '/w',
  );
  return cubit;
}

class _Host implements SessionLaunchHost {
  _Host(this.tabStore) : memberMaterializer = stubTabMemberMaterializer(tabStore);

  @override
  final ChatTabStore tabStore;

  @override
  final TabMemberMaterializer memberMaterializer;

  final List<String> clearedLaunchError = [];
  final List<String> updatedTabRunning = [];

  @override
  bool get isClosed => false;

  @override
  ChatSessionShellFactory get shellFactory =>
      ChatSessionShellFactory(executableResolver: () => '/usr/bin/claude');

  @override
  CliToolRegistry get cliRegistry => CliToolRegistry.builtIn();

  @override
  void updateTabRunning(String tabId) => updatedTabRunning.add(tabId);

  @override
  void finishSessionConnect(String sessionId) {}

  @override
  void clearLaunchError(String sessionId) => clearedLaunchError.add(sessionId);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isGetter || invocation.isSetter) return null;
    return super.noSuchMethod(invocation);
  }
}

class _FakeAcpRuntime implements AcpSessionRuntimeApi {
  bool started = false;
  bool closed = false;

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
  Future<void> close() async {
    closed = true;
  }
}

class _InstantAuthClient extends SSHClient {
  _InstantAuthClient() : super(_FakeSSHSocket(), username: 'test');

  @override
  Future<void> get authenticated => Future.value();

  @override
  Future<void> ping() async {}

  @override
  Future<void> disconnect() async {}
}

class _FakeSSHSocket implements SSHSocket {
  final _inputController = StreamController<Uint8List>();
  final _doneCompleter = Completer<void>();

  @override
  Stream<Uint8List> get stream => _inputController.stream;

  @override
  StreamSink<List<int>> get sink => _NoopSink();

  @override
  Future<void> get done => _doneCompleter.future;

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    await _inputController.close();
  }

  @override
  void destroy() {
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
    unawaited(_inputController.close());
  }
}

class _NoopSink implements StreamSink<List<int>> {
  @override
  void add(List<int> data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final _ in stream) {}
  }

  @override
  Future<void> close() async {}

  @override
  Future<void> get done async {}
}
