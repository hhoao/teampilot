import 'package:flutter/foundation.dart';

import 'team_config.dart';

enum AutomationAction { sendToLead, launchPrompt }

enum AutomationScope { session, workspace }

enum AutomationSchedulePreset { hourly, daily, weekdays, weekly, custom }

enum AutomationRunStatus {
  pending,
  dispatching,
  dispatched,
  completed,
  skippedUnavailable,
  skippedMissed,
  dispatchFailed,
}

enum AutomationRunTrigger { scheduled, manual }

T? _enumByName<T extends Enum>(List<T> values, Object? raw, {T? fallback}) {
  final name = raw?.toString().trim();
  if (name == null || name.isEmpty) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

String _defaultAutomationTimezone(Object? raw) {
  final stored = raw?.toString().trim();
  if (stored != null && stored.isNotEmpty) return stored;
  final local = DateTime.now().timeZoneName.trim();
  return local.isEmpty ? 'UTC' : local;
}

@immutable
class Automation {
  const Automation({
    required this.id,
    required this.name,
    required this.action,
    required this.scope,
    required this.workspaceId,
    this.sessionId,
    this.targetMemberId = 'team-lead',
    required this.message,
    this.cli,
    this.reuseSession = false,
    required this.preset,
    this.customCron,
    this.dayOfWeek,
    this.minute = 0,
    this.hourMinute = '09:00',
    required this.timezone,
    required this.dtstartMs,
    this.enabled = true,
    this.nextRunAtMs,
    this.lastRunAtMs,
    this.missedRunGraceMinutes = 15,
    this.maxRunCount,
    this.runCount = 0,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  factory Automation.fromJson(Map<String, Object?> json) {
    return Automation(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      action: _enumByName(
            AutomationAction.values,
            json['action'],
            fallback: AutomationAction.sendToLead,
          ) ??
          AutomationAction.sendToLead,
      scope: _enumByName(
            AutomationScope.values,
            json['scope'],
            fallback: AutomationScope.workspace,
          ) ??
          AutomationScope.workspace,
      workspaceId: json['workspaceId'] as String? ?? '',
      sessionId: json['sessionId'] as String?,
      targetMemberId: json['targetMemberId'] as String? ?? 'team-lead',
      message: json['message'] as String? ?? '',
      cli: json['cli'] == null ? null : CliTool.parse(json['cli']),
      reuseSession: json['reuseSession'] as bool? ?? false,
      preset: _enumByName(
            AutomationSchedulePreset.values,
            json['preset'],
            fallback: AutomationSchedulePreset.daily,
          ) ??
          AutomationSchedulePreset.daily,
      customCron: json['customCron'] as String?,
      dayOfWeek: (json['dayOfWeek'] as num?)?.toInt(),
      minute: (json['minute'] as num?)?.toInt() ?? 0,
      hourMinute: json['hourMinute'] as String? ?? '09:00',
      timezone: _defaultAutomationTimezone(json['timezone']),
      dtstartMs: (json['dtstartMs'] as num?)?.toInt() ?? 0,
      enabled: json['enabled'] as bool? ?? true,
      nextRunAtMs: (json['nextRunAtMs'] as num?)?.toInt(),
      lastRunAtMs: (json['lastRunAtMs'] as num?)?.toInt(),
      missedRunGraceMinutes:
          (json['missedRunGraceMinutes'] as num?)?.toInt() ?? 15,
      maxRunCount: (json['maxRunCount'] as num?)?.toInt(),
      runCount: (json['runCount'] as num?)?.toInt() ?? 0,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String name;
  final AutomationAction action;
  final AutomationScope scope;
  final String workspaceId;
  final String? sessionId;
  final String targetMemberId;
  final String message;
  final CliTool? cli;
  final bool reuseSession;
  final AutomationSchedulePreset preset;
  final String? customCron;
  final int? dayOfWeek;
  final int minute;
  final String hourMinute;
  final String timezone;
  final int dtstartMs;
  final bool enabled;
  final int? nextRunAtMs;
  final int? lastRunAtMs;
  final int missedRunGraceMinutes;
  final int? maxRunCount;
  final int runCount;
  final int createdAtMs;
  final int updatedAtMs;

  /// When set, automation stops after [runCount] reaches [maxRunCount].
  bool get hasRunLimit => maxRunCount != null && maxRunCount! > 0;

  bool get isRunLimitReached => hasRunLimit && runCount >= maxRunCount!;

  void validate() {
    if (id.trim().isEmpty) {
      throw ArgumentError('Automation id is required');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError('Automation name is required');
    }
    if (workspaceId.trim().isEmpty) {
      throw ArgumentError('Automation workspaceId is required');
    }
    if (message.trim().isEmpty) {
      throw ArgumentError('Automation message is required');
    }
    if (scope == AutomationScope.session &&
        (sessionId == null || sessionId!.trim().isEmpty)) {
      throw ArgumentError('session scope requires sessionId');
    }
    if (action == AutomationAction.launchPrompt && cli == null) {
      throw ArgumentError('launchPrompt requires cli');
    }
    if (preset == AutomationSchedulePreset.custom &&
        (customCron == null || customCron!.trim().isEmpty)) {
      throw ArgumentError('custom preset requires customCron');
    }
    if (preset == AutomationSchedulePreset.weekly &&
        (dayOfWeek == null || dayOfWeek! < 1 || dayOfWeek! > 7)) {
      throw ArgumentError('weekly preset requires dayOfWeek 1..7');
    }
    if (minute < 0 || minute > 59) {
      throw ArgumentError('minute must be 0..59');
    }
    if (timezone.trim().isEmpty) {
      throw ArgumentError('timezone is required');
    }
    if (maxRunCount != null && maxRunCount! < 1) {
      throw ArgumentError('maxRunCount must be >= 1 when set');
    }
    if (runCount < 0) {
      throw ArgumentError('runCount must be >= 0');
    }
  }

  Automation copyWith({
    String? id,
    String? name,
    AutomationAction? action,
    AutomationScope? scope,
    String? workspaceId,
    String? sessionId,
    bool clearSessionId = false,
    String? targetMemberId,
    String? message,
    CliTool? cli,
    bool clearCli = false,
    bool? reuseSession,
    AutomationSchedulePreset? preset,
    String? customCron,
    bool clearCustomCron = false,
    int? dayOfWeek,
    bool clearDayOfWeek = false,
    int? minute,
    String? hourMinute,
    String? timezone,
    int? dtstartMs,
    bool? enabled,
    int? nextRunAtMs,
    bool clearNextRunAtMs = false,
    int? lastRunAtMs,
    bool clearLastRunAtMs = false,
    int? missedRunGraceMinutes,
    int? maxRunCount,
    bool clearMaxRunCount = false,
    int? runCount,
    int? createdAtMs,
    int? updatedAtMs,
  }) {
    return Automation(
      id: id ?? this.id,
      name: name ?? this.name,
      action: action ?? this.action,
      scope: scope ?? this.scope,
      workspaceId: workspaceId ?? this.workspaceId,
      sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
      targetMemberId: targetMemberId ?? this.targetMemberId,
      message: message ?? this.message,
      cli: clearCli ? null : (cli ?? this.cli),
      reuseSession: reuseSession ?? this.reuseSession,
      preset: preset ?? this.preset,
      customCron: clearCustomCron ? null : (customCron ?? this.customCron),
      dayOfWeek: clearDayOfWeek ? null : (dayOfWeek ?? this.dayOfWeek),
      minute: minute ?? this.minute,
      hourMinute: hourMinute ?? this.hourMinute,
      timezone: timezone ?? this.timezone,
      dtstartMs: dtstartMs ?? this.dtstartMs,
      enabled: enabled ?? this.enabled,
      nextRunAtMs:
          clearNextRunAtMs ? null : (nextRunAtMs ?? this.nextRunAtMs),
      lastRunAtMs:
          clearLastRunAtMs ? null : (lastRunAtMs ?? this.lastRunAtMs),
      missedRunGraceMinutes:
          missedRunGraceMinutes ?? this.missedRunGraceMinutes,
      maxRunCount: clearMaxRunCount ? null : (maxRunCount ?? this.maxRunCount),
      runCount: runCount ?? this.runCount,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'action': action.name,
      'scope': scope.name,
      'workspaceId': workspaceId,
      if (sessionId != null && sessionId!.isNotEmpty) 'sessionId': sessionId,
      'targetMemberId': targetMemberId,
      'message': message,
      if (cli != null) 'cli': cli!.value,
      'reuseSession': reuseSession,
      'preset': preset.name,
      if (customCron != null && customCron!.isNotEmpty) 'customCron': customCron,
      if (dayOfWeek != null) 'dayOfWeek': dayOfWeek,
      'minute': minute,
      'hourMinute': hourMinute,
      'timezone': timezone,
      'dtstartMs': dtstartMs,
      'enabled': enabled,
      if (nextRunAtMs != null) 'nextRunAtMs': nextRunAtMs,
      if (lastRunAtMs != null) 'lastRunAtMs': lastRunAtMs,
      'missedRunGraceMinutes': missedRunGraceMinutes,
      if (maxRunCount != null) 'maxRunCount': maxRunCount,
      if (runCount > 0) 'runCount': runCount,
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Automation &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            name == other.name &&
            action == other.action &&
            scope == other.scope &&
            workspaceId == other.workspaceId &&
            sessionId == other.sessionId &&
            targetMemberId == other.targetMemberId &&
            message == other.message &&
            cli == other.cli &&
            reuseSession == other.reuseSession &&
            preset == other.preset &&
            customCron == other.customCron &&
            dayOfWeek == other.dayOfWeek &&
            minute == other.minute &&
            hourMinute == other.hourMinute &&
            timezone == other.timezone &&
            dtstartMs == other.dtstartMs &&
            enabled == other.enabled &&
            nextRunAtMs == other.nextRunAtMs &&
            lastRunAtMs == other.lastRunAtMs &&
            missedRunGraceMinutes == other.missedRunGraceMinutes &&
            maxRunCount == other.maxRunCount &&
            runCount == other.runCount &&
            createdAtMs == other.createdAtMs &&
            updatedAtMs == other.updatedAtMs;
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        name,
        action,
        scope,
        workspaceId,
        sessionId,
        targetMemberId,
        message,
        cli,
        reuseSession,
        preset,
        customCron,
        dayOfWeek,
        minute,
        hourMinute,
        timezone,
        dtstartMs,
        enabled,
        nextRunAtMs,
        lastRunAtMs,
        missedRunGraceMinutes,
        maxRunCount,
        runCount,
        createdAtMs,
        updatedAtMs,
      ]);
}

@immutable
class AutomationRun {
  const AutomationRun({
    required this.id,
    required this.automationId,
    required this.workspaceId,
    required this.scheduledForMs,
    required this.status,
    required this.trigger,
    this.sessionId,
    this.error,
    this.startedAtMs,
    this.completedAtMs,
  });

  factory AutomationRun.fromJson(Map<String, Object?> json) {
    return AutomationRun(
      id: json['id'] as String? ?? '',
      automationId: json['automationId'] as String? ?? '',
      workspaceId: json['workspaceId'] as String? ?? '',
      scheduledForMs: (json['scheduledForMs'] as num?)?.toInt() ?? 0,
      status: _enumByName(
            AutomationRunStatus.values,
            json['status'],
            fallback: AutomationRunStatus.pending,
          ) ??
          AutomationRunStatus.pending,
      trigger: _enumByName(
            AutomationRunTrigger.values,
            json['trigger'],
            fallback: AutomationRunTrigger.scheduled,
          ) ??
          AutomationRunTrigger.scheduled,
      sessionId: json['sessionId'] as String?,
      error: json['error'] as String?,
      startedAtMs: (json['startedAtMs'] as num?)?.toInt(),
      completedAtMs: (json['completedAtMs'] as num?)?.toInt(),
    );
  }

  final String id;
  final String automationId;
  final String workspaceId;
  final int scheduledForMs;
  final AutomationRunStatus status;
  final AutomationRunTrigger trigger;
  final String? sessionId;
  final String? error;
  final int? startedAtMs;
  final int? completedAtMs;

  AutomationRun copyWith({
    String? id,
    String? automationId,
    String? workspaceId,
    int? scheduledForMs,
    AutomationRunStatus? status,
    AutomationRunTrigger? trigger,
    String? sessionId,
    bool clearSessionId = false,
    String? error,
    bool clearError = false,
    int? startedAtMs,
    bool clearStartedAtMs = false,
    int? completedAtMs,
    bool clearCompletedAtMs = false,
  }) {
    return AutomationRun(
      id: id ?? this.id,
      automationId: automationId ?? this.automationId,
      workspaceId: workspaceId ?? this.workspaceId,
      scheduledForMs: scheduledForMs ?? this.scheduledForMs,
      status: status ?? this.status,
      trigger: trigger ?? this.trigger,
      sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
      error: clearError ? null : (error ?? this.error),
      startedAtMs:
          clearStartedAtMs ? null : (startedAtMs ?? this.startedAtMs),
      completedAtMs:
          clearCompletedAtMs ? null : (completedAtMs ?? this.completedAtMs),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'automationId': automationId,
      'workspaceId': workspaceId,
      'scheduledForMs': scheduledForMs,
      'status': status.name,
      'trigger': trigger.name,
      if (sessionId != null && sessionId!.isNotEmpty) 'sessionId': sessionId,
      if (error != null && error!.isNotEmpty) 'error': error,
      if (startedAtMs != null) 'startedAtMs': startedAtMs,
      if (completedAtMs != null) 'completedAtMs': completedAtMs,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AutomationRun &&
            runtimeType == other.runtimeType &&
            id == other.id &&
            automationId == other.automationId &&
            workspaceId == other.workspaceId &&
            scheduledForMs == other.scheduledForMs &&
            status == other.status &&
            trigger == other.trigger &&
            sessionId == other.sessionId &&
            error == other.error &&
            startedAtMs == other.startedAtMs &&
            completedAtMs == other.completedAtMs;
  }

  @override
  int get hashCode => Object.hash(
        id,
        automationId,
        workspaceId,
        scheduledForMs,
        status,
        trigger,
        sessionId,
        error,
        startedAtMs,
        completedAtMs,
      );
}
