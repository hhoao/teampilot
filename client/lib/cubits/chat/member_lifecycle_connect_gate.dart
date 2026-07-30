import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/runtime_target.dart';
import '../../models/team_config.dart';
import '../../services/cli/preset_resolver.dart';
import '../../services/cli/registry/capabilities/cli_session_lifecycle_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/registry/config_profile/config_profile_context.dart';
import '../../services/team_bus/member_bus_idle_endpoint.dart';
import '../../services/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import 'model/chat_tab.dart';

/// Result of running the CLI session lifecycle machine before PTY attach.
sealed class LifecycleConnectGateOutcome {
  const LifecycleConnectGateOutcome();

  const factory LifecycleConnectGateOutcome.allowed() =
      LifecycleConnectGateAllowed;

  const factory LifecycleConnectGateOutcome.deferred(String reason) =
      LifecycleConnectGateDeferred;

  const factory LifecycleConnectGateOutcome.blocked(
    String reason, {
    required String userMessage,
  }) = LifecycleConnectGateBlocked;
}

final class LifecycleConnectGateAllowed extends LifecycleConnectGateOutcome {
  const LifecycleConnectGateAllowed();
}

final class LifecycleConnectGateDeferred extends LifecycleConnectGateOutcome {
  const LifecycleConnectGateDeferred(this.reason);

  final String reason;
}

final class LifecycleConnectGateBlocked extends LifecycleConnectGateOutcome {
  const LifecycleConnectGateBlocked(this.reason, {required this.userMessage});

  final String reason;
  final String userMessage;
}

/// Whether [gateConnect] denial should be retried without surfacing an error.
bool lifecycleGateReasonIsTransient(String? reason) {
  return lifecycleGateReasonNeedsMemberRetry(reason);
}

/// Per-member timer retry for bus/manifest/overlay waits.
bool lifecycleGateReasonNeedsMemberRetry(String? reason) {
  return switch (reason) {
    'overlay' || 'manifest' || 'bus' => true,
    _ => false,
  };
}

String lifecycleGateUserMessage(String? reason) {
  return switch (reason) {
    'persisted' || 'auth' =>
      'Cursor sign-in required. Add or refresh Cursor provider credentials in Settings, then retry.',
    'overlay' => 'Teammate bus is reconfiguring…',
    'manifest' => 'CLI session is still initializing…',
    'bus' => 'Teammate bus is starting…',
    final other? => 'CLI session not ready ($other).',
    null => 'CLI session not ready.',
  };
}

/// Runs ensurePersisted → initialize → gateConnect for one roster member.
final class MemberLifecycleConnectGate {
  const MemberLifecycleConnectGate({
    required this.cliRegistry,
    required this.teammateBusMcpGateway,
    required this.resolvePaths,
    required this.memberWorkDirs,
    required this.launchWorkTarget,
    required this.globalPresets,
  });

  final CliToolRegistry cliRegistry;
  final TeammateBusMcpGateway teammateBusMcpGateway;
  final Future<ConfigProfileDelegate> Function(
    AppSession session,
    String memberId,
  )
  resolvePaths;
  final ({String workingDirectory, List<String> addDirs}) Function(
    AppSession session,
    String memberId,
  )
  memberWorkDirs;
  final RuntimeTarget Function(AppSession session, {String? memberId})
  launchWorkTarget;
  final List<CliPreset> Function() globalPresets;

  Future<LifecycleConnectGateOutcome> evaluate({
    required TeamProfile team,
    required TeamMemberConfig member,
    required AppSession session,
    required ChatTab tab,
  }) async {
    if (session.sessionTeam.trim().isEmpty) {
      return const LifecycleConnectGateOutcome.allowed();
    }

    if (team.teamMode == TeamMode.mixed) {
      if (tab.teamBus == null ||
          !teammateBusMcpGateway.isSessionRegistered(session.sessionId)) {
        return const LifecycleConnectGateOutcome.deferred('bus');
      }
    }

    final cli = sessionMemberLaunchCli(
      session: session,
      team: team,
      member: member,
      globalPresets: globalPresets(),
    );
    final lifecycle = cliRegistry.lifecycleFor(cli);
    final paths = await resolvePaths(session, member.id);
    final stagedMember = memberForLaunch(
      team: team,
      member: member,
      globalPresets: globalPresets(),
    );
    final resolvedProviderId = stagedMember.provider.trim();
    final launchTarget = launchWorkTarget(session, memberId: member.id);
    final memberWork = memberWorkDirs(session, member.id);
    final busIdle = team.teamMode == TeamMode.mixed &&
            !usesSshTransport(launchTarget.kind)
        ? MemberBusIdleEndpoint.local(
            teammateBusMcpGateway,
            sessionId: session.sessionId,
          )
        : null;

    await lifecycle.ensurePersisted(
      CliSessionPersistContext(
        workspaceId: session.workspaceId,
        sessionId: session.sessionId,
        memberId: member.id,
        tool: cli,
        paths: paths,
        team: team,
        busIdle: busIdle,
        workingDirectory: memberWork.workingDirectory,
        crossMachine: usesSshTransport(launchTarget.kind),
      ),
    );

    await lifecycle.initialize(
      CliSessionInitContext(
        workspaceId: session.workspaceId,
        sessionId: session.sessionId,
        memberId: member.id,
        tool: cli,
        paths: paths,
        team: team,
        busIdle: busIdle,
        workingDirectory: memberWork.workingDirectory,
        crossMachine: usesSshTransport(launchTarget.kind),
        resolvedProviderId:
            resolvedProviderId.isNotEmpty ? resolvedProviderId : null,
        credentialBasePath: paths.basePath,
      ),
    );

    final gate = lifecycle.gateConnect(
      CliSessionGateContext(
        workspaceId: session.workspaceId,
        sessionId: session.sessionId,
        memberId: member.id,
        tool: cli,
        paths: paths,
        team: team,
        busIdle: busIdle,
        workingDirectory: memberWork.workingDirectory,
        crossMachine: usesSshTransport(launchTarget.kind),
      ),
    );
    if (gate.allowed) return const LifecycleConnectGateOutcome.allowed();

    final reason = gate.reason ?? 'unknown';
    if (lifecycleGateReasonIsTransient(reason)) {
      return LifecycleConnectGateOutcome.deferred(reason);
    }
    return LifecycleConnectGateOutcome.blocked(
      reason,
      userMessage: lifecycleGateUserMessage(reason),
    );
  }

  /// Compose-landing PTY inject: lifecycle phase is ready/degraded and gate allows attach.
  Future<bool> evaluateDirectPtyInputReady({
    required TeamProfile team,
    required TeamMemberConfig member,
    required AppSession session,
    required ChatTab tab,
  }) async {
    if (session.sessionTeam.trim().isEmpty) return true;

    if (team.teamMode == TeamMode.mixed) {
      if (tab.teamBus == null ||
          !teammateBusMcpGateway.isSessionRegistered(session.sessionId)) {
        return false;
      }
    }

    final cli = sessionMemberLaunchCli(
      session: session,
      team: team,
      member: member,
      globalPresets: globalPresets(),
    );
    final lifecycle = cliRegistry.lifecycleFor(cli);
    final paths = await resolvePaths(session, member.id);
    final launchTarget = launchWorkTarget(session, memberId: member.id);
    final memberWork = memberWorkDirs(session, member.id);
    final busIdle = team.teamMode == TeamMode.mixed &&
            !usesSshTransport(launchTarget.kind)
        ? MemberBusIdleEndpoint.local(
            teammateBusMcpGateway,
            sessionId: session.sessionId,
          )
        : null;
    final gateCtx = CliSessionGateContext(
      workspaceId: session.workspaceId,
      sessionId: session.sessionId,
      memberId: member.id,
      tool: cli,
      paths: paths,
      team: team,
      busIdle: busIdle,
      workingDirectory: memberWork.workingDirectory,
      crossMachine: usesSshTransport(launchTarget.kind),
    );

    final phase = lifecycle.peekSessionPhase(gateCtx);
    if (phase != null &&
        phase != CliSessionPhase.ready &&
        phase != CliSessionPhase.degraded) {
      return false;
    }

    return lifecycle.gateConnect(gateCtx).allowed;
  }
}
