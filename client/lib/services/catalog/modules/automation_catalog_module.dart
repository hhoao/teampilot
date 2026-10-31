import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../../../models/automation.dart';
import '../../../repositories/automation_repository.dart';
import '../../automation/automation_schedule_calculator.dart';
import '../../automation/automation_schedule_defaults.dart';
import '../catalog_kind.dart';
import '../catalog_mutation_bus.dart';
import 'automation_catalog_tools.dart';

typedef AutomationRunNow =
    Future<void> Function(String workspaceId, String automationId);
typedef AutomationSessionExists =
    Future<bool> Function(String sessionId, String workspaceId);

const _createdDisabledMessage =
    'Created disabled. Enable it in Automations, or call update_automation '
    'with enabled:true.';

class AutomationCatalogModule implements CatalogKindModule {
  AutomationCatalogModule({
    required this.repository,
    required this.scheduleCalculator,
    required this.bus,
    required this.runNow,
    this.sessionExists,
    this.teamExists,
    this.presetExists,
    int Function()? nowMs,
    String Function()? newId,
    String Function()? defaultTimezone,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch),
       _newId = newId ?? (() => const Uuid().v4()),
       _defaultTimezone = defaultTimezone ?? resolveDeviceTimezoneIdentifier;

  final AutomationRepository repository;
  final AutomationScheduleCalculator scheduleCalculator;
  final CatalogMutationBus bus;
  final AutomationRunNow runNow;
  final AutomationSessionExists? sessionExists;
  final bool Function(String teamId)? teamExists;
  final bool Function(String presetId)? presetExists;
  final int Function() _nowMs;
  final String Function() _newId;
  final String Function() _defaultTimezone;

  Future<void> _writes = Future<void>.value();

  @override
  String get kind => 'automation';

  @override
  bool get supportsCreate => true;

  @override
  bool get supportsImport => false;

  @override
  bool get supportsInstall => false;

  @override
  List<CatalogToolSpec> advertise() => automationCatalogTools;

  @override
  Future<CatalogResult> handle(CatalogOp op, CatalogRequest req) {
    return switch (op) {
      CatalogOp.list => _list(req),
      CatalogOp.read => _read(req),
      CatalogOp.create => _serialized(() => _create(req)),
      CatalogOp.update => _serialized(() => _update(req)),
      CatalogOp.delete => _serialized(() => _delete(req)),
      CatalogOp.run => _serialized(() => _run(req)),
      CatalogOp.search ||
      CatalogOp.install ||
      CatalogOp.importPath ||
      CatalogOp.unbind =>
        throw CatalogException(
          'unsupported_op',
          'automation does not support ${op.name}',
        ),
    };
  }

  Future<CatalogResult> _serialized(Future<CatalogResult> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<CatalogResult> _list(CatalogRequest req) async {
    final automations = await repository.listForWorkspace(req.workspaceId);
    final runs = await repository.runsForWorkspace(req.workspaceId);
    final latest = <String, AutomationRun>{};
    for (final run in runs) {
      final current = latest[run.automationId];
      if (current == null ||
          (run.startedAtMs ?? 0) >= (current.startedAtMs ?? 0)) {
        latest[run.automationId] = run;
      }
    }
    return _ok(req, [for (final a in automations) a.id], {
      'automation': {
        'items': [
          for (final automation in automations)
            {
              ...automation.toJson(),
              'summary': scheduleCalculator.formatScheduleSummary(automation),
              'last_run': latest[automation.id]?.toJson(),
            },
        ],
      },
    });
  }

  Future<CatalogResult> _read(CatalogRequest req) async {
    final id = _optionalId(req);
    if (id == null) return _list(req);
    final automation = await _require(req.workspaceId, id);
    final runs = await repository.runsFor(
      req.workspaceId,
      automationId: automation.id,
    );
    final recent = [...runs]
      ..sort(
        (a, b) => (b.startedAtMs ?? 0).compareTo(a.startedAtMs ?? 0),
      );
    return _ok(req, [automation.id], {
      'automation': {
        ...automation.toJson(),
        'summary': scheduleCalculator.formatScheduleSummary(automation),
        'recent_runs': [for (final run in recent.take(5)) run.toJson()],
      },
    });
  }

  Future<CatalogResult> _create(CatalogRequest req) async {
    final now = _nowMs();
    final schedule = _parseSchedule(req.arguments['schedule'], now: now);
    final action = _parseAction(req.arguments['action']);
    final name = _requireText(req, 'name');
    final message = _requireText(req, 'message');
    final id = _newId();

    final Automation draft;
    if (action == AutomationAction.scheduledMessage) {
      final sessionId = _text(req.arguments['session_id']) ?? req.sessionId;
      final exists = sessionExists;
      if (exists != null && !await exists(sessionId, req.workspaceId)) {
        throw CatalogException(
          'invalid_argument',
          'session not found in this workspace: $sessionId',
        );
      }
      draft = _baseAutomation(
        id: id,
        name: name,
        action: action,
        workspaceId: req.workspaceId,
        message: message,
        schedule: schedule,
        now: now,
      ).copyWith(sessionId: sessionId);
    } else {
      final teamId = _text(req.arguments['team_id']);
      final presetId = _text(req.arguments['preset_id']);
      if (teamId == null && presetId == null) {
        throw CatalogException(
          'target_invalid',
          'launchPrompt requires team_id or preset_id',
        );
      }
      if (teamId != null) {
        final exists = teamExists;
        if (exists != null && !exists(teamId)) {
          throw CatalogException('target_invalid', 'unknown team: $teamId');
        }
      } else {
        final exists = presetExists;
        if (exists != null && !exists(presetId!)) {
          throw CatalogException('target_invalid', 'unknown preset: $presetId');
        }
      }
      draft = _baseAutomation(
        id: id,
        name: name,
        action: action,
        workspaceId: req.workspaceId,
        message: message,
        schedule: schedule,
        now: now,
        isPersonal: teamId == null,
        presetId: teamId == null ? presetId : null,
        teamId: teamId,
        targetMemberId:
            _text(req.arguments['target_member_id']) ?? 'team-lead',
        reuseSession: req.arguments['reuse_session'] == true,
      );
    }

    draft.validate();
    final preview = scheduleCalculator.computeNextRunAtMs(
      draft.copyWith(enabled: true),
      afterMs: now,
    );
    final saved = await repository.upsert(draft);
    _emit(CatalogOp.create, req, [saved.id]);
    return _ok(
      req,
      [saved.id],
      {
        'automation': saved.toJson(),
        'summary': scheduleCalculator.formatScheduleSummary(saved),
        'enabled': saved.enabled,
        'next_run_at_ms': preview,
      },
      message: _createdDisabledMessage,
    );
  }

  Automation _baseAutomation({
    required String id,
    required String name,
    required AutomationAction action,
    required String workspaceId,
    required String message,
    required _ScheduleSpec schedule,
    required int now,
    bool isPersonal = true,
    String? presetId,
    String? teamId,
    String targetMemberId = 'team-lead',
    bool reuseSession = false,
  }) {
    return Automation(
      id: id,
      name: name,
      action: action,
      workspaceId: workspaceId,
      isPersonal: isPersonal,
      presetId: presetId,
      teamId: teamId,
      targetMemberId: targetMemberId,
      message: message,
      reuseSession: reuseSession,
      preset: schedule.preset,
      customCron: schedule.customCron,
      dayOfWeek: schedule.dayOfWeek,
      minute: schedule.minute,
      hourMinute: schedule.hourMinute,
      timezone: schedule.timezone,
      dtstartMs: schedule.dtstartMs,
      runAtMs: schedule.runAtMs,
      enabled: false,
      missedRunGraceMinutes: 15,
      createdAtMs: now,
      updatedAtMs: now,
    );
  }

  Future<CatalogResult> _update(CatalogRequest req) => throw UnsupportedError(
    'implemented in Task 3',
  );

  Future<CatalogResult> _delete(CatalogRequest req) => throw UnsupportedError(
    'implemented in Task 3',
  );

  Future<CatalogResult> _run(CatalogRequest req) => throw UnsupportedError(
    'implemented in Task 3',
  );

  Future<Automation> _require(String workspaceId, String id) async {
    final automations = await repository.listForWorkspace(workspaceId);
    final match = automations.where((a) => a.id == id).firstOrNull;
    if (match == null) {
      throw CatalogException('not_found', 'automation not found: $id');
    }
    return match;
  }

  void _emit(CatalogOp op, CatalogRequest req, List<String> ids) {
    bus.emit(
      CatalogMutationEvent(
        kind: kind,
        op: op,
        ids: ids,
        workspaceId: req.workspaceId,
      ),
    );
  }

  CatalogResult _ok(
    CatalogRequest req,
    List<String> ids,
    Map<String, Object?> data, {
    String? message,
  }) {
    return CatalogResult.ok(
      kind: kind,
      ids: ids,
      workspaceId: req.workspaceId,
      restartRequired: false,
      data: data,
      message: message,
    );
  }

  _ScheduleSpec _parseSchedule(Object? raw, {required int now}) {
    if (raw is! Map) {
      throw CatalogException('schedule_invalid', 'schedule is required');
    }
    final map = raw.cast<String, Object?>();
    final type = _text(map['type'])?.toLowerCase();
    if (type == null) {
      throw CatalogException('schedule_invalid', 'schedule.type is required');
    }
    final timezone = _text(map['timezone']) ?? _defaultTimezone();
    final dtstartMs = _int(map['dtstart_ms']) ?? now;
    const defaultTime = '09:00';
    try {
      switch (type) {
        case 'hourly':
          final minute = _int(map['minute']) ?? 0;
          if (minute < 0 || minute > 59) {
            throw ArgumentError('minute must be 0..59');
          }
          return _ScheduleSpec(
            preset: AutomationSchedulePreset.hourly,
            minute: minute,
            hourMinute: defaultTime,
            timezone: timezone,
            dtstartMs: dtstartMs,
          );
        case 'daily':
        case 'weekdays':
          final time = _text(map['time']) ?? defaultTime;
          parseHourMinute(time);
          return _ScheduleSpec(
            preset: type == 'daily'
                ? AutomationSchedulePreset.daily
                : AutomationSchedulePreset.weekdays,
            hourMinute: time,
            timezone: timezone,
            dtstartMs: dtstartMs,
          );
        case 'weekly':
          final time = _text(map['time']) ?? defaultTime;
          parseHourMinute(time);
          final day = _int(map['day_of_week']) ?? 1;
          if (day < 1 || day > 7) {
            throw ArgumentError('day_of_week must be 1..7');
          }
          return _ScheduleSpec(
            preset: AutomationSchedulePreset.weekly,
            hourMinute: time,
            dayOfWeek: day,
            timezone: timezone,
            dtstartMs: dtstartMs,
          );
        case 'custom':
          final cron = _text(map['cron']);
          if (cron == null || !scheduleCalculator.isValidCron(cron)) {
            throw ArgumentError('invalid cron expression');
          }
          return _ScheduleSpec(
            preset: AutomationSchedulePreset.custom,
            customCron: cron,
            timezone: timezone,
            dtstartMs: dtstartMs,
          );
        case 'once':
          final at = _runAtMs(map['at']);
          if (at == null || at <= now) {
            throw ArgumentError('at must be a future timestamp');
          }
          return _ScheduleSpec(
            preset: AutomationSchedulePreset.once,
            runAtMs: at,
            timezone: timezone,
            dtstartMs: dtstartMs,
          );
        default:
          throw ArgumentError('unknown schedule type: $type');
      }
    } on ArgumentError catch (error) {
      throw CatalogException(
        'schedule_invalid',
        error.message?.toString() ?? 'invalid schedule',
      );
    }
  }

  int? _runAtMs(Object? raw) {
    if (raw is int) return raw;
    if (raw is String && raw.trim().isNotEmpty) {
      return DateTime.tryParse(raw.trim())?.millisecondsSinceEpoch;
    }
    return null;
  }

  AutomationAction _parseAction(Object? raw) {
    final name = _text(raw) ?? AutomationAction.scheduledMessage.name;
    for (final value in AutomationAction.values) {
      if (value.name == name) return value;
    }
    throw CatalogException('invalid_argument', 'unknown action: $name');
  }

  String _requireText(CatalogRequest req, String key) {
    final value = _text(req.arguments[key]);
    if (value == null) {
      throw CatalogException('invalid_argument', '$key is required');
    }
    return value;
  }

  String _requireId(CatalogRequest req) {
    final id = _text(req.arguments['id']);
    if (id == null) {
      throw CatalogException('invalid_argument', 'id is required');
    }
    return id;
  }

  String? _optionalId(CatalogRequest req) => _text(req.arguments['id']);

  static String? _text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}

class _ScheduleSpec {
  const _ScheduleSpec({
    required this.preset,
    required this.timezone,
    required this.dtstartMs,
    this.customCron,
    this.dayOfWeek,
    this.minute = 0,
    this.hourMinute = '09:00',
    this.runAtMs,
  });

  final AutomationSchedulePreset preset;
  final String? customCron;
  final int? dayOfWeek;
  final int minute;
  final String hourMinute;
  final String timezone;
  final int dtstartMs;
  final int? runAtMs;
}
