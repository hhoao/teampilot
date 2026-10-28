import 'dart:async';

import 'package:acpd/acpd.dart' as acpd;
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/session/acp/acp_chat_runtime_cubit.dart';
import 'package:teampilot/services/acp/acp_chat_strings.dart';
import 'package:teampilot/services/acp/acp_client_extensions.dart';
import 'package:teampilot/services/acp/acp_session.dart';
import 'package:teampilot/services/acp/acp_session_runtime.dart';
import 'package:teampilot/services/agent_status/agent_permission_request.dart';
import 'package:teampilot/services/chat/session/chat_tab_store.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/chat/runtime/session_activity_aggregator.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_activity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/chat/session/session_working_resolver.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../support/in_memory_filesystem.dart';

const _testAcpStrings = AcpChatStrings(
  launchFailedVersion: 'v',
  launchFailedAdapter: 'a',
  launchFailed: 'l',
  turnFailed: 't',
  processExited: 'x',
  notLoggedIn: 'Not logged in',
);

void main() {
  SessionActivityAggregator aggregator({
    required ChatTabStore store,
    bool Function(String sessionId)? deliveryInFlight,
    bool Function(String sessionId)? attention,
  }) {
    return SessionActivityAggregator(
      tabStore: store,
      sessionWorking: SessionWorkingResolver(),
      globalPresets: () => const [],
      activeTeam: () => null,
      activeSessionId: () => null,
      presence: () => const {},
      sessionBusyFromAttention: attention,
      sessionBusyFromDeliveryInFlight: deliveryInFlight,
    );
  }

  test('delivery in-flight alone yields delivering only, not inTurn', () {
    final store = ChatTabStore(storage: fakeHomeStorage());
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
        cliTeamName: 'ct',
      ),
    );
    final reasons = aggregator(
      store: store,
      deliveryInFlight: (id) => id == 'sess',
    ).computeReasons();
    expect(reasons['sess'], {SessionBusyReason.delivering});
    expect(reasons['sess']!.contains(SessionBusyReason.inTurn), isFalse);
  });

  test(
    'clearing delivery in-flight with no other busy yields empty reasons',
    () {
      final store = ChatTabStore(storage: fakeHomeStorage());
      store.registerSession(
        ChatTab(
          info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
          cliTeamName: 'ct',
        ),
      );
      expect(
        aggregator(
          store: store,
          deliveryInFlight: (_) => false,
        ).computeReasons()['sess'],
        isEmpty,
      );
    },
  );

  test('attention busy alone yields attention only', () {
    final store = ChatTabStore(storage: fakeHomeStorage());
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
        cliTeamName: 'ct',
      ),
    );
    final reasons = aggregator(
      store: store,
      attention: (id) => id == 'sess',
    ).computeReasons();
    expect(reasons['sess'], {SessionBusyReason.attention});
  });

  test('delivery and attention together yield both, not inTurn', () {
    final store = ChatTabStore(storage: fakeHomeStorage());
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'sess', title: 't', subtitle: 's'),
        cliTeamName: 'ct',
      ),
    );
    final reasons = aggregator(
      store: store,
      attention: (id) => id == 'sess',
      deliveryInFlight: (id) => id == 'sess',
    ).computeReasons();
    expect(reasons['sess'], {
      SessionBusyReason.delivering,
      SessionBusyReason.attention,
    });
    expect(reasons['sess']!.contains(SessionBusyReason.inTurn), isFalse);
  });

  ChatTab personalInTurnTab() {
    final shell = _ConnectedShell()
      ..activityTracker.latchBootFrameReadyForTest(
        DateTime.now().subtract(const Duration(seconds: 5)),
      )
      ..markUserTurnStarted();

    return ChatTab(
        info: const ChatTabInfo(id: 'personal-1', title: 'P', subtitle: ''),
        cliTeamName: '',
      )
      ..persistedSession = AppSession(
        sessionId: 'personal-1',
        workspaceId: 'ws',
        folders: const [],
        createdAt: 0,
      )
      ..memberShells['agent'] = shell;
  }

  test('inTurn from member working yields inTurn only', () {
    final store = ChatTabStore(storage: fakeHomeStorage());
    store.registerSession(personalInTurnTab());
    expect(aggregator(store: store).computeReasons()['personal-1'], {
      SessionBusyReason.inTurn,
    });
  });

  test('all three reasons when inTurn plus attention and delivery', () {
    final store = ChatTabStore(storage: fakeHomeStorage());
    store.registerSession(personalInTurnTab());
    final reasons = aggregator(
      store: store,
      attention: (id) => id == 'personal-1',
      deliveryInFlight: (id) => id == 'personal-1',
    ).computeReasons();
    expect(reasons['personal-1'], {
      SessionBusyReason.delivering,
      SessionBusyReason.inTurn,
      SessionBusyReason.attention,
    });
  });

  test('two tabs: idle and delivering both appear in map', () {
    final store = ChatTabStore(storage: fakeHomeStorage());
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'idle', title: 'i', subtitle: ''),
        cliTeamName: 'ct',
      ),
    );
    store.registerSession(
      ChatTab(
        info: const ChatTabInfo(id: 'busy', title: 'b', subtitle: ''),
        cliTeamName: 'ct',
      ),
    );
    final reasons = aggregator(
      store: store,
      deliveryInFlight: (id) => id == 'busy',
    ).computeReasons();
    expect(reasons.containsKey('idle'), isTrue);
    expect(reasons['idle'], isEmpty);
    expect(reasons.containsKey('busy'), isTrue);
    expect(reasons['busy'], {SessionBusyReason.delivering});
  });

  ChatTab personalAcpTab() {
    final tab = ChatTab(
      info: const ChatTabInfo(id: 'acp-1', title: 'A', subtitle: ''),
      cliTeamName: '',
    );
    tab.persistedSession = AppSession(
      sessionId: 'acp-1',
      workspaceId: 'ws',
      folders: const [],
      createdAt: 0,
      acp: true,
    );
    tab.acpRuntime = AcpChatRuntimeCubit(
      runtime: _StubAcpRuntime(),
      sessionId: 'acp-1',
      tool: CliTool.gemini,
    )..ensureStrings(_testAcpStrings);
    return tab;
  }

  test('live ACP turn stays busy after the attention TTL expired', () {
    final store = ChatTabStore(storage: fakeHomeStorage());
    final tab = personalAcpTab();
    // Terminal-less seat: no memberShell, so only the runtime knows about it.
    tab.acpRuntime!.sendPrompt('long task');
    expect(tab.acpRuntime!.state.inTurn, isTrue);
    store.registerSession(tab);

    final reasons = aggregator(
      store: store,
      // The attention stamp is written once per turn and dropped after 30 min;
      // a longer ACP turn must still read as working.
      attention: (_) => false,
    ).computeReasons();

    expect(reasons['acp-1'], {SessionBusyReason.inTurn});
  });

  test('ACP runtime parked outside a turn does not mark the session busy', () {
    final store = ChatTabStore(storage: fakeHomeStorage());
    store.registerSession(personalAcpTab());
    expect(aggregator(store: store).computeReasons()['acp-1'], isEmpty);
  });

  test('ended ACP runtime does not mark the session busy', () async {
    final store = ChatTabStore(storage: fakeHomeStorage());
    final tab = personalAcpTab();
    tab.acpRuntime!.sendPrompt('long task');
    tab.acpRuntime!.handleProcessExited(1);
    store.registerSession(tab);
    expect(aggregator(store: store).computeReasons()['acp-1'], isEmpty);
  });
}

/// Minimal all-stub [AcpSessionRuntimeApi] so the aggregator tests can build a
/// live [AcpChatRuntimeCubit] (copied from chat_tab_acp_runtimes_test).
class _StubAcpRuntime implements AcpSessionRuntimeApi {
  final updatesController = StreamController<AcpSessionUpdate>.broadcast();
  final permissionsController =
      StreamController<AgentPermissionRequest>.broadcast();
  final clientRequestsController =
      StreamController<AcpPendingClientRequest>.broadcast();

  bool closed = false;
  Completer<int>? agentExit;

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
  }) async {}

  @override
  void setPermissionPolicy(LaunchSecurityPolicy policy) {}

  @override
  bool get isStarted => false;

  @override
  String get sessionId => 'acp-session-1';

  @override
  Future<void> prompt(String text) async {}

  @override
  Stream<AcpSessionUpdate> get updates => updatesController.stream;

  @override
  Stream<AgentPermissionRequest> get permissionRequests =>
      permissionsController.stream;

  @override
  Stream<AcpPendingClientRequest> get clientRequests =>
      clientRequestsController.stream;

  @override
  AcpAuthNotice? lastAuthNotice;

  @override
  Future<int>? get agentProcessExitCode => agentExit?.future;

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

class _ConnectedShell extends TerminalSession {
  _ConnectedShell() : super(executable: 'true', fs: InMemoryFilesystem());

  @override
  bool get isRunning => true;

  @override
  bool get isConnected => true;

  @override
  void dispose() {}
}
