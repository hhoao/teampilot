import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_lifecycle_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';

import '../../support/post_frame_test_harness.dart';

class _DenyGateLifecycle implements CliSessionLifecycleCapability {
  var initializeCalls = 0;

  @override
  Future<CliSessionPersistResult> ensurePersisted(
    CliSessionPersistContext ctx,
  ) async => const CliSessionPersistResult();

  @override
  Future<CliSessionInitResult> initialize(
    CliSessionInitContext ctx, {
    CliSessionPhase targetPhase = CliSessionPhase.ready,
  }) async {
    initializeCalls++;
    return const CliSessionInitResult();
  }

  @override
  Future<void> finalize(CliSessionFinalizeContext ctx) async {}

  @override
  CliSessionGateDecision gateConnect(CliSessionGateContext ctx) =>
      const CliSessionGateDecision(allowed: false, reason: 'test-deny');

  @override
  CliSessionPhase? peekSessionPhase(CliSessionGateContext ctx) => null;
}

class _ToolWithExtraCapability implements CliToolDefinition {
  const _ToolWithExtraCapability(this._inner, this._extra);

  final CliToolDefinition _inner;
  final CliCapability _extra;

  @override
  CliTool get id => _inner.id;

  @override
  bool get isLaunchSupported => _inner.isLaunchSupported;

  @override
  Iterable<CliCapability> get capabilities => [..._inner.capabilities, _extra];
}

CliToolRegistry _registryWithLifecycle(
  CliTool cli,
  CliSessionLifecycleCapability lifecycle,
) {
  final registry = CliToolRegistry();
  registerBuiltInCliTools(registry);
  final inner = registry.tryGet(cli);
  expect(inner, isNotNull);
  registry.register(_ToolWithExtraCapability(inner!, lifecycle));
  return registry;
}

class _SpyTerminalSession extends TerminalSession {
  _SpyTerminalSession({required super.executable});

  var connectCalls = 0;

  @override
  bool get isRunning => false;

  @override
  void connect({
    required String workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    shellLaunch,
    Map<String, String>? extraEnvironment,
    void Function()? onProcessStarted,
    void Function(String message)? onProcessFailed,
    void Function()? onProcessExited,
    void Function(String line)? onFirstUserLineSubmitted,
    void Function(String line)? onEveryUserLineSubmitted,
    busUserInputRouting,
    String? executableOverride,
  }) {
    connectCalls++;
  }

  @override
  void dispose() {}
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  group('SessionLaunchService lifecycle gate', () {
    late Directory tmp;
    late SessionRepository repo;
    late _DenyGateLifecycle denyLifecycle;
    late ChatCubit cubit;
    late PostFrameTestHarness postFrame;
    final shells = <_SpyTerminalSession>[];

    const team = TeamProfile(
      id: 'team-gate',
      name: 'Gate Team',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
      members: [TeamMemberConfig(id: 'team-lead', name: 'Team Lead')],
    );

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('launch_lifecycle_gate_');
      repo = SessionRepository(rootDir: tmp.path);
      denyLifecycle = _DenyGateLifecycle();
      postFrame = PostFrameTestHarness();
      shells.clear();
      cubit = ChatCubit(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
        sessionRepository: repo,
        lifecycleService: SessionLifecycleService(
          cliToolRegistry: _registryWithLifecycle(
            CliTool.claude,
            denyLifecycle,
          ),
        ),
        postFrameScheduler: postFrame.scheduler,
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) {
              final shell = _SpyTerminalSession(executable: executable);
              shells.add(shell);
              return shell;
            },
      );
    });

    tearDown(() async {
      await postFrame.flush();
      await drainPendingAsyncWork();
      await cubit.close();
      await drainPendingAsyncWork();
      await deleteTempDirBestEffort(tmp);
    });

    test('denied gate skips shell connect and surfaces launch error', () async {
      final workspace = await repo.createWorkspace([
        WorkspaceFolder(path: '/tmp'),
      ]);
      final session = (await repo.createSession(
        workspace.workspaceId,
        sessionTeam: team.id,
        rosterMembers: team.members,

        memberClis: {for (final m in team.members) m.id: CliTool.claude},
      )).session;
      await cubit.loadWorkspaceData(repo);

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

      await cubit.launchAllMembers(team, repo: repo);
      await postFrame.flush();
      await drainPendingAsyncWork();

      expect(denyLifecycle.initializeCalls, greaterThanOrEqualTo(1));
      expect(shells, isNotEmpty);
      expect(shells.first.connectCalls, 0);
      expect(
        cubit.isSessionConnecting(session.sessionId),
        isFalse,
      );
      expect(cubit.tabStore.activeTabs.first.info.launchError, isNotNull);
    });
  });
}
