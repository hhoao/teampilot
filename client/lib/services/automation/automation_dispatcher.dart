import 'dart:async';

import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../../cubits/chat/model/session_create_request.dart';
import '../../cubits/chat/model/session_open_request.dart';
import '../../cubits/chat/model/session_open_status.dart';
import '../../models/app_session.dart';
import '../../models/automation.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../repositories/automation_repository.dart';
import '../../repositories/session_repository.dart';
import '../../services/launch/personal_launch_context_resolver.dart';
import '../../utils/logger.dart';
import 'automation_bus_gateway.dart';
import 'automation_dispatch_result.dart';
import 'automation_schedule_calculator.dart';

typedef AutomationWorkspaceResolver = Workspace? Function(String workspaceId);
typedef AutomationTeamResolver = TeamProfile? Function(String teamId);
typedef AutomationSessionLookup = AppSession? Function(
  String sessionId,
  String workspaceId,
);

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
    PersonalLaunchContextResolver? personalContextResolver,
    AutomationSessionLookup? sessionById,
    int Function()? nowMs,
    Duration memberReadyTimeout = const Duration(seconds: 60),
  })  : _repository = repository,
        _scheduleCalculator = scheduleCalculator,
        _sessionRepository = sessionRepository,
        _busGateway = busGateway,
        _requestOpenSession = requestOpenSession,
        _requestCreateAndOpenSession = requestCreateAndOpenSession,
        _workspaceById = workspaceById,
        _teamById = teamById,
        _personalContextResolver = personalContextResolver,
        _sessionById = sessionById,
        _nowMs = nowMs ?? _automationDefaultNowMs,
        _memberReadyTimeout = memberReadyTimeout;

  static const _uuid = Uuid();

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
  final PersonalLaunchContextResolver? _personalContextResolver;
  final AutomationSessionLookup? _sessionById;
  final int Function() _nowMs;
  final Duration _memberReadyTimeout;

  Future<AutomationDispatchResult> dispatch(
    Automation automation, {
    AutomationRunTrigger trigger = AutomationRunTrigger.scheduled,
  }) async {
    automation.validate();
    final startedAtMs = _nowMs();
    final pending = _pendingRun(
      automation,
      trigger: trigger,
      startedAtMs: startedAtMs,
    );
    await _repository.upsertRun(
      automation.workspaceId,
      pending.copyWith(status: AutomationRunStatus.dispatching),
    );

    try {
      final AutomationRun finished;
      final Automation updated;
      switch (automation.action) {
        case AutomationAction.sendToLead:
          (finished, updated) = await _dispatchSendToLead(
            automation,
            pending,
            startedAtMs: startedAtMs,
          );
        case AutomationAction.launchPrompt:
          (finished, updated) = await _dispatchLaunchPrompt(
            automation,
            pending,
            startedAtMs: startedAtMs,
          );
      }
      await _repository.upsertRun(automation.workspaceId, finished);
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
      await _repository.upsertRun(automation.workspaceId, failed);
      final updated = _advanceAutomationAfterRun(
        automation,
        lastRunAtMs: startedAtMs,
      );
      await _repository.upsert(updated);
      return AutomationDispatchResult(run: failed, automation: updated);
    }
  }

  Future<(AutomationRun, Automation)> _dispatchSendToLead(
    Automation automation,
    AutomationRun pending, {
    required int startedAtMs,
  }) async {
    final session = await _resolveSession(automation);
    if (session == null) {
      final skipped = _finishRun(
        pending,
        AutomationRunStatus.skippedUnavailable,
        startedAtMs: startedAtMs,
        error: 'session_not_found',
      );
      final updated = _advanceAutomationAfterRun(
        automation,
        lastRunAtMs: startedAtMs,
      );
      return (skipped, updated);
    }

    final memberId = await _resolveMemberId(automation, session);
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
        error: 'member_connect_timeout',
      );
      final updated = _advanceAutomationAfterRun(
        automation,
        lastRunAtMs: startedAtMs,
      );
      return (failed, updated);
    }

    _busGateway.deliverUserCommandToMember(
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
    );
    return (completed, updated);
  }

  Future<(AutomationRun, Automation)> _dispatchLaunchPrompt(
    Automation automation,
    AutomationRun pending, {
    required int startedAtMs,
  }) async {
    final session = await _resolveOrCreateSession(automation);
    if (session == null) {
      final skipped = _finishRun(
        pending,
        AutomationRunStatus.skippedUnavailable,
        startedAtMs: startedAtMs,
        error: 'session_unavailable',
      );
      final updated = _advanceAutomationAfterRun(
        automation,
        lastRunAtMs: startedAtMs,
      );
      return (skipped, updated);
    }

    final memberId = await _resolveMemberId(automation, session);
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
        error: 'member_connect_timeout',
      );
      final updated = _advanceAutomationAfterRun(
        automation,
        lastRunAtMs: startedAtMs,
      );
      return (failed, updated);
    }

    _busGateway.deliverUserCommandToMember(
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
    );
    return (completed, updated);
  }

  Future<AppSession?> _resolveSession(Automation automation) async {
    final sessionId = automation.sessionId?.trim();
    if (sessionId == null || sessionId.isEmpty) return null;
    final fromSnapshot = _sessionById?.call(sessionId, automation.workspaceId);
    if (fromSnapshot != null) return fromSnapshot;
    final sessions = await _sessionRepository.loadSessionsForWorkspace(
      automation.workspaceId,
    );
    return sessions.where((s) => s.sessionId == sessionId).firstOrNull;
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

    final plannedSessionId = _uuid.v4();
    final teamId = workspace.defaultProfileId.trim();
    final SessionOpenStatus status;
    if (teamId.isNotEmpty) {
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
          cli: automation.cli,
          fixedSessionId: plannedSessionId,
        ),
      );
    } else {
      status = await _requestCreateAndOpenSession(
        SessionCreateRequest(
          workspace: workspace,
          isPersonal: true,
          repo: _sessionRepository,
          cli: automation.cli,
          fixedSessionId: plannedSessionId,
        ),
      );
    }
    if (status != SessionOpenStatus.opened) return null;

    final fromSnapshot =
        _sessionById?.call(plannedSessionId, automation.workspaceId);
    if (fromSnapshot != null) return fromSnapshot;

    final sessions = await _sessionRepository.loadSessionsForWorkspace(
      automation.workspaceId,
    );
    return sessions
        .where((s) => s.sessionId == plannedSessionId)
        .firstOrNull;
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

  Future<String> _resolveMemberId(Automation automation, AppSession session) async {
    if (session.sessionTeam.trim().isEmpty) {
      final workspace = _workspaceById(session.workspaceId);
      final resolver = _personalContextResolver;
      if (workspace != null && resolver != null) {
        final ctx = await resolver.resolve(
          session: session,
          workspace: workspace,
        );
        return ctx.personalMember.id;
      }
      return session.sessionId;
    }
    final target = automation.targetMemberId.trim();
    return target.isEmpty ? 'team-lead' : target;
  }

  TeamMemberConfig? _resolveTeamMember(
    TeamProfile team,
    String memberId,
  ) {
    final trimmed = memberId.trim();
    if (trimmed.isNotEmpty) {
      final match = team.members.where((m) => m.id == trimmed).firstOrNull;
      if (match != null && match.isValid) return match;
    }
    final lead = team.members.where((m) => m.id == 'team-lead').firstOrNull;
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
    return automation.copyWith(
      lastRunAtMs: lastRunAtMs,
      runCount: nextRunCount,
      enabled: stillEnabled,
      nextRunAtMs: nextRunAtMs,
      clearNextRunAtMs: nextRunAtMs == null,
      updatedAtMs: _nowMs(),
    );
  }
}
