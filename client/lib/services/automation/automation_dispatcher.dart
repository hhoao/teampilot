import 'dart:async';

import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../../cubits/chat/model/session_create_request.dart';
import '../../cubits/chat/model/session_open_request.dart';
import '../../cubits/chat/model/session_open_status.dart';
import '../../models/app_session.dart';
import '../../models/automation.dart';
import '../../models/cli_preset.dart';
import '../../models/launch_security_policy.dart';
import '../../models/session_continue_overrides.dart';
import '../../models/simple_launch_identity.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../repositories/automation_repository.dart';
import '../../repositories/session_repository.dart';
import '../../services/expert_hub/expert_landing_preflight.dart';
import '../../utils/workspace/automation_launch_directory.dart';
import '../../utils/logging/logger.dart';
import 'automation_bus_gateway.dart';
import 'automation_dispatch_result.dart';
import 'automation_launch_session_binding.dart';
import 'automation_schedule_calculator.dart';
import '../../services/cli/registry/cli_tool_registry.dart';

typedef AutomationWorkspaceResolver = Workspace? Function(String workspaceId);
typedef AutomationTeamResolver = TeamProfile? Function(String teamId);
typedef AutomationSessionLookup =
    AppSession? Function(String sessionId, String workspaceId);

int _automationDefaultNowMs() => DateTime.now().millisecondsSinceEpoch;

class AutomationDispatcher {
  AutomationDispatcher({
    required AutomationRepository repository,
    required AutomationScheduleCalculator scheduleCalculator,
    required SessionRepository sessionRepository,
    required AutomationBusGateway busGateway,
    required Future<SessionOpenStatus> Function(SessionOpenRequest)
    requestOpenSession,
    required Future<SessionOpenStatus> Function(SessionCreateRequest)
    requestCreateAndOpenSession,
    required AutomationWorkspaceResolver workspaceById,
    required AutomationTeamResolver teamById,
    CliPreset? Function(String id)? resolveCliPreset,
    AutomationSessionLookup? sessionById,
    int Function()? nowMs,
    Duration memberReadyTimeout = const Duration(seconds: 60),
    Future<T> Function<T>(
      String sessionId,
      Future<T> Function() action,
    )?
    runDeliveryInFlight,
  }) : _repository = repository,
       _scheduleCalculator = scheduleCalculator,
       _sessionRepository = sessionRepository,
       _busGateway = busGateway,
       _requestOpenSession = requestOpenSession,
       _requestCreateAndOpenSession = requestCreateAndOpenSession,
       _workspaceById = workspaceById,
       _teamById = teamById,
       _resolveCliPreset = resolveCliPreset,
       _sessionById = sessionById,
       _nowMs = nowMs ?? _automationDefaultNowMs,
       _memberReadyTimeout = memberReadyTimeout,
       _runDeliveryInFlight = runDeliveryInFlight;

  static const _uuid = Uuid();
  static const _leadMemberId = 'team-lead';

  final AutomationRepository _repository;
  final AutomationScheduleCalculator _scheduleCalculator;
  final SessionRepository _sessionRepository;
  final AutomationBusGateway _busGateway;
  final Future<SessionOpenStatus> Function(SessionOpenRequest)
  _requestOpenSession;
  final Future<SessionOpenStatus> Function(SessionCreateRequest)
  _requestCreateAndOpenSession;
  final AutomationWorkspaceResolver _workspaceById;
  final AutomationTeamResolver _teamById;
  final CliPreset? Function(String id)? _resolveCliPreset;
  final AutomationSessionLookup? _sessionById;
  final int Function() _nowMs;
  final Duration _memberReadyTimeout;
  final Future<T> Function<T>(
    String sessionId,
    Future<T> Function() action,
  )?
  _runDeliveryInFlight;

  Future<T> _inFlight<T>(
    String sessionId,
    Future<T> Function() action,
  ) {
    final run = _runDeliveryInFlight;
    if (run == null) return action();
    return run(sessionId, action);
  }

  Future<AutomationDispatchResult> dispatch(
    Automation automation, {
    AutomationRunTrigger trigger = AutomationRunTrigger.scheduled,
  }) async {
    automation.validate();
    final workspaceId = automation.workspaceId;
    final startedAtMs = _nowMs();
    final pending = _pendingRun(
      automation,
      trigger: trigger,
      startedAtMs: startedAtMs,
    );
    await _repository.upsertRun(
      workspaceId,
      pending.copyWith(status: AutomationRunStatus.dispatching),
    );

    try {
      final (finished, updated) = await _dispatchMessage(
        automation,
        pending,
        startedAtMs: startedAtMs,
      );
      await _repository.upsertRun(workspaceId, finished);
      await _repository.upsert(updated);
      return AutomationDispatchResult(run: finished, automation: updated);
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[automations] dispatch failed ${automation.id}: $error',
        error: error,
        stackTrace: stackTrace,
      );
      final failed = _finishRun(
        pending,
        AutomationRunStatus.dispatchFailed,
        startedAtMs: startedAtMs,
        error: error.toString(),
      );
      await _repository.upsertRun(workspaceId, failed);
      final updated = _advanceAutomationAfterRun(
        automation,
        lastRunAtMs: startedAtMs,
      );
      await _repository.upsert(updated);
      return AutomationDispatchResult(run: failed, automation: updated);
    }
  }

  Future<(AutomationRun, Automation)> _dispatchMessage(
    Automation automation,
    AutomationRun pending, {
    required int startedAtMs,
  }) async {
    final session = automation.isLaunchPrompt
        ? await _resolveOrCreateSession(automation)
        : await _resolveSession(automation);
    if (session == null) {
      final skipped = _finishRun(
        pending,
        AutomationRunStatus.skippedUnavailable,
        startedAtMs: startedAtMs,
        error: automation.isLaunchPrompt
            ? 'session_unavailable'
            : 'session_not_found',
      );
      final updated = _advanceAutomationAfterRun(
        automation,
        lastRunAtMs: startedAtMs,
      );
      return (skipped, updated);
    }

    final memberId = automation.isScheduledMessage
        ? await _resolveLeadMemberId(session)
        : await _resolveLaunchMemberId(automation, session);
    return _inFlight(session.sessionId, () async {
      final connected = await _ensureSessionConnected(
        session,
        memberId: memberId,
      );
      if (!connected) {
        final failed = _finishRun(
          pending,
          AutomationRunStatus.dispatchFailed,
          startedAtMs: startedAtMs,
          sessionId: session.sessionId,
          error: 'member_not_ready',
        );
        final updated = _advanceAutomationAfterRun(
          automation,
          lastRunAtMs: startedAtMs,
        );
        return (failed, updated);
      }

      await _busGateway.deliverUserCommandToMember(
        session.sessionId,
        memberId,
        automation.message,
      );
      await _repository.upsertRun(
        automation.workspaceId,
        _finishRun(
          pending,
          AutomationRunStatus.dispatched,
          startedAtMs: startedAtMs,
          sessionId: session.sessionId,
        ),
      );
      final completed = _finishRun(
        pending,
        AutomationRunStatus.completed,
        startedAtMs: startedAtMs,
        sessionId: session.sessionId,
      );
      final updated = _advanceAutomationAfterRun(
        automation,
        lastRunAtMs: startedAtMs,
        dispatchedSessionId: session.sessionId,
      );
      return (completed, updated);
    });
  }

  Future<AppSession?> _resolveSession(Automation automation) async {
    final sessionId = automation.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return null;

    AppSession? session = _sessionById?.call(sessionId, automation.workspaceId);
    session ??= (await _sessionRepository.loadSessionsForWorkspace(
      automation.workspaceId,
    )).where((s) => s.sessionId == sessionId).firstOrNull;
    if (session == null) return null;
    if (!automation.matchesSession(session)) return null;
    return session;
  }

  Future<AppSession?> _resolveOrCreateSession(Automation automation) async {
    if (automation.reuseSession) {
      final existing = await _resolveSession(automation);
      if (existing != null) return existing;
    }
    return _createSessionForLaunchPrompt(automation);
  }

  Future<AppSession?> _createSessionForLaunchPrompt(
    Automation automation,
  ) async {
    final workspace = _workspaceById(automation.workspaceId);
    if (workspace == null) return null;

    final workingDirectory = automationLaunchWorkingDirectory(
      automation,
      workspace: workspace,
    );
    final plannedSessionId = _uuid.v4();
    final SessionOpenStatus status;
    if (automation.isPersonal) {
      final presetId = automation.presetId?.trim() ?? '';
      final preset = presetId.isEmpty
          ? null
          : _resolveCliPreset?.call(presetId);
      final expertKey = resolveLandingSessionExpertKey(automation.expertKey);
      final simpleIdentity = SimpleLaunchIdentity.resolve(
        preset: preset,
        presetId: presetId,
        expertKey: expertKey,
        officialProviderId: CliToolRegistry.builtIn().defaultOfficialProviderId,
      );
      status = await _requestCreateAndOpenSession(
        SessionCreateRequest(
          workspace: workspace,
          isPersonal: true,
          repo: _sessionRepository,
          cli: simpleIdentity.cli,
          simpleIdentity: simpleIdentity,
          expertKey: expertKey,
          continueOverrides: SessionContinueOverrides(
            launchSecurityPolicy: LaunchSecurityPolicyOverride.fromPolicy(
              automation.launchSecurityPolicy,
            ),
          ),
          workingDirectory: workingDirectory,
          fixedSessionId: plannedSessionId,
        ),
      );
    } else {
      final teamId = automation.teamId?.trim() ?? '';
      if (teamId.isEmpty) return null;
      final team = _teamById(teamId);
      if (team == null) return null;
      final member = _resolveTeamMember(team, automation.targetMemberId);
      status = await _requestCreateAndOpenSession(
        SessionCreateRequest(
          workspace: workspace,
          isPersonal: false,
          team: team,
          member: member,
          repo: _sessionRepository,
          continueOverrides: SessionContinueOverrides(
            launchSecurityPolicy: LaunchSecurityPolicyOverride.fromPolicy(
              automation.launchSecurityPolicy,
            ),
          ),
          workingDirectory: workingDirectory,
          fixedSessionId: plannedSessionId,
        ),
      );
    }
    if (status != SessionOpenStatus.opened) return null;

    final fromSnapshot = _sessionById?.call(
      plannedSessionId,
      automation.workspaceId,
    );
    if (fromSnapshot != null) return fromSnapshot;

    final sessions = await _sessionRepository.loadSessionsForWorkspace(
      automation.workspaceId,
    );
    return sessions.where((s) => s.sessionId == plannedSessionId).firstOrNull;
  }

  Future<bool> _ensureSessionConnected(
    AppSession session, {
    required String memberId,
  }) async {
    final workspace = _workspaceById(session.workspaceId);
    if (workspace == null) return false;

    final isPersonal = session.sessionTeam.trim().isEmpty;
    TeamProfile? team;
    TeamMemberConfig? member;
    if (!isPersonal) {
      team = _teamById(session.sessionTeam);
      if (team == null) return false;
      member = _resolveTeamMember(team, memberId);
    }

    final status = await _requestOpenSession(
      SessionOpenRequest(
        session: session,
        workspace: workspace,
        team: team,
        member: member,
        repo: _sessionRepository,
        connectImmediately: true,
      ),
    );
    if (status != SessionOpenStatus.opened) return false;

    try {
      await _busGateway
          .ensureMemberReady(session.sessionId, memberId)
          .timeout(_memberReadyTimeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  Future<String> _resolveLeadMemberId(AppSession session) async {
    if (session.sessionTeam.trim().isEmpty) {
      return session.sessionId;
    }
    return _leadMemberId;
  }

  Future<String> _resolveLaunchMemberId(
    Automation automation,
    AppSession session,
  ) async {
    if (session.sessionTeam.trim().isEmpty) {
      return session.sessionId;
    }
    final target = automation.targetMemberId.trim();
    return target.isEmpty ? _leadMemberId : target;
  }

  TeamMemberConfig? _resolveTeamMember(TeamProfile team, String memberId) {
    final trimmed = memberId.trim();
    if (trimmed.isNotEmpty) {
      final match = team.members.where((m) => m.id == trimmed).firstOrNull;
      if (match != null && match.isValid) return match;
    }
    final lead = team.members.where((m) => m.id == _leadMemberId).firstOrNull;
    if (lead != null && lead.isValid) return lead;
    return team.members.where((m) => m.isValid).firstOrNull;
  }

  AutomationRun _pendingRun(
    Automation automation, {
    required AutomationRunTrigger trigger,
    required int startedAtMs,
  }) {
    return AutomationRun(
      id: _uuid.v4(),
      automationId: automation.id,
      workspaceId: automation.workspaceId,
      scheduledForMs: automation.nextRunAtMs ?? startedAtMs,
      status: AutomationRunStatus.pending,
      trigger: trigger,
      startedAtMs: startedAtMs,
    );
  }

  AutomationRun _finishRun(
    AutomationRun pending,
    AutomationRunStatus status, {
    required int startedAtMs,
    String? sessionId,
    String? error,
  }) {
    return pending.copyWith(
      status: status,
      sessionId: sessionId,
      error: error,
      startedAtMs: startedAtMs,
      completedAtMs: _nowMs(),
    );
  }

  Automation _advanceAutomationAfterRun(
    Automation automation, {
    required int lastRunAtMs,
    String? dispatchedSessionId,
  }) {
    final nextRunCount = automation.runCount + 1;
    final limitReached =
        automation.hasRunLimit && nextRunCount >= automation.maxRunCount!;
    final stillEnabled = automation.enabled && !limitReached;
    final nextRunAtMs = stillEnabled
        ? _scheduleCalculator.computeNextRunAtMs(
            automation,
            afterMs: lastRunAtMs,
          )
        : null;
    var updated = automation.copyWith(
      lastRunAtMs: lastRunAtMs,
      runCount: nextRunCount,
      enabled: stillEnabled,
      nextRunAtMs: nextRunAtMs,
      clearNextRunAtMs: nextRunAtMs == null,
      updatedAtMs: _nowMs(),
    );
    if (dispatchedSessionId != null && dispatchedSessionId.trim().isNotEmpty) {
      updated = AutomationLaunchSessionBinding.applyAfterSuccessfulDispatch(
        updated,
        sessionId: dispatchedSessionId,
      );
    }
    return updated;
  }
}
