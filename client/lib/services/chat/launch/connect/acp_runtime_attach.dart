import 'dart:io';

import '../../../../models/app_session.dart';
import '../../../../models/runtime_target.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../../models/workspace_launch_context.dart';
import '../../../acp/acp_chat_strings.dart';
import '../../../acp/acp_chat_transcript.dart';
import '../../../acp/acp_agent_session_store.dart';
import '../../../acp/acp_frame_logger.dart';
import '../../../acp/acp_session_runtime.dart';
import '../../../acp/acp_ssh_transport.dart';
import '../../../ssh/ssh_member_session.dart';
import '../../../storage/home_storage.dart';
import '../../../storage/runtime_context.dart';
import '../../team_bus/mcp/member_bus_mcp_transport_resolver.dart';
import '../../team_bus/mcp/teammate_bus_mcp_config.dart';
import '../../runtime/runtime_extra_mcp_servers.dart';
import '../../../../cubits/session/acp/acp_chat_runtime_cubit.dart';
import '../../../../cubits/session/acp/acp_launch_wiring.dart';
import '../../../../cubits/session/acp/acp_transport_wiring.dart';
import '../../../../utils/logging/logger.dart';
import '../session/member_acp_stamp.dart';
import '../session_launch_host.dart';
import '../../session/chat_tab.dart';
import 'acp_launch_environment.dart';
import 'connect_shell_result.dart';
import 'session_connect_executor.dart';
import 'session_connect_job.dart';

/// Test seam for the extra MCP map mixed ACP attach stages and forwards.
typedef AcpMemberExtraMcp =
    Map<String, Map<String, Object?>> Function({
      required AppSession session,
      required TeamMemberConfig member,
    });

/// Optional mixed-seat lifecycle gate (auth sync, bus ready) before ACP spawn.
/// Null from tests that skip [SessionLaunchService.configureLaunchComponents].
typedef AcpMemberLifecycleGate =
    Future<ConnectShellResult?> Function({
      required TeamProfile team,
      required TeamMemberConfig member,
      required AppSession session,
      required String sessionId,
      required bool teamBusInstalled,
      Map<String, Map<String, Object?>>? extraMcpServers,
    });

/// Transcript file under `sessions/<id>/runtime/`.
///
/// Personal stays `acp-transcript.jsonl`. Mixed seats use
/// `acp-transcript-<rosterMemberId>.jsonl`.
String acpTranscriptFileName({String? memberId, required bool personal}) {
  if (personal) return 'acp-transcript.jsonl';
  final id = memberId?.trim() ?? '';
  if (id.isEmpty) return 'acp-transcript.jsonl';
  return 'acp-transcript-$id.jsonl';
}

/// Adapter-path resolver for one ACP launch plan.
///
/// Remote launches use the per-target absolute override (or `null` → the plain
/// adapter name via PATH). Local launches use the boot-discovered map.
String? Function(CliTool tool) acpAdapterPathResolverFor({
  required bool remote,
  required String? remoteAdapterPath,
  String Function(CliTool tool)? localResolver,
}) {
  if (remote) return (_) => remoteAdapterPath;
  final resolve = localResolver;
  return resolve == null ? (_) => null : (tool) => resolve(tool);
}

/// Agent-session sidecar under `sessions/<id>/runtime/`.
///
/// Personal stays `acp-session.json`. Mixed seats use
/// `acp-session-<rosterMemberId>.json`.
String acpAgentSessionFileName({String? memberId, required bool personal}) {
  if (personal) return 'acp-session.json';
  final id = memberId?.trim() ?? '';
  if (id.isEmpty) return 'acp-session.json';
  return 'acp-session-$id.json';
}

/// Personal and mixed-seat ACP attach. [SessionLaunchService] delegates here
/// so the service does not grow the spawn path.
class AcpRuntimeAttach {
  AcpRuntimeAttach({
    required SessionLaunchHost host,
    required HomeStorage storage,
    required this.workspaceById,
    required this.launchWorkTarget,
    this.runtimeFactory,
    this.preparePersonalContribution,
    this.prepareTeamConnect,
    this.extraMcpForMember,
    this.memberLifecycleGate,
    this.prepareRemoteStaging,
    this.sshLaunchFactory,
  }) : _host = host,
       _storage = storage;

  final SessionLaunchHost _host;
  final HomeStorage _storage;
  final Workspace? Function(String workspaceId) workspaceById;
  final RuntimeTarget Function(AppSession session, {String? memberId})
  launchWorkTarget;
  final AcpRuntimeFactory? runtimeFactory;
  final AcpContributionEnvBuilder? preparePersonalContribution;
  final AcpTeamConnectPrepare? prepareTeamConnect;
  final AcpMemberExtraMcp? extraMcpForMember;

  /// Production wires [SessionLaunchService.lifecycleGateBeforeAttach] here.
  AcpMemberLifecycleGate? memberLifecycleGate;

  /// Test seam: skip the production remote staging.
  final AcpRemoteStagingBuilder? prepareRemoteStaging;

  /// Test seam: skip opening a real member SSH session.
  final AcpSshLaunchFactory? sshLaunchFactory;

  /// Terminal-less personal ACP: attach a cubit and spawn `session.cli`
  /// locally, or on the remote host when the launch target uses SSH.
  Future<bool> attachAcpRuntime(
    SessionConnectJob job,
    AppSession session,
  ) async {
    final tab = _host.tabStore.getOpenTabBySessionId(session.sessionId);
    if (tab == null) return false;
    final existing = tab.acpRuntime;
    if (existing != null) {
      _host.updateTabRunning(tab.info.id);
      return true;
    }
    final cli = session.cli;
    if (cli == null) {
      throw StateError('ACP session requires session.cli');
    }
    final workspace = job.workspace ?? workspaceById(session.workspaceId);
    final launchTarget = launchWorkTarget(session);
    final remote = usesSshTransport(launchTarget.kind);
    final workingDirectory = _personalWorkingDirectory(session, job.workspace);

    late final String executable;
    late final String sessionToolDir;
    late final Map<String, String> baseEnv;
    if (remote) {
      if (workspace == null) {
        throw StateError('Simple session requires workspace');
      }
      final build = prepareRemoteStaging ?? _productionRemoteStaging;
      final prepared = await build(
        session: session,
        workspace: workspace,
        launchTarget: launchTarget,
      );
      final selected = selectAcpRemoteLaunch(
        prepared: prepared,
        localExecutable: _host.shellFactory.executableFor(cli),
        localSessionToolDir: _sessionToolDir(session, cli),
      );
      executable = selected.executable;
      sessionToolDir = selected.sessionToolDir;
      baseEnv = selected.env;
    } else {
      executable = _host.shellFactory.executableFor(cli);
      sessionToolDir = _sessionToolDir(session, cli);
      baseEnv = await _personalLaunchEnv(
        session,
        job,
        workspace,
        launchTarget,
      );
    }

    final sshLaunch = remote
        ? (sshLaunchFactory ?? _productionSshLaunch)(
            session: session,
            launchTarget: launchTarget,
          )
        : null;

    final remoteAdapterPath = remote
        ? await _resolveRemoteAdapterPath(cli, launchTarget)
        : null;
    final cubit = _cubit(
      session: session,
      cli: cli,
      personal: true,
      memberId: null,
      launchTarget: launchTarget,
      sshLaunch: sshLaunch,
      remoteAdapterPath: remoteAdapterPath,
      processWorkingDirectory: workingDirectory,
    );
    tab.acpRuntime = cubit;
    _host.updateTabRunning(tab.info.id);
    await cubit.start(
      executable: executable,
      sessionToolDir: sessionToolDir,
      workingDirectory: workingDirectory,
      baseEnv: baseEnv,
      permissionPolicy: session.acpPermission,
    );
    if (_host.isClosed) return true;
    _host.finishSessionConnect(session.sessionId);
    _host.updateTabRunning(tab.info.id);
    return true;
  }

  /// Production remote staging: the same orchestration the PTY path uses, so
  /// the remote workspace is provisioned and `remoteCliPath` /
  /// `plan.memberConfigDir` / `plan.env` are the remote values.
  Future<AcpPreparedSimpleConnect> _productionRemoteStaging({
    required AppSession session,
    required Workspace workspace,
    required RuntimeTarget launchTarget,
  }) {
    return _host.sessionConnect.prepareSimpleConnect(
      session: session,
      workspace: workspace,
      launchTarget: launchTarget,
    );
  }

  /// Reads the per-target ACP adapter override for a remote launch. `null`
  /// keeps today's behavior (resolve the bare adapter name via remote PATH).
  Future<String?> _resolveRemoteAdapterPath(
    CliTool cli,
    RuntimeTarget launchTarget,
  ) async {
    final resolver = _host.acpAdapterPathOverride;
    if (resolver == null) return null;
    try {
      final path = (await resolver(launchTarget.id, cli.value))?.trim() ?? '';
      return path.isEmpty ? null : path;
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[acp-remote] adapter override lookup failed target=${launchTarget.id} '
        'cli=${cli.value}',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// Production SSH launch: opens (and stores on the tab) one member SSH
  /// session, then hands out exec channels over it. Stored under
  /// `session.sessionId` so [ChatTab.disposeBus] tears it down.
  AcpSshLaunch _productionSshLaunch({
    required AppSession session,
    required RuntimeTarget launchTarget,
  }) {
    final factory = _host.shellFactory.sshClientFactory;
    final profile = _host.shellFactory.profileFor(launchTarget);
    if (factory == null || profile == null) {
      throw StateError(
        'ACP remote session requires an SSH profile and client factory',
      );
    }
    return (
      profile: profile,
      openChannel: (command) async {
        final tab = _host.tabStore.getOpenTabBySessionId(session.sessionId);
        if (tab == null) {
          throw StateError(
            'ACP remote session tab missing session=${session.sessionId}',
          );
        }
        final memberSession =
            tab.memberSshSessions[session.sessionId] ??
            await SshMemberSession.open(factory, profile);
        tab.memberSshSessions[session.sessionId] = memberSession;
        return DartSsh2AcpChannel(await memberSession.openExec(command));
      },
    );
  }

  /// Mixed-seat ACP. False lets the caller fall through to PTY.
  Future<bool> attachMemberAcpRuntime(
    SessionConnectJob job,
    AppSession session,
    ResolvedLaunchMembers resolved,
  ) async {
    final member = resolved.member;
    final team = resolved.team;
    final workspace = job.workspace ?? workspaceById(session.workspaceId);
    final launchTarget = _memberLaunchTarget(session, workspace, member.id);
    if (team == null ||
        !shouldAttachMemberAcp(
          session: session,
          memberId: member.id,
          team: team,
          targetId: launchTarget.id,
        )) {
      return false;
    }
    final tab = _host.tabStore.getOpenTabBySessionId(session.sessionId);
    if (tab == null) return false;
    final existing = tab.memberAcpRuntimes[member.id];
    if (existing != null) {
      _host.updateTabRunning(tab.info.id);
      return true;
    }
    if (workspace == null) {
      throw StateError('Team session requires workspace');
    }
    final cli = resolved.cli;
    final injectedExtra = extraMcpForMember?.call(
      session: session,
      member: member,
    );
    final extra =
        injectedExtra ??
        await _productionExtraMcp(
          tab: tab,
          session: session,
          team: resolved.team,
          member: member,
          cli: cli,
          launchTarget: launchTarget,
          workspace: workspace,
        );
    final work = session.workDirsForMember(
      member.id,
      folders: WorkspaceLaunchContext(
        session: session,
        workspace: workspace,
        usesPosixPaths: _storage.usesPosixPaths,
      ).folderCatalog,
      usesPosixPaths: _storage.usesPosixPaths,
    );
    final staged = await prepareAcpTeamLaunchEnvironment(
      prepareTeamConnect:
          prepareTeamConnect ?? _productionTeamPrepare(work.addDirs),
      session: session,
      team: team,
      member: member,
      workspace: workspace,
      launchTarget: launchTarget,
      workingDirectory: work.workingDirectory,
      extraMcpServers: extra,
    );
    final gate = memberLifecycleGate;
    if (gate != null) {
      final gated = await gate(
        team: team,
        member: member,
        session: session,
        sessionId: session.sessionId,
        teamBusInstalled: tab.teamBus != null,
        extraMcpServers: extra,
      );
      if (gated != null) {
        throw StateError(
          'ACP member lifecycle ${gated.name} member=${member.id}',
        );
      }
      appLogger.d(
        '[session-launch] acp member lifecycle gate done member=${member.id}',
      );
    }
    final cubit = _cubit(
      session: session,
      cli: cli,
      personal: false,
      memberId: member.id,
      launchTarget: launchTarget,
      sshLaunch: null,
      processWorkingDirectory: staged.workingDirectory,
    );
    tab.memberAcpRuntimes[member.id] = cubit;
    _listenForMemberIdle(tab, member.id, cubit);
    _host.updateTabRunning(tab.info.id);
    // Same moment as PTY `onProcessStarted`: unblock send()'s materialize
    // wait and allow MailArrived doorbells. Do this before `cubit.start`
    // (ACP session/new is often >20s) so TeamBus is not stuck in
    // `materializing` until Cursor's 60s MCP timeout.
    tab.teamBus?.markMemberRunning(member.id);
    _host.memberMaterializer.markMemberReady(session.sessionId, member.id);
    await cubit.start(
      executable: _host.shellFactory.executableFor(cli),
      sessionToolDir: _memberSessionToolDir(
        session,
        cli,
        staged.memberConfigDir,
      ),
      workingDirectory: staged.workingDirectory,
      baseEnv: staged.env,
      mcpServers: staged.mcpServers,
      permissionPolicy:
          session.bindingFor(member.id)?.acpPermission ??
          LaunchSecurityPolicy.fullAccess,
    );
    if (_host.isClosed) return true;
    _host.finishSessionConnect(session.sessionId);
    _host.updateTabRunning(tab.info.id);
    return true;
  }

  /// TeamBus idle fires when the seat becomes prompt-ready: the first
  /// transition into [AcpChatPhase.idle], and each later turn whose [inTurn]
  /// falls while the phase stays idle. [AcpChatPhase.ended] does not fire.
  /// Later emits that stay idle with [inTurn] already false do not fire.
  /// [Cubit.close] closes the state stream and cancels this listener.
  /// Personal attach does not subscribe.
  void _listenForMemberIdle(
    ChatTab tab,
    String memberId,
    AcpChatRuntimeCubit cubit,
  ) {
    var previousPhase = cubit.state.phase;
    var previousInTurn = cubit.state.inTurn;
    cubit.stream.listen((state) {
      final wasPhase = previousPhase;
      final wasInTurn = previousInTurn;
      previousPhase = state.phase;
      previousInTurn = state.inTurn;
      if (state.phase == AcpChatPhase.ended) return;
      final enteredIdle =
          wasPhase != AcpChatPhase.idle && state.phase == AcpChatPhase.idle;
      final turnEnded =
          state.phase == AcpChatPhase.idle && wasInTurn && !state.inTurn;
      if (!enteredIdle && !turnEnded) return;
      appLogger.d(
        '[acp-attach] member idle member=$memberId session=${cubit.sessionId}',
      );
      tab.teamBus?.onMemberIdle(memberId);
    });
  }

  AcpChatRuntimeCubit _cubit({
    required AppSession session,
    required CliTool cli,
    required bool personal,
    required String? memberId,
    required RuntimeTarget launchTarget,
    required String processWorkingDirectory,
    AcpSshLaunch? sshLaunch,
    String? remoteAdapterPath,
  }) {
    final remote = usesSshTransport(launchTarget.kind);
    final logger = AcpFrameLogger();
    final runtime =
        runtimeFactory?.call(logger: logger, tool: cli) ??
        AcpSessionRuntime(
          spawner: productionAcpSpawner(
            registry: _host.cliRegistry,
            tool: cli,
            workingDirectory: processWorkingDirectory,
            logger: logger,
            transportStarter: acpStarterForTarget(
              launchTarget: launchTarget,
              sshLaunch: sshLaunch,
            ),
          ),
          logger: logger,
          launchPlanFor: acpLaunchPlanResolver(
            _host.cliRegistry,
            discoveredAdapterPath: acpAdapterPathResolverFor(
              remote: remote,
              remoteAdapterPath: remoteAdapterPath,
              localResolver: _host.discoveredAcpAdapterPath,
            ),
          ),
        );
    return AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: session.sessionId,
      tool: cli,
      seatMemberId: personal ? AcpChatRuntimeCubit.acpMemberId : memberId!,
      attention: _host.agentAttentionCubit,
      transcript: _transcript(session, memberId: memberId, personal: personal),
      agentSession: _agentSessionStore(session, memberId: memberId, personal: personal),
    )..ensureStrings(_host.acpChatStrings?.call(cli) ?? defaultAcpChatStrings);
  }

  /// Personal spawner captured cwd before start; member start passes cwd
  /// separately, so the production spawner cwd is filled at start time.
  String _personalWorkingDirectory(AppSession session, Workspace? workspace) {
    final firstFolder = session.folders.isNotEmpty
        ? session.folders.first.path
        : '';
    if (firstFolder.trim().isNotEmpty) return firstFolder;
    return workspace?.firstFolderPath ?? '';
  }

  String _sessionToolDir(AppSession session, CliTool cli) {
    return _storage.context.layout.sessionRuntimeToolDir(
      session.workspaceId,
      session.sessionId,
      cli.value,
    );
  }

  String _memberSessionToolDir(
    AppSession session,
    CliTool cli,
    String stagedDir,
  ) {
    final staged = stagedDir.trim();
    if (staged.isNotEmpty) return staged;
    return _sessionToolDir(session, cli);
  }

  Future<Map<String, String>> _personalLaunchEnv(
    AppSession session,
    SessionConnectJob job,
    Workspace? workspace,
    RuntimeTarget launchTarget,
  ) async {
    final resolved = workspace ?? job.workspace;
    if (resolved == null) {
      throw StateError('Simple session requires workspace');
    }
    final injected = preparePersonalContribution;
    if (injected != null) {
      return {
        'PATH': Platform.environment['PATH'] ?? '',
        ...await injected(session, resolved),
      };
    }
    return prepareAcpLaunchEnvironment(
      prepareSimpleConnect:
          ({required session, required workspace, required launchTarget}) =>
              _host.sessionConnect.prepareSimpleConnect(
                session: session,
                workspace: workspace,
                launchTarget: launchTarget,
              ),
      session: session,
      workspace: resolved,
      launchTarget: launchTarget,
    );
  }

  AcpTeamConnectPrepare _productionTeamPrepare(
    List<String> additionalDirectories,
  ) {
    return ({
      required session,
      required team,
      required member,
      required workspace,
      required launchTarget,
      required workingDirectory,
      extraMcpServers,
    }) {
      return _host.sessionConnect.prepareTeamConnect(
        session: session,
        team: team,
        member: member,
        memberBinding: session.bindingFor(member.id),
        workspace: workspace,
        launchTarget: launchTarget,
        workingDirectory: workingDirectory,
        additionalDirectories: additionalDirectories,
        extraMcpServers: extraMcpServers,
      );
    };
  }

  RuntimeTarget _memberLaunchTarget(
    AppSession session,
    Workspace? workspace,
    String memberId,
  ) {
    if (prepareTeamConnect != null) {
      final id = session.memberTargets[memberId]?.trim();
      if (id == null || id.isEmpty) return RuntimeTarget.local();
      return RuntimeTarget(id: id, label: id, kind: runtimeKindOfId(id));
    }
    if (workspace == null) return RuntimeTarget.local();
    return launchWorkTarget(session, memberId: memberId);
  }

  Future<Map<String, Map<String, Object?>>> _productionExtraMcp({
    required ChatTab tab,
    required AppSession session,
    required TeamProfile? team,
    required TeamMemberConfig member,
    required CliTool cli,
    required RuntimeTarget launchTarget,
    required Workspace workspace,
  }) async {
    final gateway = _host.teammateBusMcpGateway;
    await gateway.ensureStarted();
    final mixedBus =
        team?.teamMode == TeamMode.mixed &&
        tab.teamBus != null &&
        gateway.isSessionRegistered(session.sessionId);
    final isLocalNative = _storage.context.mode == StorageBackendMode.native;
    final busExtra = <String, Map<String, Object?>>{
      if (mixedBus)
        teammateBusMcpServerName: resolveMemberBusMcpTransportConfig(
          cliRegistry: _host.cliRegistry,
          endpoint: gateway.mcpEndpoint,
          sessionId: session.sessionId,
          memberId: member.id,
          cli: cli,
          isLocalNative: isLocalNative,
        ),
    };
    return composeRuntimeExtraMcpServers(
      extra: busExtra,
      session: session,
      memberId: member.id,
      cli: cli,
      launchKind: launchTarget.kind,
      cliRegistry: _host.cliRegistry,
      catalogEndpoint: gateway.catalogMcpEndpoint,
      composerEndpoint: gateway.teamComposerMcpEndpoint,
      isLocalNative: isLocalNative,
      teamGenerationTokenIssuer: _host.teamGenerationTokenIssuer,
      workspace: workspace,
      sessionSshMcpEndpoint: gateway.sessionSshMcpEndpoint,
    );
  }

  AcpChatTranscriptWriter _transcript(
    AppSession session, {
    required String? memberId,
    required bool personal,
  }) {
    return AcpChatTranscriptWriter(
      fs: _storage.fs,
      path: _storage.context.layout.pathContext.join(
        _storage.context.layout.workspace.sessionRuntimeDir(
          session.workspaceId,
          session.sessionId,
        ),
        acpTranscriptFileName(memberId: memberId, personal: personal),
      ),
    );
  }

  AcpAgentSessionStore _agentSessionStore(
    AppSession session, {
    required String? memberId,
    required bool personal,
  }) {
    return AcpAgentSessionStore(
      fs: _storage.fs,
      path: _storage.context.layout.pathContext.join(
        _storage.context.layout.workspace.sessionRuntimeDir(
          session.workspaceId,
          session.sessionId,
        ),
        acpAgentSessionFileName(memberId: memberId, personal: personal),
      ),
    );
  }
}
