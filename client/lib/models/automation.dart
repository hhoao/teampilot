import 'package:flutter/foundation.dart';

import 'app_session.dart';
import 'automation_session_match.dart';
import 'landing_launch_context.dart';
import 'launch_security_policy.dart';

enum AutomationAction { scheduledMessage, launchPrompt }

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

T _requireEnum<T extends Enum>(
  List<T> values,
  Object? raw, {
  required String field,
}) {
  final parsed = _enumByName(values, raw);
  if (parsed == null) {
    throw FormatException('Automation.$field is required');
  }
  return parsed;
}

T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
  final name = raw?.toString().trim();
  if (name == null || name.isEmpty) return null;
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
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
    required this.workspaceId,
    this.isPersonal = true,
    this.presetId,
    this.teamId,
    this.expertKey,
    this.projectFolderPath,
    this.workingDirectoryPath,
    this.launchSecurityPolicy = const LaunchSecurityPolicy(),
    this.sessionId,
    this.targetMemberId = 'team-lead',
    required this.message,
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
      action: _requireEnum(
        AutomationAction.values,
        json['action'],
        field: 'action',
      ),
      workspaceId: json['workspaceId'] as String? ?? '',
      isPersonal: json['isPersonal'] as bool? ?? true,
      presetId: json['presetId'] as String?,
      teamId: json['teamId'] as String?,
      expertKey: json['expertKey'] as String?,
      projectFolderPath: json['projectFolderPath'] as String?,
      workingDirectoryPath: json['workingDirectoryPath'] as String?,
      launchSecurityPolicy: LaunchSecurityPolicy.fromJson(
        json['launchSecurityPolicy'],
      ),
      sessionId: json['sessionId'] as String?,
      targetMemberId: json['targetMemberId'] as String? ?? 'team-lead',
      message: json['message'] as String? ?? '',
      reuseSession: json['reuseSession'] as bool? ?? false,
      preset: _requireEnum(
        AutomationSchedulePreset.values,
        json['preset'],
        field: 'preset',
      ),
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
  final String workspaceId;

  /// Simple (unteamed) vs team launch — mirrors [LandingLaunchContext.isPersonal].
  final bool isPersonal;

  /// Global CLI preset when [isPersonal].
  final String? presetId;

  /// Team identity when not [isPersonal].
  final String? teamId;

  /// Expert Hub key when [isPersonal].
  final String? expertKey;

  /// Workspace folder (git project root) for launch-prompt sessions.
  final String? projectFolderPath;

  /// Launch cwd under [projectFolderPath] (worktree path when applicable).
  final String? workingDirectoryPath;

  /// Session-level security policy for new launch-prompt sessions.
  final LaunchSecurityPolicy launchSecurityPolicy;

  final String? sessionId;
  final String targetMemberId;
  final String message;
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

  bool get isScheduledMessage => action == AutomationAction.scheduledMessage;

  bool get isLaunchPrompt => action == AutomationAction.launchPrompt;

  bool get hasRunLimit => maxRunCount != null && maxRunCount! > 0;

  bool get isRunLimitReached => hasRunLimit && runCount >= maxRunCount!;

  LandingLaunchContext get launchContext => LandingLaunchContext(
    isPersonal: isPersonal,
    presetId: presetId,
    teamId: teamId,
    projectFolderPath: projectFolderPath,
    expertKey: expertKey,
    workingDirectoryPath: workingDirectoryPath,
    launchSecurityPolicy: launchSecurityPolicy,
  );

  bool matchesSession(AppSession session) =>
      automationMatchesSession(this, session);

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
    switch (action) {
      case AutomationAction.scheduledMessage:
        if (sessionId == null || sessionId!.trim().isEmpty) {
          throw ArgumentError('scheduledMessage requires sessionId');
        }
        if (reuseSession) {
          throw ArgumentError('scheduledMessage must not reuse session');
        }
      case AutomationAction.launchPrompt:
        if (isPersonal) {
          if (presetId == null || presetId!.trim().isEmpty) {
            throw ArgumentError('launchPrompt simple mode requires presetId');
          }
        } else {
          if (teamId == null || teamId!.trim().isEmpty) {
            throw ArgumentError('launchPrompt team mode requires teamId');
          }
          if (targetMemberId.trim().isEmpty) {
            throw ArgumentError(
              'launchPrompt team mode requires targetMemberId',
            );
          }
        }
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
    String? workspaceId,
    bool? isPersonal,
    String? presetId,
    bool clearPresetId = false,
    String? teamId,
    bool clearTeamId = false,
    String? expertKey,
    bool clearExpertKey = false,
    String? projectFolderPath,
    bool clearProjectFolderPath = false,
    String? workingDirectoryPath,
    bool clearWorkingDirectoryPath = false,
    LaunchSecurityPolicy? launchSecurityPolicy,
    String? sessionId,
    bool clearSessionId = false,
    String? targetMemberId,
    String? message,
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
      workspaceId: workspaceId ?? this.workspaceId,
      isPersonal: isPersonal ?? this.isPersonal,
      presetId: clearPresetId ? null : (presetId ?? this.presetId),
      teamId: clearTeamId ? null : (teamId ?? this.teamId),
      expertKey: clearExpertKey ? null : (expertKey ?? this.expertKey),
      projectFolderPath: clearProjectFolderPath
          ? null
          : (projectFolderPath ?? this.projectFolderPath),
      workingDirectoryPath: clearWorkingDirectoryPath
          ? null
          : (workingDirectoryPath ?? this.workingDirectoryPath),
      launchSecurityPolicy: launchSecurityPolicy ?? this.launchSecurityPolicy,
      sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
      targetMemberId: targetMemberId ?? this.targetMemberId,
      message: message ?? this.message,
      reuseSession: reuseSession ?? this.reuseSession,
      preset: preset ?? this.preset,
      customCron: clearCustomCron ? null : (customCron ?? this.customCron),
      dayOfWeek: clearDayOfWeek ? null : (dayOfWeek ?? this.dayOfWeek),
      minute: minute ?? this.minute,
      hourMinute: hourMinute ?? this.hourMinute,
      timezone: timezone ?? this.timezone,
      dtstartMs: dtstartMs ?? this.dtstartMs,
      enabled: enabled ?? this.enabled,
      nextRunAtMs: clearNextRunAtMs ? null : (nextRunAtMs ?? this.nextRunAtMs),
      lastRunAtMs: clearLastRunAtMs ? null : (lastRunAtMs ?? this.lastRunAtMs),
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
      'workspaceId': workspaceId,
      if (isLaunchPrompt) ...{
        'isPersonal': isPersonal,
        if (isPersonal) ...{
          if (presetId != null && presetId!.isNotEmpty) 'presetId': presetId,
          if (expertKey != null && expertKey!.isNotEmpty)
            'expertKey': expertKey,
        } else ...{
          if (teamId != null && teamId!.isNotEmpty) 'teamId': teamId,
          'targetMemberId': targetMemberId,
        },
        'launchSecurityPolicy': launchSecurityPolicy.toJson(),
        if (reuseSession) 'reuseSession': reuseSession,
        if (projectFolderPath != null && projectFolderPath!.isNotEmpty)
          'projectFolderPath': projectFolderPath,
        if (workingDirectoryPath != null && workingDirectoryPath!.isNotEmpty)
          'workingDirectoryPath': workingDirectoryPath,
      },
      if (sessionId != null && sessionId!.isNotEmpty) 'sessionId': sessionId,
      'message': message,
      'preset': preset.name,
      if (customCron != null && customCron!.isNotEmpty)
        'customCron': customCron,
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
            workspaceId == other.workspaceId &&
            isPersonal == other.isPersonal &&
            presetId == other.presetId &&
            teamId == other.teamId &&
            expertKey == other.expertKey &&
            projectFolderPath == other.projectFolderPath &&
            workingDirectoryPath == other.workingDirectoryPath &&
            launchSecurityPolicy == other.launchSecurityPolicy &&
            sessionId == other.sessionId &&
            targetMemberId == other.targetMemberId &&
            message == other.message &&
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
    workspaceId,
    isPersonal,
    presetId,
    teamId,
    expertKey,
    projectFolderPath,
    workingDirectoryPath,
    launchSecurityPolicy,
    sessionId,
    targetMemberId,
    message,
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
      status: _requireEnum(
        AutomationRunStatus.values,
        json['status'],
        field: 'status',
      ),
      trigger: _requireEnum(
        AutomationRunTrigger.values,
        json['trigger'],
        field: 'trigger',
      ),
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
      startedAtMs: clearStartedAtMs ? null : (startedAtMs ?? this.startedAtMs),
      completedAtMs: clearCompletedAtMs
          ? null
          : (completedAtMs ?? this.completedAtMs),
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
