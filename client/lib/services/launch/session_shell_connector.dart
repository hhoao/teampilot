import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../cubits/chat/chat_tab_store.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/member_instance.dart';
import '../../models/member_remote_provision_progress.dart';
import '../../models/runtime_target.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../repositories/session_repository.dart';
import '../../services/cli/installer_types.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/launch/connect_shell_result.dart';
import '../../services/launch/member_bus_mcp_transport_resolver.dart';
import '../../services/session/shell_launch_spec.dart';
import '../../services/session/remote_ssh_launch_constraints.dart';
import '../../services/ssh/ssh_member_session.dart';
import '../../services/agent_status/member_agent_status_endpoint.dart';
import '../../services/agent_status/member_agent_status_endpoint_resolver.dart';
import '../../services/team_bus/member_bus_idle_endpoint.dart';
import '../../services/team_bus/remote/member_bus_mcp_config.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_config.dart';
import '../../services/team_bus/remote/remote_bus_binding_resolver.dart';
import '../../services/team_bus/remote/remote_bus_mount.dart';
import '../../services/team_bus/remote/ssh_remote_bus_mount_factory.dart';
import '../../services/terminal/terminal_session.dart';
import '../../services/terminal/terminal_theme_for_launch.dart';
import 'package:logger/logger.dart';
import '../../utils/logging/logger.dart';

typedef TermuxWorkOpsBlockResolver = String? Function(RuntimeTarget target);

/// Hooks [SessionShellConnector] delegates back to [SessionLaunchService].
abstract interface class SessionShellConnectorDelegate {
  WorkspaceLaunchContext launchContextFor(AppSession session);

  Future<ConnectShellResult?> lifecycleGateBeforeAttach({
    required TeamProfile team,
    required TeamMemberConfig member,
    required AppSession session,
    required ChatTab tab,
    String? remoteMemberKeyForRollback,
  });

  void cancelLifecycleConnectRetry(String sessionId, String memberId);

  void Function(String line)? autoRenameOnFirstPrompt(String sessionId);

  void Function(String line)? autoTouchOnEveryPrompt(String sessionId);
}

/// Attaches a member shell after launch prep, lifecycle gating, and SSH/bus setup.
class SessionShellConnector {
  SessionShellConnector(
    this._host,
    this._delegate, {
    Uuid? uuid,
    TermuxWorkOpsBlockResolver? termuxWorkOpsBlockFor,
  }) : _uuid = uuid ?? const Uuid(),
       _termuxWorkOpsBlockFor = termuxWorkOpsBlockFor;

  final SessionLaunchHost _host;
  final SessionShellConnectorDelegate _delegate;
  final Uuid _uuid;
  final TermuxWorkOpsBlockResolver? _termuxWorkOpsBlockFor;

  ChatTabStore get _tabStore => _host.tabStore;

  bool connectShellStillValid({
    required ChatTab tab,
    required TerminalSession shell,
  }) {
    if (_host.isClosed) return false;
    if (_tabStore.activeIndexOfSession(tab.info.id) == -1) return false;
    if (shell.isDisposed) return false;
    return true;
  }

  void abortConnectShellIfStale({
    required ChatTab tab,
    required TerminalSession shell,
    required String reason,
    String? remoteMemberKey,
  }) {
    if (_host.isClosed) return;
    if (connectShellStillValid(tab: tab, shell: shell)) return;
    appLogger.d(
      '[session-launch] connectShell aborted session=${tab.info.id} '
      'reason=$reason',
    );
    if (remoteMemberKey != null) {
      unawaited(tab.closeMemberRemotePlane(remoteMemberKey));
    }
    if (_host.isSessionConnecting(tab.info.id)) {
      _host.finishSessionConnect(tab.info.id);
    }
  }

  Future<ConnectShellResult> connect({
    required ChatTab tab,
    required AppSession session,
    required TerminalSession shell,
    SessionRepository? repo,
    required bool launched,
    TeamProfile? team,
    TeamMemberConfig? member,
    Workspace? workspace,
  }) async {
    var connectSession = tab.persistedSession ?? session;
    final isPersonal = connectSession.sessionTeam.trim().isEmpty;
    final memberLabel = isPersonal
        ? connectSession.sessionId
        : (member?.id ?? '');
    appLogger.d(
      '[session-launch] connectShell start '
      'session=${tab.info.id} member=$memberLabel personal=$isPersonal '
      'launched=$launched',
    );
    if (!isPersonal && (team == null || member == null)) {
      appLogger.d(
        '[session-launch] connectShell aborted session=${tab.info.id} '
        'reason=missing_team_or_member',
      );
      _host.failSessionConnect(
        tab.info.id,
        'Team session requires team and member to connect.',
      );
      return ConnectShellResult.failed;
    }

    if (team != null && !_teamSessionPersistedEnough(connectSession)) {
      final waited = await _waitForPersistedTeamSession(tab);
      if (waited != null) connectSession = waited;
    }

    if (team != null) {
      if (connectSession.cliTeamName.isEmpty) {
        appLogger.d(
          '[session-launch] connectShell aborted session=${tab.info.id} '
          'reason=missing_cli_team_name',
        );
        _host.failSessionConnect(
          tab.info.id,
          'Session is missing CLI team identity (cliTeamName). '
          'Create a new team session.',
        );
        return ConnectShellResult.failed;
      }
      if (!connectSession.sessionId.startsWith('local-') &&
          connectSession.members.isEmpty) {
        appLogger.d(
          '[session-launch] connectShell aborted session=${tab.info.id} '
          'reason=missing_member_bindings',
        );
        _host.failSessionConnect(
          tab.info.id,
          'Session is missing member task bindings. Create a new team session.',
        );
        return ConnectShellResult.failed;
      }
    }

    final activeSession = connectSession;
    final SessionMemberBinding? binding = team != null && member != null
        ? await _resolveMemberBinding(
            session: activeSession,
            team: team,
            member: member,
            tab: tab,
            repo: repo,
          )
        : null;

    if (!connectShellStillValid(tab: tab, shell: shell)) {
      abortConnectShellIfStale(
        tab: tab,
        shell: shell,
        reason: 'tab_or_shell_gone_after_member_binding',
      );
      return ConnectShellResult.aborted;
    }

    final launchMember = member;
    final rosterMemberId = binding?.rosterMemberId;
    final launchTarget = _host.lifecycle.launchWorkTarget(
      _delegate.launchContextFor(activeSession),
      memberId: isPersonal ? null : (rosterMemberId ?? launchMember?.id),
    );
    final launchCli = isPersonal
        ? activeSession.simpleIdentity.cli
        : sessionMemberLaunchCli(
            session: activeSession,
            team: team!,
            member: launchMember!,
            globalPresets: _host.lifecycle.globalPresets,
          );
    final preflightMemberId = isPersonal
        ? activeSession.sessionId
        : (rosterMemberId ?? launchMember!.id);

    final sshMemberKey = preflightMemberId;
    String? remoteMemberKeyForRollback;
    try {
      final memberSshSession = await _beginRemoteMemberSshSession(
        tab: tab,
        memberKey: sshMemberKey,
        launchTarget: launchTarget,
      );
      if (memberSshSession != null) {
        remoteMemberKeyForRollback = sshMemberKey;
      }
      shell.sshMemberSession = memberSshSession;

      appLogger.d(
        '[session-launch] launch target resolved '
        'session=${tab.info.id} member=$preflightMemberId '
        'cli=${launchCli.value} target=${launchTarget.kind.name} '
        'targetId=${launchTarget.id}',
      );

      final termuxBlock = _termuxWorkOpsBlockFor?.call(launchTarget);
      if (termuxBlock != null) {
        appLogger.d(
          '[session-launch] connectShell aborted session=${tab.info.id} '
          'reason=termux_disconnected',
        );
        _host.failSessionConnect(tab.info.id, termuxBlock);
        return ConnectShellResult.failed;
      }

      final mixedBus =
          team != null &&
          launchMember != null &&
          team.teamMode == TeamMode.mixed &&
          tab.teamBus != null &&
          _host.teammateBusMcpGateway.isSessionRegistered(
            activeSession.sessionId,
          );
      RemoteBusBinding? remoteBinding;
      String? remoteCliPath;
      ShellLaunchSpec shellLaunch;
      final launchWarnings = <String>[];
      MemberAgentStatusEndpoint? agentStatus;

      if (isPersonal) {
        if (workspace == null) {
          _host.failSessionConnect(
            tab.info.id,
            'Simple session requires workspace to connect.',
          );
          return ConnectShellResult.failed;
        }
        agentStatus = await _resolveAgentStatusForSeat(
          tab: tab,
          sessionId: activeSession.sessionId,
          memberId: activeSession.sessionId,
          launchTarget: launchTarget,
          launchCli: launchCli,
          memberSshSession: memberSshSession,
          mixedRemoteBinding: null,
          launchWarnings: launchWarnings,
        );
        final progressMemberId = activeSession.sessionId;
        final connectResult = await _prepareConnectWithProvisionUi(
          tab: tab,
          memberId: progressMemberId,
          launchTarget: launchTarget,
          prepare: (onProgress) => _host.sessionConnect.prepareSimpleConnect(
            session: activeSession,
            workspace: workspace,
            launchTarget: launchTarget,
            agentStatus: agentStatus,
            onProvisionProgress: onProgress,
          ),
        );
        shellLaunch = connectResult.shellLaunch;
        remoteCliPath = connectResult.remoteCliPath;
        launchWarnings.addAll(connectResult.warnings);
      } else {
        if (mixedBus && memberSshSession != null) {
          appLogger.d(
            '[session-launch] mixed bus remote setup start '
            'session=${tab.info.id} member=$preflightMemberId',
          );
          final resolver = _host.remoteBusResolver;
          if (resolver != null) {
            remoteBinding = await _bindMixedRemoteBus(
              tab: tab,
              memberId: preflightMemberId,
              launchCli: launchCli,
              launchTarget: launchTarget,
              memberSshSession: memberSshSession,
              resolver: resolver,
            );
          } else {
            launchWarnings.add('remote_bus_binding_unavailable');
          }
        }
        agentStatus = await _resolveAgentStatusForSeat(
          tab: tab,
          sessionId: activeSession.sessionId,
          memberId: preflightMemberId,
          launchTarget: launchTarget,
          launchCli: launchCli,
          memberSshSession: memberSshSession,
          mixedRemoteBinding: remoteBinding,
          launchWarnings: launchWarnings,
        );
        final memberWork = activeSession.workDirsForMember(
          rosterMemberId ?? launchMember!.id,
          folders: _delegate.launchContextFor(activeSession).folderCatalog,
        );
        final progressMemberId = launchMember!.id;
        final connectResult = await _prepareConnectWithProvisionUi(
          tab: tab,
          memberId: progressMemberId,
          launchTarget: launchTarget,
          prepare: (onProgress) => _host.sessionConnect.prepareTeamConnect(
            session: activeSession,
            team: team!,
            member: launchMember,
            memberBinding: binding,
            workspace: workspace,
            launchTarget: launchTarget,
            workingDirectory: memberWork.workingDirectory,
            additionalDirectories: memberWork.addDirs,
            extraMcpServers: mixedBus
                ? {
                    teammateBusMcpServerName:
                        resolveMemberBusMcpTransportConfig(
                          cliRegistry: _host.cliRegistry,
                          endpoint: _host.teammateBusMcpGateway.mcpEndpoint,
                          sessionId: activeSession.sessionId,
                          memberId: launchMember.id,
                          cli: sessionMemberLaunchCli(
                            session: activeSession,
                            team: team,
                            member: launchMember,
                            globalPresets: _host.lifecycle.globalPresets,
                          ),
                          remoteBinding: remoteBinding,
                        ),
                  }
                : null,
            busIdle: mixedBus
                ? switch (remoteBinding) {
                    final binding? => MemberBusIdleEndpoint.remote(binding),
                    null when !usesSshTransport(launchTarget.kind) =>
                      MemberBusIdleEndpoint.local(
                        _host.teammateBusMcpGateway,
                        sessionId: activeSession.sessionId,
                      ),
                    null => null,
                  }
                : null,
            agentStatus: agentStatus,
            onProvisionProgress: onProgress,
          ),
        );
        shellLaunch = connectResult.shellLaunch;
        remoteCliPath = connectResult.remoteCliPath;
        launchWarnings.addAll(connectResult.warnings);
      }

      final agentStatusSeatMemberId = isPersonal
          ? activeSession.sessionId
          : preflightMemberId;

      if (!connectShellStillValid(tab: tab, shell: shell)) {
        abortConnectShellIfStale(
          tab: tab,
          shell: shell,
          reason: 'tab_or_shell_gone_after_prepare_connect',
          remoteMemberKey: remoteMemberKeyForRollback,
        );
        return ConnectShellResult.aborted;
      }

      if (team != null && member != null) {
        final gateStop = await _delegate.lifecycleGateBeforeAttach(
          team: team,
          member: member,
          session: activeSession,
          tab: tab,
          remoteMemberKeyForRollback: remoteMemberKeyForRollback,
        );
        if (gateStop != null) {
          remoteMemberKeyForRollback = null;
          return gateStop;
        }
      }

      if (usesSshTransport(launchTarget.kind)) {
        final injectRootSandboxEnv = await _host.isWorkspaceRootSandboxEnvOptIn(
          activeSession.workspaceId,
        );
        shellLaunch = await applyRemoteSshLaunchConstraints(
          spec: shellLaunch,
          memberTarget: launchTarget,
          memberSession: memberSshSession,
          profile: _host.shellFactory.profileFor(launchTarget),
          injectRootSandboxEnv: injectRootSandboxEnv,
        );
      }

      if (!connectShellStillValid(tab: tab, shell: shell)) {
        abortConnectShellIfStale(
          tab: tab,
          shell: shell,
          reason: 'tab_or_shell_gone_after_ssh_constraints',
          remoteMemberKey: remoteMemberKeyForRollback,
        );
        return ConnectShellResult.aborted;
      }

      // After SSH constraints may flip skip-permissions (root dropFlag).
      _registerAgentStatusSeat(
        sessionId: activeSession.sessionId,
        memberId: agentStatusSeatMemberId,
        cli: launchCli,
        skipPermissions:
            shellLaunch.launchContext.member.dangerouslySkipPermissions,
        agentStatus: agentStatus,
      );
      if (launchCli == CliTool.cursor) {
        final attention = _host.agentAttentionCubit;
        if (attention != null) {
          final sessionId = activeSession.sessionId;
          final memberId = agentStatusSeatMemberId;
          shell.bindCursorTitleAttention(
            sessionId: sessionId,
            memberId: memberId,
            attention: attention,
            skipPermissions: () =>
                _host.agentStatusSeatLookup?.resolveSkipPermissions(
                  sessionId,
                  memberId,
                ) ??
                false,
          );
        }
      }

      final plan = shellLaunch.plan;
      appLogger.d(
        '[session-launch] launch plan ready '
        'session=${tab.info.id} member=$memberLabel '
        'resume=${plan.resume} create=${plan.createSessionId ?? ''} '
        'resumeId=${plan.resumeSessionId ?? ''} warnings=${plan.warnings.length}',
      );
      final configDir = plan.memberConfigDir.trim();
      if (configDir.isNotEmpty && member != null) {
        tab.memberConfigDirs[member.id] = configDir;
        tab.memberToolConfigDir = configDir;
      }
      _host.emitLaunchWarnings([...launchWarnings, ...plan.warnings]);
      await _persistNativeSessionId(repo, tab, activeSession, binding, plan);

      if (!connectShellStillValid(tab: tab, shell: shell)) {
        abortConnectShellIfStale(
          tab: tab,
          shell: shell,
          reason: 'tab_or_shell_gone_after_persist_native_id',
          remoteMemberKey: remoteMemberKeyForRollback,
        );
        return ConnectShellResult.aborted;
      }

      final memberWork = activeSession.workDirsForMember(
        isPersonal ? null : binding?.rosterMemberId,
        folders: _delegate.launchContextFor(activeSession).folderCatalog,
      );
      appLogger.d(
        '[session-launch] shell.connect '
        'session=${tab.info.id} member=$memberLabel '
        'cwd=${memberWork.workingDirectory} addDirs=${memberWork.addDirs.length}',
      );
      // Background members never hit workbench theme sync before spawn; apply
      // here so COLORFGBG matches the embedded light/dark (Claude theme: auto).
      final launchTheme = _host.resolveTerminalThemeForLaunch();
      if (launchTheme != null) {
        applyShellTerminalThemeForLaunch(shell, launchTheme);
      }
      shell.connect(
        workingDirectory: memberWork.workingDirectory,
        additionalDirectories: memberWork.addDirs,
        executableOverride: remoteCliPath,
        fixedSessionId: plan.createSessionId,
        resumeSessionId: plan.resumeSessionId,
        shellLaunch: shellLaunch,
        extraEnvironment: plan.env.isEmpty ? null : plan.env,
        busUserInputRouting: team != null && member != null
            ? _host.teamBus.busUserInputRouting(tab, team, member)
            : null,
        onFirstUserLineSubmitted: _delegate.autoRenameOnFirstPrompt(
          activeSession.sessionId,
        ),
        onEveryUserLineSubmitted: _delegate.autoTouchOnEveryPrompt(
          activeSession.sessionId,
        ),
        onProcessFailed: (message) {
          if (remoteMemberKeyForRollback != null) {
            unawaited(tab.closeMemberRemotePlane(remoteMemberKeyForRollback));
          }
          // Non-zero exit (crash / interrupt) never fires a CLI `Stop` done
          // hook; without this the agent-status seat keeps the session lit as
          // working until the stale TTL, exactly like [onProcessExited] clears
          // on a clean exit.
          _host.clearAgentStatusSeat(
            sessionId: activeSession.sessionId,
            memberId: agentStatusSeatMemberId,
          );
          _host.failSessionConnect(tab.info.id, message);
        },
        onProcessExited: () {
          _host.clearAgentStatusSeat(
            sessionId: activeSession.sessionId,
            memberId: agentStatusSeatMemberId,
          );
          _host.updateTabRunning(tab.info.id);
        },
        onProcessStarted: () {
          if (team != null && member != null) {
            _delegate.cancelLifecycleConnectRetry(tab.info.id, member.id);
            tab.teamBus?.markMemberRunning(member.id);
            _host.memberMaterializer.markMemberReady(tab.info.id, member.id);
          } else if (isPersonal) {
            final personalMemberId = tab.selectedMemberId.trim();
            if (personalMemberId.isNotEmpty) {
              _host.memberMaterializer.markMemberReady(
                tab.info.id,
                personalMemberId,
              );
            }
          }
          _host.clearLaunchError(tab.info.id);
          _host.updateTabRunning(tab.info.id);
          _host.finishSessionConnect(tab.info.id);
          final r = repo ?? _host.sessionRepository;
          if (r != null && !activeSession.sessionId.startsWith('local-')) {
            unawaited(
              _persistSessionStarted(r, activeSession.sessionId).onError(
                (e, st) => appLogger.w(
                  '[session] persist after start failed: $e',
                  error: e,
                  stackTrace: st,
                ),
              ),
            );
          }
        },
      );
      remoteMemberKeyForRollback = null;
      return ConnectShellResult.attached;
    } on Object catch (e, st) {
      if (remoteMemberKeyForRollback != null) {
        await tab.closeMemberRemotePlane(remoteMemberKeyForRollback);
      }
      appLogger.e(
        '[session-launch] connectShell failed session=${tab.info.id} '
        'member=$memberLabel: $e',
        error: e,
        stackTrace: st,
      );
      _host.failSessionConnect(tab.info.id, 'Failed to connect session: $e');
      return ConnectShellResult.failed;
    }
  }

  Future<void> _persistNativeSessionId(
    SessionRepository? repo,
    ChatTab tab,
    AppSession session,
    SessionMemberBinding? binding,
    LaunchPlan plan,
  ) async {
    final id = plan.nativeSessionIdToPersist?.trim() ?? '';
    final tool = plan.toolValue?.trim() ?? '';
    final r = repo ?? _host.sessionRepository;
    if (r == null ||
        id.isEmpty ||
        tool.isEmpty ||
        session.sessionId.startsWith('local-')) {
      return;
    }

    AppSession applyNative(AppSession s) {
      if (binding != null) {
        return s.copyWith(
          members: [
            for (final m in s.members)
              if (m.rosterMemberId == binding.rosterMemberId)
                m.withNativeSessionId(tool, id)
              else
                m,
          ],
        );
      }
      return s.withNativeSessionId(tool, id);
    }

    final current = tab.persistedSession ?? session;
    if (identical(applyNative(current), current)) return;

    try {
      await r.recordNativeSessionId(
        session.sessionId,
        tool: tool,
        nativeId: id,
        rosterMemberId: binding?.rosterMemberId,
      );
    } on Object catch (e, st) {
      appLogger.w(
        '[session] persist native session id failed: $e',
        error: e,
        stackTrace: st,
      );
      return;
    }
    if (_host.isClosed) return;

    tab.persistedSession = applyNative(current);
    final state = _host.state;
    final sessions = state.sessions
        .map((s) => s.sessionId == session.sessionId ? applyNative(s) : s)
        .toList();
    _host.emitSnapshot(
      _host.dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
    );
  }

  Future<void> _persistSessionStarted(
    SessionRepository repo,
    String sessionId,
  ) async {
    await repo.markSessionLaunched(sessionId);
    if (_host.isClosed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final state = _host.state;
    final sessions = state.sessions.map((s) {
      if (s.sessionId != sessionId) return s;
      return s.copyWith(
        launchState: AppSessionLaunchState.started,
        updatedAt: now,
      );
    }).toList();
    // Keep the open tab's cached session in sync — history-review reconnect
    // reads tab.persistedSession for previouslyLaunched / resume decisions.
    final tab = _host.tabStore.openTabBySessionId(sessionId);
    final cached = tab?.persistedSession;
    if (tab != null && cached != null && cached.sessionId == sessionId) {
      tab.persistedSession = cached.copyWith(
        launchState: AppSessionLaunchState.started,
        updatedAt: now,
      );
    }
    _host.emitSnapshot(
      _host.dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
    );
  }

  Future<SessionMemberBinding> _resolveMemberBinding({
    required AppSession session,
    required TeamProfile team,
    required TeamMemberConfig member,
    required ChatTab tab,
    SessionRepository? repo,
  }) async {
    final type = _memberTypeForCliLock(team, member);
    final locked = memberLaunchCli(
      team: team,
      member: type,
      globalPresets: _host.lifecycle.globalPresets,
    );
    final r = repo ?? _host.sessionRepository;
    final isLocal = session.sessionId.startsWith('local-');
    if (r != null && !isLocal) {
      return r.ensureMemberBinding(
        session.sessionId,
        member.id,
        typeId: type.id,
        cli: locked,
      );
    }
    final existing = session.bindingFor(member.id);
    if (existing != null) return existing;
    final binding = SessionMemberBinding(
      rosterMemberId: member.id,
      typeId: type.id,
      taskId: _uuid.v4(),
      cli: locked,
    );
    tab.persistedSession = session.copyWith(
      members: [...session.members, binding],
    );
    return binding;
  }

  /// Resolve the roster **type** for append-time CLI lock (not a pod instance).
  TeamMemberConfig _memberTypeForCliLock(
    TeamProfile team,
    TeamMemberConfig member,
  ) {
    for (final type in team.members) {
      if (type.id == member.id) return type;
    }
    for (final inst in expandTeamRoster(team.members)) {
      if (inst.instanceId == member.id) return inst.type;
    }
    return member;
  }

  bool _teamSessionPersistedEnough(AppSession session) {
    if (session.cliTeamName.trim().isEmpty) return false;
    if (session.sessionId.startsWith('local-')) return true;
    return session.members.isNotEmpty;
  }

  Future<AppSession?> _waitForPersistedTeamSession(
    ChatTab tab, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final persisted = tab.persistedSession;
      if (persisted != null && _teamSessionPersistedEnough(persisted)) {
        return persisted;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return tab.persistedSession;
  }

  Future<
    ({ShellLaunchSpec shellLaunch, List<String> warnings, String remoteCliPath})
  >
  _prepareConnectWithProvisionUi({
    required ChatTab tab,
    required String memberId,
    required RuntimeTarget launchTarget,
    required Future<
      ({
        ShellLaunchSpec shellLaunch,
        List<String> warnings,
        String remoteCliPath,
      })
    >
    Function(void Function(CliInstallProgress progress)? onProgress)
    prepare,
  }) async {
    final hostLabel = _provisionHostLabel(launchTarget);
    MemberRemoteProvisionProgress? latest;

    void reportMemberProgress(CliInstallProgress progress) {
      latest = MemberRemoteProvisionProgress(
        memberId: memberId,
        phase: progress.phase,
        detail: progress.detail,
        hostLabel: hostLabel,
      );
      _host.setMemberRemoteProvisionProgress(tab.info.id, memberId, latest);
    }

    Future<
      ({
        ShellLaunchSpec shellLaunch,
        List<String> warnings,
        String remoteCliPath,
      })
    >
    runPrepare(void Function(CliInstallProgress progress)? onProgress) async {
      try {
        final result = await prepare(onProgress);
        _host.setMemberRemoteProvisionProgress(tab.info.id, memberId, null);
        return result;
      } on Object catch (e) {
        _host.setMemberRemoteProvisionProgress(
          tab.info.id,
          memberId,
          (latest ??
                  MemberRemoteProvisionProgress(
                    memberId: memberId,
                    phase: CliInstallPhase.locatingExecutable,
                    detail: 'connecting',
                    hostLabel: hostLabel,
                  ))
              .copyWith(error: '$e'),
        );
        rethrow;
      }
    }

    if (!usesSshTransport(launchTarget.kind)) {
      return runPrepare(null);
    }

    final adapter = _host.cliProvisionActivity;
    if (adapter == null) {
      reportMemberProgress(
        const CliInstallProgress(
          phase: CliInstallPhase.locatingExecutable,
          detail: 'connecting',
        ),
      );
      return runPrepare(reportMemberProgress);
    }

    return adapter.runTracked(
      title: hostLabel.isEmpty
          ? 'Provisioning remote environment'
          : 'Provisioning $hostLabel',
      workspaceId: tab.workspaceId.trim().isEmpty ? null : tab.workspaceId,
      historyMessageFor: (_) => hostLabel.isEmpty
          ? 'Remote environment ready'
          : 'Remote environment ready on $hostLabel',
      run: (onActivityProgress) async {
        void onProgress(CliInstallProgress progress) {
          onActivityProgress(progress);
          reportMemberProgress(progress);
        }

        onProgress(
          const CliInstallProgress(
            phase: CliInstallPhase.locatingExecutable,
            detail: 'connecting',
          ),
        );
        return runPrepare(onProgress);
      },
    );
  }

  /// Work context + reverse tunnels for a mixed remote member.
  ///
  /// Times out so a hung `forwardRemote` / SFTP resolve cannot leave the
  /// member forever in `membersPendingConnect` (builder-1 symptom).
  Future<RemoteBusBinding> _bindMixedRemoteBus({
    required ChatTab tab,
    required String memberId,
    required CliTool launchCli,
    required RuntimeTarget launchTarget,
    required SshMemberSession memberSshSession,
    required RemoteBusBindingResolver resolver,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    Future<RemoteBusBinding> run() async {
      appLogger.d(
        '[session-launch] mixed bus remote resolve-work-ctx '
        'session=${tab.info.id} member=$memberId target=${launchTarget.id}',
      );
      final workCtx = await _host.lifecycle.resolveWorkContextForTargetId(
        launchTarget.id,
      );
      appLogger.d(
        '[session-launch] mixed bus remote uname '
        'session=${tab.info.id} member=$memberId',
      );
      final arch = archFromUname(await memberSshSession.run('uname -m'));
      final mount = buildRemoteBusMount(
        memberSession: memberSshSession,
        gateway: _host.teammateBusMcpGateway,
        registration: tab.busSessionRegistration!,
        storageFs: workCtx.fs,
        arch: arch,
      );
      tab.memberRemoteBusMounts[memberId] = mount;
      appLogger.d(
        '[session-launch] mixed bus remote bind '
        'session=${tab.info.id} member=$memberId arch=$arch cli=${launchCli.value}',
      );
      final binding = await resolver.bindMember(
        mount: mount,
        memberId: memberId,
        cli: launchCli,
      );
      appLogger.d(
        '[session-launch] mixed bus remote setup ready '
        'session=${tab.info.id} member=$memberId',
      );
      return binding;
    }

    try {
      return await run().timeout(timeout);
    } on TimeoutException {
      throw TimeoutException(
        'mixed bus remote setup timed out after ${timeout.inSeconds}s '
        '(member=$memberId target=${launchTarget.id}). Check remote '
        'AllowTcpForwarding / GatewayPorts and SSH connectivity.',
        timeout,
      );
    }
  }

  /// Builds [MemberAgentStatusEndpoint] for a seat. Soft-fails status-only SSH
  /// tunnels (launch continues without attention).
  Future<MemberAgentStatusEndpoint?> _resolveAgentStatusForSeat({
    required ChatTab tab,
    required String sessionId,
    required String memberId,
    required RuntimeTarget launchTarget,
    required CliTool launchCli,
    required SshMemberSession? memberSshSession,
    required RemoteBusBinding? mixedRemoteBinding,
    required List<String> launchWarnings,
  }) async {
    final gateway = _host.teammateBusMcpGateway;
    // Local seats stamp the gateway /agent-status URL; start listeners even
    // when TeamBus was never installed (native / simple connect paths).
    await gateway.ensureStarted();
    if (!needsAgentStatusOnlyHttpTunnel(
      launchKind: launchTarget.kind,
      mixedRemoteBinding: mixedRemoteBinding,
    )) {
      return resolveMemberAgentStatusEndpoint(
        gateway: gateway,
        sessionId: sessionId,
        remoteBinding: mixedRemoteBinding,
      );
    }

    if (memberSshSession == null) {
      appLogger.w(
        '[agent-status] status-only SSH tunnel skipped '
        'session=$sessionId member=$memberId reason=no_ssh_session',
      );
      launchWarnings.add('agent_status_tunnel_unavailable');
      return null;
    }

    try {
      final token = gateway.registerAgentStatusSession(sessionId: sessionId);
      final workCtx = await _host.lifecycle.resolveWorkContextForTargetId(
        launchTarget.id,
      );
      final arch = archFromUname(await memberSshSession.run('uname -m'));
      final mount = buildStatusOnlyRemoteBusMount(
        memberSession: memberSshSession,
        gateway: gateway,
        storageFs: workCtx.fs,
        arch: arch,
        token: token,
      );
      tab.memberRemoteBusMounts[memberId] = mount;
      final binding = await mount.bindHttpMember(memberId);
      appLogger.d(
        '[agent-status] status-only SSH tunnel ready '
        'session=$sessionId member=$memberId cli=${launchCli.value}',
      );
      return MemberAgentStatusEndpoint.remote(binding);
    } on Object catch (e, st) {
      await tab.closeMemberRemoteBusMount(memberId);
      appLogger.w(
        '[agent-status] status-only SSH tunnel failed '
        'session=$sessionId member=$memberId: $e',
        error: e,
        stackTrace: st,
      );
      launchWarnings.add('agent_status_tunnel_failed');
      return null;
    }
  }

  void _registerAgentStatusSeat({
    required String sessionId,
    required String memberId,
    required CliTool cli,
    required bool skipPermissions,
    required MemberAgentStatusEndpoint? agentStatus,
  }) {
    final lookup = _host.agentStatusSeatLookup;
    if (lookup == null) return;

    final token = agentStatus?.token;
    _host.teammateBusMcpGateway.registerAgentStatusSession(
      sessionId: sessionId,
      token: token,
    );
    lookup.registerSeat(
      sessionId: sessionId,
      memberId: memberId,
      cli: cli,
      skipPermissions: skipPermissions,
    );
  }

  Future<SshMemberSession?> _beginRemoteMemberSshSession({
    required ChatTab tab,
    required String memberKey,
    required RuntimeTarget launchTarget,
  }) async {
    if (!usesSshTransport(launchTarget.kind)) return null;
    final factory = _host.shellFactory.transportFactory?.sshClientFactory;
    final profile = _host.shellFactory.profileFor(launchTarget);
    if (factory == null || profile == null) return null;

    await tab.closeMemberRemotePlane(memberKey);

    final session = await SshMemberSession.open(factory, profile);
    tab.memberSshSessions[memberKey] = session;
    return session;
  }

  /// Human-readable SSH host for provision UI. Never surfaces raw `ssh:<uuid>`.
  String _provisionHostLabel(RuntimeTarget launchTarget) {
    if (!usesSshTransport(launchTarget.kind)) return '';
    final profile = _host.shellFactory.profileFor(launchTarget);
    final name = profile?.name.trim() ?? '';
    if (name.isNotEmpty) return name;
    final host = profile?.host.trim() ?? '';
    if (host.isNotEmpty) return host;
    final label = launchTarget.label.trim();
    if (label.isNotEmpty &&
        label != launchTarget.id &&
        !label.startsWith('ssh:')) {
      return label;
    }
    return '';
  }
}
