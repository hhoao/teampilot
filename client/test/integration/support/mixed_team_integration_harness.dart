import 'dart:ffi';
import 'dart:io';

import 'package:mock_anthropic/scenarios/ping_pong_mixed_claude.dart';
import 'package:mock_anthropic/server.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_provider_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/team_bus/mcp/bus_bridge_locator.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../support/post_frame_test_harness.dart';
import 'bus_mail_assertions.dart';

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

  /// True when `libflutter_pty` is on the loader path (e.g. after `flutter build linux`).
  static bool get nativePtyAvailable {
    if (Platform.isLinux) {
      try {
        DynamicLibrary.open('libflutter_pty.so');
        return true;
      } catch (_) {
        return false;
      }
    }
    if (Platform.isWindows) {
      for (final path in [
        'flutter_pty.dll',
        r'build\windows\x64\debug\flutter_pty.dll',
        r'build\windows\x64\runner\Debug\flutter_pty.dll',
      ]) {
        try {
          DynamicLibrary.open(path);
          return true;
        } catch (_) {}
      }
    }
    return false;
  }

  /// Resolves `claude` on PATH, or null when not installed.
  static String? resolveClaudePath() {
    try {
      if (Platform.isWindows) {
        final result = Process.runSync('where', ['claude']);
        if (result.exitCode != 0) return null;
        for (final raw in result.stdout.toString().split(RegExp(r'\r?\n'))) {
          final line = raw.trim();
          if (line.isNotEmpty) return line;
        }
        return null;
      }
      final result = Process.runSync('which', ['claude']);
      if (result.exitCode != 0) return null;
      final line = result.stdout.toString().trim().split('\n').first.trim();
      return line.isEmpty ? null : line;
    } on ProcessException {
      return null;
    }
  }

  Future<void> startMockServer() async {
    _forceHttpMcp();
    final server = MockAnthropicServer(
      scenarios: pingPongMixedClaudeScenarios(),
    );
    _mockServer = server;
    await server.start();
  }

  Future<void> writeMockProviders() async {
    await AppProviderRepository(basePath: AppStorage.paths.basePath).saveProviders(
      CliTool.claude,
      [
        AppProviderConfig(
          id: kMockLeaderProviderId,
          cli: CliTool.claude,
          name: 'Mock Leader',
          baseUrl: mockBaseUrl,
          apiKey: leadScriptApiKey,
          defaultModel: 'mock-model',
        ),
        AppProviderConfig(
          id: kMockWorkerProviderId,
          cli: CliTool.claude,
          name: 'Mock Worker',
          baseUrl: mockBaseUrl,
          apiKey: workerScriptApiKey,
          defaultModel: 'mock-model',
        ),
      ],
    );
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

  Future<void> kickoffMembers(
    ChatCubit cubit, {
    PostFrameTestHarness? postFrame,
  }) async {
    const maxAttempts = 8;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await _submitKickoffOnce(cubit, postFrame: postFrame);

      final workerHit = await _waitForMockRequest(
        workerScriptApiKey,
        timeout: const Duration(seconds: 25),
      );
      if (workerHit) {
        final leaderHit = await _waitForMockRequest(
          leadScriptApiKey,
          timeout: const Duration(seconds: 15),
        );
        if (!leaderHit) {
          await _submitLeaderKickoff(cubit, postFrame: postFrame);
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
  }) async {
    await _submitWorkerKickoff(cubit);
    await _submitLeaderKickoff(cubit, postFrame: postFrame);
  }

  Future<void> _submitWorkerKickoff(ChatCubit cubit) async {
    cubit.selectMember(kWorkerMember.id);
    final worker = cubit.currentSession;
    if (worker == null) {
      throw StateError('worker shell missing before kickoff');
    }
    await worker.submitFullScreenInput('Start idle loop.');
    await drainPendingAsyncWork(rounds: 10);
  }

  Future<void> _submitLeaderKickoff(
    ChatCubit cubit, {
    PostFrameTestHarness? postFrame,
  }) async {
    cubit.selectMember(kLeadMember.id);
    final leader = cubit.currentSession;
    if (leader == null) {
      throw StateError('leader shell missing before kickoff');
    }
    await leader.submitFullScreenInput('Coordinate the team.');
    await drainPendingAsyncWork(rounds: 10);
    if (postFrame != null) {
      await postFrame.flush();
    }
  }

  Future<bool> _waitForMockRequest(
    String apiKey, {
    required Duration timeout,
  }) async {
    final server = _mockServer;
    if (server == null) return false;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (server.requestLog.any((entry) => entry.apiKey == apiKey)) {
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
      where: (row) =>
          row['from'] == kLeadMember.id && row['content'] == 'ping',
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

  Future<void> dumpFailureArtifacts({
    String? workspaceId,
    String? sessionId,
  }) async {
    // ignore: avoid_print
    print(_mockServer?.dumpDiagnostics() ?? 'mockServer: not started');
    // ignore: avoid_print
    print('claudePath: $claudePath');
    if (workspaceId != null && sessionId != null) {
      await _dumpClaudeSettings(
        workspaceId: workspaceId,
        sessionId: sessionId,
      );
      await dumpBusMailDiagnostics(
        teampilotRoot: AppStorage.paths.basePath,
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberIds: [kLeadMember.id, kWorkerMember.id],
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
          !entity.path.contains('${Platform.pathSeparator}settings${Platform.pathSeparator}')) {
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
