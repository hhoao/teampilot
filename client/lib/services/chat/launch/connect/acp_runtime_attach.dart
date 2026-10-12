import 'dart:io';

import '../../../../models/app_session.dart';
import '../../../../models/runtime_target.dart';
import '../../../../models/team_config.dart';
import '../../../../models/workspace.dart';
import '../../../../models/workspace_launch_context.dart';
import '../../../acp/acp_chat_strings.dart';
import '../../../acp/acp_chat_transcript.dart';
import '../../../acp/acp_frame_logger.dart';
import '../../../acp/acp_session_runtime.dart';
import '../../../storage/home_storage.dart';
import '../../../storage/runtime_context.dart';
import '../../team_bus/mcp/member_bus_mcp_transport_resolver.dart';
import '../../team_bus/mcp/teammate_bus_mcp_config.dart';
import '../../runtime/runtime_extra_mcp_servers.dart';
import '../../../../cubits/session/acp/acp_chat_runtime_cubit.dart';
import '../../../../cubits/session/acp/acp_launch_wiring.dart';
import '../session/member_acp_stamp.dart';
import '../session_launch_host.dart';
import '../../session/chat_tab.dart';
import 'acp_launch_environment.dart';
import 'session_connect_executor.dart';
import 'session_connect_job.dart';

/// Test seam for the extra MCP map mixed ACP attach stages and forwards.
typedef AcpMemberExtraMcp =
    Map<String, Map<String, Object?>> Function({
      required AppSession session,
      required TeamMemberConfig member,
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

  /// Terminal-less personal ACP: attach a cubit and spawn `session.cli`.
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
    final workingDirectory = _personalWorkingDirectory(session, job.workspace);
    final cubit = _cubit(
      session: session,
      cli: cli,
      personal: true,
      memberId: null,
      processWorkingDirectory: workingDirectory,
    );
    tab.acpRuntime = cubit;
    _host.updateTabRunning(tab.info.id);
    await cubit.start(
      executable: _host.shellFactory.executableFor(cli),
      sessionToolDir: _sessionToolDir(session, cli),
      workingDirectory: workingDirectory,
      baseEnv: await _personalLaunchEnv(session, job, workspace),
    );
    if (_host.isClosed) return true;
    _host.finishSessionConnect(session.sessionId);
    _host.updateTabRunning(tab.info.id);
    return true;
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
    final cubit = _cubit(
      session: session,
      cli: cli,
      personal: false,
      memberId: member.id,
      processWorkingDirectory: staged.workingDirectory,
    );
    tab.memberAcpRuntimes[member.id] = cubit;
    _host.updateTabRunning(tab.info.id);
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
    );
    if (_host.isClosed) return true;
    _host.finishSessionConnect(session.sessionId);
    _host.updateTabRunning(tab.info.id);
    return true;
  }

  AcpChatRuntimeCubit _cubit({
    required AppSession session,
    required CliTool cli,
    required bool personal,
    required String? memberId,
    required String processWorkingDirectory,
  }) {
    final logger = AcpFrameLogger();
    final runtime =
        runtimeFactory?.call(logger: logger, tool: cli) ??
        AcpSessionRuntime(
          spawner: productionAcpSpawner(
            registry: _host.cliRegistry,
            tool: cli,
            workingDirectory: processWorkingDirectory,
            logger: logger,
          ),
          logger: logger,
          launchPlanFor: acpLaunchPlanResolver(_host.cliRegistry),
        );
    return AcpChatRuntimeCubit(
      runtime: runtime,
      sessionId: session.sessionId,
      tool: cli,
      seatMemberId: personal ? AcpChatRuntimeCubit.acpMemberId : memberId!,
      attention: _host.agentAttentionCubit,
      transcript: _transcript(session, memberId: memberId, personal: personal),
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
      launchTarget: launchWorkTarget(session),
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
}
