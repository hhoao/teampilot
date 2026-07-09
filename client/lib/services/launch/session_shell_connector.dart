import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../cubits/chat/chat_tab_store.dart';
import '../../cubits/chat/model/chat_tab.dart';
import '../../cubits/chat/session_launch_host.dart';
import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/personal_profile.dart';
import '../../models/runtime_target.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../models/workspace_launch_context.dart';
import '../../repositories/session_repository.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/launch/connect_shell_result.dart';
import '../../services/launch/member_bus_mcp_transport_resolver.dart';
import '../../services/session/shell_launch_spec.dart';
import '../../services/session/remote_ssh_launch_constraints.dart';
import '../../services/ssh/ssh_member_session.dart';
import '../../services/team_bus/member_bus_idle_endpoint.dart';
import '../../services/team_bus/remote/member_bus_mcp_config.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_config.dart';
import '../../services/team_bus/remote/remote_bus_mount.dart';
import '../../services/team_bus/remote/ssh_remote_bus_mount_factory.dart';
import '../../services/terminal/terminal_session.dart';
import '../../services/terminal/terminal_theme_for_launch.dart';
import '../../utils/logger.dart';

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
  }) : _uuid = uuid ?? const Uuid();

  final SessionLaunchHost _host;
  final SessionShellConnectorDelegate _delegate;
  final Uuid _uuid;

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
    if (_host.state.sessionConnectingId == tab.info.id) {
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
    PersonalProfile? personal,
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
    if (isPersonal) {
      if (personal == null) {
        appLogger.d(
          '[session-launch] connectShell aborted session=${tab.info.id} '
          'reason=missing_personal_identity',
        );
        _host.failSessionConnect(
          tab.info.id,
          'Personal session is missing personal identity.',
        );
        return ConnectShellResult.failed;
      }
    } else if (team == null || member == null) {
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
    CliPreset? personalLaunchPreset;
    if (isPersonal) {
      final pinnedPresetId = tab.personalPresetId?.trim() ?? '';
      personalLaunchPreset = pinnedPresetId.isNotEmpty
          ? await _host.lifecycle.resolvePresetById(pinnedPresetId)
          : await _host.lifecycle.resolveActivePresetForSession(
              activeSession,
              personal!,
            );
    }
    final launchCli = isPersonal
        ? (personalLaunchPreset?.cli ?? activeSession.cli ?? CliTool.claude)
        : memberLaunchCli(
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

      final mixedBus =
          team != null &&
          launchMember != null &&
          team.teamMode == TeamMode.mixed &&
          tab.teamBus != null &&
          _host.teammateBusMcpGateway.isSessionRegistered(activeSession.sessionId);
      RemoteBusBinding? remoteBinding;
      String? remoteCliPath;
      ShellLaunchSpec shellLaunch;
      final launchWarnings = <String>[];

      if (isPersonal) {
        final connectResult = await _host.sessionConnect.preparePersonalConnect(
          session: activeSession,
          workspace: workspace!,
          personal: personal!,
          preset: personalLaunchPreset,
          launchTarget: launchTarget,
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
            final workCtx = await _host.lifecycle.resolveWorkContextForTargetId(
              launchTarget.id,
            );
            final arch = archFromUname(await memberSshSession.run('uname -m'));
            final mount = buildRemoteBusMount(
              memberSession: memberSshSession,
              gateway: _host.teammateBusMcpGateway,
              registration: tab.busSessionRegistration!,
              storageFs: workCtx.fs,
              arch: arch,
            );
            tab.memberRemoteBusMounts[preflightMemberId] = mount;
            remoteBinding = await resolver.bindMember(
              mount: mount,
              memberId: preflightMemberId,
              cli: launchCli,
            );
          } else {
            launchWarnings.add('remote_bus_binding_unavailable');
          }
        }
        final memberWork = activeSession.workDirsForMember(
          rosterMemberId ?? launchMember!.id,
          folders: _delegate.launchContextFor(activeSession).folderCatalog,
        );
        final connectResult = await _host.sessionConnect.prepareTeamConnect(
          session: activeSession,
          team: team!,
          member: launchMember!,
          memberBinding: binding,
          workspace: workspace,
          launchTarget: launchTarget,
          workingDirectory: memberWork.workingDirectory,
          additionalDirectories: memberWork.addDirs,
          extraMcpServers: mixedBus
              ? {
                  teammateBusMcpServerName: resolveMemberBusMcpTransportConfig(
                    cliRegistry: _host.cliRegistry,
                    endpoint: _host.teammateBusMcpGateway.mcpEndpoint,
                    sessionId: activeSession.sessionId,
                    memberId: launchMember.id,
                    cli: memberLaunchCli(
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
                  null when launchTarget.kind != RuntimeKind.ssh =>
                    MemberBusIdleEndpoint.local(
                      _host.teammateBusMcpGateway,
                      sessionId: activeSession.sessionId,
                    ),
                  null => null,
                }
              : null,
        );
        shellLaunch = connectResult.shellLaunch;
        remoteCliPath = connectResult.remoteCliPath;
        launchWarnings.addAll(connectResult.warnings);
      }

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

      if (launchTarget.kind == RuntimeKind.ssh) {
        final injectRootSandboxEnv = await _host.isRootSandboxEnvOptIn(
          launchTarget.id,
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
          _host.failSessionConnect(tab.info.id, message);
        },
        onProcessExited: () => _host.updateTabRunning(tab.info.id),
        onProcessStarted: () {
          if (team != null && member != null) {
            _delegate.cancelLifecycleConnectRetry(tab.info.id, member.id);
            tab.teamBus?.markMemberRunning(member.id);
            _host.memberMaterializer.markMemberReady(tab.info.id, member.id);
          } else if (isPersonal) {
            tab.personalPresetId = null;
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
    _host.emitSnapshot(
      _host.dataStore.deriveSnapshot(
        workspaces: state.workspaces,
        sessions: sessions,
      ),
    );
  }

  Future<SessionMemberBinding> _resolveMemberBinding({
    required AppSession session,
    required TeamMemberConfig member,
    required ChatTab tab,
    SessionRepository? repo,
  }) async {
    final r = repo ?? _host.sessionRepository;
    final isLocal = session.sessionId.startsWith('local-');
    if (r != null && !isLocal) {
      return r.ensureMemberBinding(session.sessionId, member.id);
    }
    final existing = session.bindingFor(member.id);
    if (existing != null) return existing;
    final binding = SessionMemberBinding(
      rosterMemberId: member.id,
      taskId: _uuid.v4(),
    );
    tab.persistedSession = session.copyWith(
      members: [...session.members, binding],
    );
    return binding;
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

  Future<SshMemberSession?> _beginRemoteMemberSshSession({
    required ChatTab tab,
    required String memberKey,
    required RuntimeTarget launchTarget,
  }) async {
    if (launchTarget.kind != RuntimeKind.ssh) return null;
    final factory = _host.shellFactory.transportFactory?.sshClientFactory;
    final profile = _host.shellFactory.profileFor(launchTarget);
    if (factory == null || profile == null) return null;

    await tab.closeMemberRemotePlane(memberKey);

    final session = await SshMemberSession.open(factory, profile);
    tab.memberSshSessions[memberKey] = session;
    return session;
  }
}
