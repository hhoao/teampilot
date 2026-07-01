import 'dart:io';

import 'package:mock_anthropic/scenario.dart';
import 'package:mock_anthropic/scenarios/ping_pong_mixed_claude.dart';
import 'package:mock_anthropic/scenarios/task_dispatch_mixed_claude.dart';
import 'package:mock_anthropic/server.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/repositories/ssh_known_host_repository.dart';
import 'package:teampilot/repositories/ssh_profile_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/launch/launch_factory.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context_registry.dart';
import 'package:teampilot/services/storage/runtime_context_resolver.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/team_bus/mcp/bus_bridge_locator.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_server.dart';
import 'package:teampilot/services/team_bus/remote/remote_bus_binding_resolver.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';

import '../../support/post_frame_test_harness.dart';
import 'bus_mail_assertions.dart';
import 'bus_roster_assertions.dart';
import 'bus_task_assertions.dart';
import 'docker_ssh_server.dart';
import 'integration_prerequisites.dart';

const kItMixedClaudeTeamId = 'it-mixed-claude';
const kMockLeaderProviderId = 'mock-leader';
const kMockWorkerProviderId = 'mock-worker';

const kLeadMember = TeamMemberConfig(
  id: 'team-lead',
  name: 'team-lead',
  provider: kMockLeaderProviderId,
);

const kWorkerMember = TeamMemberConfig(
  id: 'worker-1',
  name: 'developer',
  provider: kMockWorkerProviderId,
);

const kItMixedClaudeTeam = TeamProfile(
  id: kItMixedClaudeTeamId,
  name: 'IT Mixed Claude',
  cli: CliTool.claude,
  teamMode: TeamMode.mixed,
  members: [kLeadMember, kWorkerMember],
);

/// Orchestrator for L2 ChatCubit + mock Anthropic integration tests.
class MixedTeamIntegrationHarness {
  MixedTeamIntegrationHarness({required this.claudePath});

  final String claudePath;

  MockAnthropicServer? _mockServer;
  ChatCubit? cubit;

  String? _savedBusBridgeEnv;
  bool _envOverrideApplied = false;

  String get mockBaseUrl => _mockServer!.baseUri.toString();

  int get mockPort => _mockServer!.port;

  /// True when `libflutter_pty` is on the loader path (e.g. after `flutter build linux`).
  static bool get nativePtyAvailable =>
      IntegrationPrerequisites.nativePtyAvailable;

  /// Resolves `claude` on PATH, or null when not installed.
  static String? resolveClaudePath() =>
      IntegrationPrerequisites.resolveClaudePath();

  Future<void> startMockServer({
    ScenarioRegistry? scenarios,
    bool exposeToDocker = false,
  }) async {
    _forceHttpMcp();
    final server = MockAnthropicServer(
      scenarios: scenarios ?? pingPongMixedClaudeScenarios(),
    );
    _mockServer = server;
    await server.start(
      address: exposeToDocker ? InternetAddress.anyIPv4 : null,
    );
  }

  Future<void> writeMockProviders({String? workerBaseUrl}) async {
    final port = _mockServer!.port;
    final leaderUrl = workerBaseUrl != null
        ? 'http://127.0.0.1:$port'
        : mockBaseUrl;
    final remoteWorkerUrl = workerBaseUrl ?? leaderUrl;
    await AppProviderRepository(
      basePath: AppStorage.paths.basePath,
    ).saveProviders(CliTool.claude, [
      AppProviderConfig(
        id: kMockLeaderProviderId,
        cli: CliTool.claude,
        name: 'Mock Leader',
        baseUrl: leaderUrl,
        apiKey: leadScriptApiKey,
        defaultModel: 'mock-model',
      ),
      AppProviderConfig(
        id: kMockWorkerProviderId,
        cli: CliTool.claude,
        name: 'Mock Worker',
        baseUrl: remoteWorkerUrl,
        apiKey: workerScriptApiKey,
        defaultModel: 'mock-model',
      ),
    ]);
  }

  ChatCubit createCubit({required PostFrameTestHarness postFrame}) {
    final created = ChatCubit(
      executableResolver: () => claudePath,
      cliExecutableResolver: (_) => claudePath,
      postFrameScheduler: postFrame.scheduler,
      autoLaunchAllMembersOnConnect: () => true,
      sessionRepository: SessionRepository(),
      lifecycleService: SessionLifecycleService(
        appDataBasePath: AppStorage.paths.basePath,
      ),
    );
    cubit = created;
    return created;
  }

  /// Full ChatCubit wiring for local-lead + Docker-SSH-worker mixed teams.
  ChatCubit createDockerCubit({
    required PostFrameTestHarness postFrame,
    required MixedTeamDockerRemote remote,
  }) {
    final registry = remote.contextRegistry;
    final profileById = remote.sshProfileById;
    final lifecycle = SessionLifecycleService(
      appDataBasePath: AppStorage.paths.basePath,
      workContextResolver: registry.forTarget,
    );
    final created = ChatCubit(
      executableResolver: () => claudePath,
      cliExecutableResolver: (_) => claudePath,
      postFrameScheduler: postFrame.scheduler,
      autoLaunchAllMembersOnConnect: () => true,
      sessionRepository: SessionRepository(),
      lifecycleService: lifecycle,
      transportFactory: TerminalTransportFactory(
        sshProfileRepository: remote.sshProfileRepository,
        sshCredentialStore: remote.credentialStore,
        sshKnownHostRepository: remote.knownHostRepository,
        sshClientFactory: remote.sshClientFactory,
      ),
      sshProfileById: profileById,
      defaultTargetResolver: RuntimeTarget.local,
      remoteBusResolver: RemoteBusBindingResolver(
        registry: CliToolRegistry.builtIn(),
      ),
      sessionConnect: buildSessionConnectOrchestrator(
        lifecycle: lifecycle,
        registry: CliToolRegistry.builtIn(),
        sshClientFactory: remote.sshClientFactory,
        profileById: profileById,
        contextForTarget: registry.forTarget,
        homeContext: registry.home,
        homeTarget: RuntimeTarget.local,
        isCredentialOptIn: (_) async => false,
        isInstallOptIn: (_) async => true,
        cliPathOverride: (_, __) async => null,
        setCliPathOverride: (_, __, ___) async {},
        loadLocalCredentials: (_) async => const [],
        localCliPath: (_) async => claudePath,
      ),
    );
    cubit = created;
    return created;
  }

  /// Same as L2; remote SSH worker may need slightly longer to settle.
  Future<void> waitUntilDockerMembersReady(
    ChatCubit cubit,
    List<String> memberIds,
  ) => waitUntilMembersReady(
    cubit,
    memberIds,
    minWarmup: const Duration(seconds: 30),
    settleTimeout: const Duration(seconds: 90),
  );

  /// Worker must enter `wait_for_message` before the leader sends ping.
  Future<void> kickoffAndWaitForPingPong({
    required ChatCubit cubit,
    required String workspaceId,
    required String sessionId,
    PostFrameTestHarness? postFrame,
    Duration workerReadyTimeout = const Duration(seconds: 60),
    Duration busTimeout = const Duration(seconds: 30),
  }) async {
    _resetMockScenarios();
    final workerBaseline = _mockRequestCount(workerScriptApiKey);
    await _submitWorkerKickoff(cubit);
    final workerInLoop = await _waitForNewMockRequest(
      workerScriptApiKey,
      afterCount: workerBaseline,
      timeout: workerReadyTimeout,
    );
    if (!workerInLoop) {
      throw StateError(
        'Remote worker never entered mock API idle loop '
        '(expected $workerScriptApiKey request)',
      );
    }
    await waitUntilWorkerParked(
      bus: _busForSession(cubit, sessionId),
      mcpServer: _mcpForSession(cubit, sessionId),
      memberId: kWorkerMember.id,
      timeout: workerReadyTimeout,
    );
    await _submitLeaderKickoff(cubit, postFrame: postFrame);
    await waitForPingPong(
      workspaceId: workspaceId,
      sessionId: sessionId,
      timeout: busTimeout,
    );
  }

  /// Remote worker parks on `wait_for_message` before leader `add_tasks`.
  Future<void> kickoffAndWaitForTaskDispatch({
    required ChatCubit cubit,
    required String workspaceId,
    required String sessionId,
    required String title,
    PostFrameTestHarness? postFrame,
    String workerKickoff = taskDispatchWorkerKickoff,
    String leaderKickoff = taskDispatchLeaderKickoff,
    Duration workerReadyTimeout = const Duration(seconds: 90),
    Duration busTimeout = const Duration(seconds: 90),
  }) async {
    await kickoffWorkerParkedThenLeader(
      cubit,
      sessionId: sessionId,
      postFrame: postFrame,
      workerKickoff: workerKickoff,
      leaderKickoff: leaderKickoff,
      workerReadyTimeout: workerReadyTimeout,
    );
    await waitForTaskDispatched(
      workspaceId: workspaceId,
      sessionId: sessionId,
      title: title,
      timeout: busTimeout,
    );
  }

  Future<void> verifyMockReachableFromDocker(
    MixedTeamDockerRemote remote,
  ) async {
    final client = await remote.sshClientFactory.clientForStorage(
      remote.profile,
    );
    final url = 'http://${DockerSshServer.hostGatewayHostname}:$mockPort/';
    final out = await client.run(
      'wget -q -O /dev/null --timeout=5 $url 2>/dev/null; echo \$?',
    );
    final code = String.fromCharCodes(out).trim();
    if (code != '0' && code != '8') {
      throw StateError(
        'Docker worker host cannot reach mock API at $url (wget exit $code)',
      );
    }
  }

  Future<void> waitUntilMembersRunning(
    ChatCubit cubit,
    List<String> memberIds, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (memberIds.every(cubit.isMemberRunning)) {
        return;
      }
      await drainPendingAsyncWork();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(
      'Timed out waiting for members to run: '
      '${memberIds.where((id) => !cubit.isMemberRunning(id)).join(', ')}',
    );
  }

  /// Waits for PTY spawn plus Claude Code + MCP startup before kickoff input.
  ///
  /// [isMemberRunning] fires on first PTY output, but the Ink input box on the
  /// alternate screen often needs 15–30s more before [submitFullScreenInput]
  /// reaches the API layer.
  Future<void> waitUntilMembersReady(
    ChatCubit cubit,
    List<String> memberIds, {
    Duration minWarmup = const Duration(seconds: 20),
    Duration settleTimeout = const Duration(seconds: 45),
  }) async {
    await waitUntilMembersRunning(cubit, memberIds);

    final warmupDeadline = DateTime.now().add(minWarmup);
    while (DateTime.now().isBefore(warmupDeadline)) {
      await drainPendingAsyncWork();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    final settleDeadline = DateTime.now().add(settleTimeout);
    while (DateTime.now().isBefore(settleDeadline)) {
      if (memberIds.every((id) => _isMemberShellSettled(cubit, id))) {
        await Future<void>.delayed(const Duration(seconds: 2));
        return;
      }
      await drainPendingAsyncWork();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Worker parks on SSE `wait_for_message` before the leader acts.
  ///
  /// Syncs on [TeammateBusMcpServer.activeWaitStreamCount] and in-memory
  /// roster (`turnDoneBusWait`), not arbitrary delays.
  Future<void> kickoffWorkerParkedThenLeader(
    ChatCubit cubit, {
    required String sessionId,
    PostFrameTestHarness? postFrame,
    String workerKickoff = 'Start idle loop.',
    String leaderKickoff = 'Coordinate the team.',
    Duration workerReadyTimeout = const Duration(seconds: 90),
  }) async {
    _resetMockScenarios();
    final workerBaseline = _mockRequestCount(workerScriptApiKey);
    await _submitWorkerKickoff(cubit, kickoff: workerKickoff);
    final workerInLoop = await _waitForNewMockRequest(
      workerScriptApiKey,
      afterCount: workerBaseline,
      timeout: workerReadyTimeout,
    );
    if (!workerInLoop) {
      throw StateError(
        'Worker never hit mock API after kickoff '
        '(expected $workerScriptApiKey request)',
      );
    }
    await waitUntilWorkerParked(
      bus: _busForSession(cubit, sessionId),
      mcpServer: _mcpForSession(cubit, sessionId),
      memberId: kWorkerMember.id,
      timeout: workerReadyTimeout,
    );
    await _submitLeaderKickoff(
      cubit,
      postFrame: postFrame,
      kickoff: leaderKickoff,
    );
    await drainPendingAsyncWork(rounds: 15);
    if (postFrame != null) {
      await postFrame.flush();
    }
  }

  TeamBus? _busForSession(ChatCubit? cubit, String sessionId) =>
      cubit?.tabStore.bySessionId(sessionId)?.teamBus;

  TeammateBusMcpServer? _mcpForSession(ChatCubit? cubit, String sessionId) =>
      cubit?.tabStore.bySessionId(sessionId)?.mcpServer;

  Future<void> kickoffMembers(
    ChatCubit cubit, {
    PostFrameTestHarness? postFrame,
    String workerKickoff = 'Start idle loop.',
    String leaderKickoff = 'Coordinate the team.',
  }) async {
    const maxAttempts = 8;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      _resetMockScenarios();
      final workerBaseline = _mockRequestCount(workerScriptApiKey);
      final leaderBaseline = _mockRequestCount(leadScriptApiKey);
      await _submitKickoffOnce(
        cubit,
        postFrame: postFrame,
        workerKickoff: workerKickoff,
        leaderKickoff: leaderKickoff,
      );

      final workerHit = await _waitForNewMockRequest(
        workerScriptApiKey,
        afterCount: workerBaseline,
        timeout: const Duration(seconds: 25),
      );
      if (workerHit) {
        final leaderHit = await _waitForNewMockRequest(
          leadScriptApiKey,
          afterCount: leaderBaseline,
          timeout: const Duration(seconds: 15),
        );
        if (!leaderHit) {
          await _submitLeaderKickoff(
            cubit,
            postFrame: postFrame,
            kickoff: leaderKickoff,
          );
        }
        return;
      }

      if (attempt < maxAttempts - 1) {
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
    throw StateError(
      'Mock Anthropic API received no requests after $maxAttempts kickoff attempts',
    );
  }

  Future<void> _submitKickoffOnce(
    ChatCubit cubit, {
    PostFrameTestHarness? postFrame,
    String workerKickoff = 'Start idle loop.',
    String leaderKickoff = 'Coordinate the team.',
  }) async {
    await _submitWorkerKickoff(cubit, kickoff: workerKickoff);
    await _submitLeaderKickoff(
      cubit,
      postFrame: postFrame,
      kickoff: leaderKickoff,
    );
  }

  Future<void> _submitFullScreenKickoff(
    TerminalSession shell,
    String text,
  ) async {
    if (shell.runtimeTarget.namespace.isSsh) {
      // Bracketed paste + CR in one Future can lose the Enter over SSH latency;
      // stage text, settle, then submit on its own chain slot.
      await shell.pasteText(text);
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await shell.submitPendingCr();
    } else {
      await shell.submitFullScreenInput(text);
    }
  }

  Future<void> _submitWorkerKickoff(
    ChatCubit cubit, {
    String kickoff = 'Start idle loop.',
  }) async {
    cubit.selectMember(kWorkerMember.id);
    final worker = cubit.currentSession;
    if (worker == null) {
      throw StateError('worker shell missing before kickoff');
    }
    await _submitFullScreenKickoff(worker, kickoff);
    await drainPendingAsyncWork(rounds: 20);
  }

  Future<void> _submitLeaderKickoff(
    ChatCubit cubit, {
    PostFrameTestHarness? postFrame,
    String kickoff = 'Coordinate the team.',
  }) async {
    cubit.selectMember(kLeadMember.id);
    final leader = cubit.currentSession;
    if (leader == null) {
      throw StateError('leader shell missing before kickoff');
    }
    await _submitFullScreenKickoff(leader, kickoff);
    await drainPendingAsyncWork(rounds: 10);
    if (postFrame != null) {
      await postFrame.flush();
    }
  }

  void _resetMockScenarios() => _mockServer?.resetScenarios();

  int _mockRequestCount(String apiKey) =>
      _mockServer?.requestCountFor(apiKey) ?? 0;

  Future<bool> _waitForNewMockRequest(
    String apiKey, {
    required int afterCount,
    required Duration timeout,
  }) async {
    final server = _mockServer;
    if (server == null) return false;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (server.requestCountFor(apiKey) > afterCount) {
        return true;
      }
      await drainPendingAsyncWork();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  bool _isMemberShellSettled(ChatCubit cubit, String memberId) {
    cubit.selectMember(memberId);
    final shell = cubit.currentSession;
    if (shell == null || !shell.isRunning) return false;
    return !shell.activityTracker.isWorking;
  }

  TerminalSession? memberShell(ChatCubit cubit, String memberId) {
    cubit.selectMember(memberId);
    return cubit.currentSession;
  }

  Future<void> waitForPingPong({
    required String workspaceId,
    required String sessionId,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final root = AppStorage.paths.basePath;

    final workerPing = await waitForBusMail(
      teampilotRoot: root,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: kWorkerMember.id,
      timeout: timeout,
      where: (row) => row['from'] == kLeadMember.id && row['content'] == 'ping',
    );
    if (!workerPing) {
      throw StateError(
        'Timed out waiting for worker mail: ping from ${kLeadMember.id}',
      );
    }

    final leaderPong = await waitForBusMail(
      teampilotRoot: root,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: kLeadMember.id,
      timeout: timeout,
      where: (row) =>
          row['from'] == kWorkerMember.id && row['content'] == 'pong',
    );
    if (!leaderPong) {
      throw StateError(
        'Timed out waiting for leader mail: pong from ${kWorkerMember.id}',
      );
    }
  }

  Future<void> waitForTaskDispatched({
    required String workspaceId,
    required String sessionId,
    required String title,
    String assignee = 'worker-1',
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final claimed = await waitForTaskClaimedByTitle(
      teampilotRoot: AppStorage.paths.basePath,
      workspaceId: workspaceId,
      sessionId: sessionId,
      title: title,
      assignee: assignee,
      timeout: timeout,
    );
    if (!claimed) {
      throw StateError(
        'Timed out waiting for task "$title" to be claimed by $assignee',
      );
    }
  }

  Future<void> waitForTaskCompleted({
    required String workspaceId,
    required String sessionId,
    required String title,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final done = await waitForTaskDoneByTitle(
      teampilotRoot: AppStorage.paths.basePath,
      workspaceId: workspaceId,
      sessionId: sessionId,
      title: title,
      timeout: timeout,
    );
    if (!done) {
      throw StateError('Timed out waiting for task "$title" to be marked done');
    }
  }

  Future<void> waitForWorkerMail({
    required String workspaceId,
    required String sessionId,
    required String fromMemberId,
    required String content,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final ok = await waitForBusMail(
      teampilotRoot: AppStorage.paths.basePath,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: kWorkerMember.id,
      timeout: timeout,
      where: (row) => row['from'] == fromMemberId && row['content'] == content,
    );
    if (!ok) {
      throw StateError(
        'Timed out waiting for worker mail from $fromMemberId: $content',
      );
    }
  }

  Future<void> waitForLeaderMail({
    required String workspaceId,
    required String sessionId,
    required String fromMemberId,
    required String content,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final ok = await waitForBusMail(
      teampilotRoot: AppStorage.paths.basePath,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: kLeadMember.id,
      timeout: timeout,
      where: (row) => row['from'] == fromMemberId && row['content'] == content,
    );
    if (!ok) {
      throw StateError(
        'Timed out waiting for leader mail from $fromMemberId: $content',
      );
    }
  }

  TeamBus? tabBus(String sessionId) =>
      cubit?.tabStore.bySessionId(sessionId)?.teamBus;

  Future<void> dumpFailureArtifacts({
    String? workspaceId,
    String? sessionId,
    ChatCubit? cubit,
  }) async {
    // ignore: avoid_print
    print(_mockServer?.dumpDiagnostics() ?? 'mockServer: not started');
    // ignore: avoid_print
    print('claudePath: $claudePath');
    if (workspaceId != null && sessionId != null) {
      await _dumpClaudeSettings(workspaceId: workspaceId, sessionId: sessionId);
      await dumpBusRosterDiagnostics(
        bus: _busForSession(cubit ?? this.cubit, sessionId),
        mcpServer: _mcpForSession(cubit ?? this.cubit, sessionId),
      );
      await dumpBusMailDiagnostics(
        teampilotRoot: AppStorage.paths.basePath,
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberIds: [kLeadMember.id, kWorkerMember.id],
      );
      await dumpBusTaskDiagnostics(
        teampilotRoot: AppStorage.paths.basePath,
        workspaceId: workspaceId,
        sessionId: sessionId,
      );
    }
  }

  Future<void> _dumpClaudeSettings({
    required String workspaceId,
    required String sessionId,
  }) async {
    final root = WorkspaceLayout(
      teampilotRoot: AppStorage.paths.basePath,
    ).sessionRuntimeDir(workspaceId, sessionId);
    final dir = Directory(root);
    if (!await dir.exists()) {
      // ignore: avoid_print
      print('--- claude settings: runtime dir missing ($root)');
      return;
    }
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name != '.claude.json' &&
          !entity.path.contains(
            '${Platform.pathSeparator}settings${Platform.pathSeparator}',
          )) {
        continue;
      }
      if (!name.endsWith('.json')) continue;
      // ignore: avoid_print
      print('--- claude settings: ${entity.path}');
      // ignore: avoid_print
      print(await entity.readAsString());
    }
  }

  Future<void> dispose() async {
    final activeCubit = cubit;
    cubit = null;
    if (activeCubit != null) {
      await activeCubit.close();
    }
    await _mockServer?.stop();
    _mockServer = null;
    _restoreBusBridgeEnv();
  }

  void _forceHttpMcp() {
    try {
      _savedBusBridgeEnv = Platform.environment[BusBridgeLocator.envOverride];
      Platform.environment[BusBridgeLocator.envOverride] =
          '/dev/null/teampilot-it-no-bridge';
      _envOverrideApplied = true;
    } on UnsupportedError {
      // `flutter test` exposes an unmodifiable environment map; rely on no
      // runnable bridge being present in the test runner instead.
      _envOverrideApplied = false;
    }
  }

  void _restoreBusBridgeEnv() {
    if (!_envOverrideApplied) return;
    final saved = _savedBusBridgeEnv;
    _savedBusBridgeEnv = null;
    _envOverrideApplied = false;
    try {
      if (saved == null) {
        Platform.environment.remove(BusBridgeLocator.envOverride);
      } else {
        Platform.environment[BusBridgeLocator.envOverride] = saved;
      }
    } on UnsupportedError {
      // Best-effort restore only.
    }
  }
}

/// Docker SSH host + runtime contexts for mixed-team integration tests.
class MixedTeamDockerRemote {
  MixedTeamDockerRemote._({
    required this.server,
    required this.profile,
    required this.sshClientFactory,
    required this.sshProfileRepository,
    required this.credentialStore,
    required this.knownHostRepository,
    required this.contextRegistry,
  });

  static const profileId = 'it-mixed-docker';
  static const remoteWorkspacePath = '/home/testuser/workspace';

  final DockerSshServer server;
  final SshProfile profile;
  final SshClientFactory sshClientFactory;
  final SshProfileRepository sshProfileRepository;
  final SshCredentialStore credentialStore;
  final SshKnownHostRepository knownHostRepository;
  final RuntimeContextRegistry contextRegistry;

  String get sshTargetId => 'ssh:$profileId';

  SshProfile? sshProfileById(String id) => id == profileId ? profile : null;

  static Future<MixedTeamDockerRemote> start() async {
    final server = await DockerSshServer.startMixed(
      clientRoot: Directory.current.path,
    );
    final credentials = InMemorySshCredentialStore();
    final knownHosts = InMemorySshKnownHostRepository();
    await credentials.savePassword(profileId, DockerSshServer.defaultPassword);

    final profile = SshProfile(
      id: profileId,
      name: 'docker-it-mixed',
      host: server.host,
      port: server.port,
      username: DockerSshServer.defaultUsername,
    );

    final sshProfileRepository = SshProfileRepository();
    await sshProfileRepository.save(profile);

    final sshClientFactory = SshClientFactory(
      credentialStore: credentials,
      knownHostRepository: knownHosts,
      onHostKeyPrompt: (_) async => true,
    );

    final client = await sshClientFactory.clientForStorage(profile);
    await client.run('mkdir -p $remoteWorkspacePath');

    final resolver = RuntimeContextResolver(
      sshClientFactory: sshClientFactory,
      nativeAppDataPath: AppStorage.paths.basePath,
      nativeCwd: AppStorage.cwd,
    );
    final registry = RuntimeContextRegistry(
      resolver: resolver,
      homeTarget: RuntimeTarget.local(),
      sshProfileById: (id) => id == profileId ? profile : null,
    );
    await registry.ensureHome();

    return MixedTeamDockerRemote._(
      server: server,
      profile: profile,
      sshClientFactory: sshClientFactory,
      sshProfileRepository: sshProfileRepository,
      credentialStore: credentials,
      knownHostRepository: knownHosts,
      contextRegistry: registry,
    );
  }

  Future<void> dispose() async {
    sshClientFactory.disconnectAll();
    await server.stop();
  }
}
