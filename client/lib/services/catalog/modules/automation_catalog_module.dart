import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';

import '../../../models/automation.dart';
import '../../../repositories/automation_repository.dart';
import '../../automation/automation_schedule_calculator.dart';
import '../../automation/automation_schedule_defaults.dart';
import '../catalog_error_sanitizer.dart';
import '../catalog_kind.dart';
import '../catalog_mutation_bus.dart';
import 'automation_catalog_tools.dart';
import 'automation_schedule_args.dart';

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
      CatalogOp.unbind => throw CatalogException(
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
    return _ok(
      req,
      [for (final a in automations) a.id],
      {
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
      },
    );
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
      ..sort((a, b) => (b.startedAtMs ?? 0).compareTo(a.startedAtMs ?? 0));
    return _ok(
      req,
      [automation.id],
      {
        'automation': {
          ...automation.toJson(),
          'summary': scheduleCalculator.formatScheduleSummary(automation),
          'recent_runs': [for (final run in recent.take(5)) run.toJson()],
        },
      },
    );
  }

  Future<CatalogResult> _create(CatalogRequest req) async {
    final now = _nowMs();
    final schedule = parseAutomationSchedule(
      req.arguments['schedule'],
      calculator: scheduleCalculator,
      defaultTimezone: _defaultTimezone(),
      now: now,
    );
    final action = _parseAction(req.arguments['action']);
    final name = _requireText(req, 'name');
    final message = _requireText(req, 'message');
    final maxRunCount = _maxRunCount(req);
    final missedRunGraceMinutes = _graceMinutes(req);
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
        maxRunCount: maxRunCount,
        missedRunGraceMinutes: missedRunGraceMinutes,
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
        maxRunCount: maxRunCount,
        missedRunGraceMinutes: missedRunGraceMinutes,
        isPersonal: teamId == null,
        presetId: teamId == null ? presetId : null,
        teamId: teamId,
        targetMemberId: _text(req.arguments['target_member_id']) ?? 'team-lead',
        reuseSession: req.arguments['reuse_session'] == true,
      );
    }

    final (saved, preview) = await _commit(draft, now);
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
    required AutomationScheduleSpec schedule,
    required int now,
    required int missedRunGraceMinutes,
    int? maxRunCount,
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
      missedRunGraceMinutes: missedRunGraceMinutes,
      maxRunCount: maxRunCount,
      createdAtMs: now,
      updatedAtMs: now,
    );
  }

  /// Validates and persists [draft], translating data-layer failures so the
  /// catalog transport never surfaces a raw `ArgumentError` as
  /// `install_failed`.
  ///
  /// With [scheduleNextRun] the next run is resolved from the draft's own
  /// `enabled` flag (update); otherwise the next run is only previewed from a
  /// would-be enabled automation (create). Both paths run inside the same
  /// translation boundary, so a validation failure raised by the schedule
  /// calculator is reported exactly like one raised by [Automation.validate].
  Future<(Automation, int?)> _commit(
    Automation draft,
    int now, {
    bool scheduleNextRun = false,
  }) async {
    try {
      draft.validate();
      final Automation ready;
      final int? preview;
      if (scheduleNextRun) {
        final nextMs = draft.enabled
            ? scheduleCalculator.computeNextRunAtMs(draft, afterMs: now)
            : null;
        ready = draft.copyWith(
          enabled: draft.enabled && nextMs != null,
          nextRunAtMs: nextMs,
          clearNextRunAtMs: nextMs == null,
        );
        preview = nextMs;
      } else {
        ready = draft;
        preview = scheduleCalculator.computeNextRunAtMs(
          draft.copyWith(enabled: true),
          afterMs: now,
        );
      }
      ready.validate();
      final saved = await repository.upsert(ready);
      return (saved, preview);
    } on CatalogException {
      rethrow;
    } on ArgumentError catch (error) {
      throw CatalogException(
        'invalid_argument',
        error.message?.toString() ?? 'invalid automation',
      );
    } on FormatException catch (error) {
      throw CatalogException('invalid_argument', error.message);
    } on Object catch (error) {
      throw CatalogException(
        'write_failed',
        CatalogErrorSanitizer.sanitize('$error'),
      );
    }
  }

  Future<CatalogResult> _update(CatalogRequest req) async {
    final id = _requireId(req);
    final existing = await _require(req.workspaceId, id);
    final now = _nowMs();
    var next = existing;

    if (req.arguments.containsKey('name')) {
      next = next.copyWith(name: _requireText(req, 'name'));
    }
    if (req.arguments.containsKey('message')) {
      next = next.copyWith(message: _requireText(req, 'message'));
    }
    if (req.arguments.containsKey('schedule')) {
      final rawSchedule = req.arguments['schedule'];
      final schedule = parseAutomationSchedule(
        rawSchedule,
        calculator: scheduleCalculator,
        defaultTimezone: next.timezone,
        now: now,
      );
      final overridesDtstart =
          rawSchedule is Map && rawSchedule.containsKey('dtstart_ms');
      next = next.copyWith(
        preset: schedule.preset,
        customCron: schedule.customCron,
        clearCustomCron: schedule.customCron == null,
        dayOfWeek: schedule.dayOfWeek,
        clearDayOfWeek: schedule.dayOfWeek == null,
        minute: schedule.minute,
        hourMinute: schedule.hourMinute,
        timezone: schedule.timezone,
        dtstartMs: overridesDtstart ? schedule.dtstartMs : next.dtstartMs,
        runAtMs: schedule.runAtMs,
        clearRunAtMs: schedule.runAtMs == null,
      );
    }
    if (req.arguments.containsKey('max_run_count')) {
      final maxRunCount = _maxRunCount(req);
      next = next.copyWith(
        maxRunCount: maxRunCount,
        clearMaxRunCount: maxRunCount == null,
      );
    }
    if (req.arguments.containsKey('missed_run_grace_minutes')) {
      next = next.copyWith(missedRunGraceMinutes: _graceMinutes(req));
    }
    if (req.arguments.containsKey('reuse_session')) {
      next = next.copyWith(
        reuseSession: req.arguments['reuse_session'] == true,
      );
    }
    if (req.arguments.containsKey('target_member_id')) {
      next = next.copyWith(
        targetMemberId: _text(req.arguments['target_member_id']) ?? 'team-lead',
      );
    }
    if (req.arguments.containsKey('enabled')) {
      next = next.copyWith(enabled: req.arguments['enabled'] == true);
    }

    if (req.arguments['enabled'] == true && next.isRunLimitReached) {
      throw CatalogException(
        'run_limit_reached',
        'automation has reached its run limit: $id; increase or clear '
            'max_run_count before enabling it',
      );
    }

    final (saved, _) = await _commit(next, now, scheduleNextRun: true);
    _emit(CatalogOp.update, req, [saved.id]);
    return _ok(
      req,
      [saved.id],
      {
        'automation': saved.toJson(),
        'summary': scheduleCalculator.formatScheduleSummary(saved),
        'enabled': saved.enabled,
        'next_run_at_ms': saved.nextRunAtMs,
      },
    );
  }

  Future<CatalogResult> _delete(CatalogRequest req) async {
    final id = _requireId(req);
    final existing = await _require(req.workspaceId, id);
    await _translateWrite(
      () => repository.delete(existing.workspaceId, existing.id),
    );
    _emit(CatalogOp.delete, req, [existing.id]);
    return _ok(
      req,
      [existing.id],
      {
        'automation': {'id': existing.id, 'deleted': true},
      },
      message: 'Automation deleted.',
    );
  }

  Future<CatalogResult> _run(CatalogRequest req) async {
    final id = _requireId(req);
    final automation = await _require(req.workspaceId, id);
    if (automation.isRunLimitReached) {
      throw CatalogException(
        'run_limit_reached',
        'automation has reached its run limit: $id',
      );
    }
    final run = await _translateWrite(() async {
      await runNow(automation.workspaceId, automation.id);
      final runs = await repository.runsFor(
        automation.workspaceId,
        automationId: automation.id,
      );
      final latest = [...runs]
        ..sort((a, b) => (b.startedAtMs ?? 0).compareTo(a.startedAtMs ?? 0));
      return latest.isEmpty ? null : latest.first;
    });
    _emit(CatalogOp.run, req, [automation.id]);
    return _ok(
      req,
      [automation.id],
      {
        'run': run?.toJson(),
        'automation': (await _require(req.workspaceId, id)).toJson(),
      },
    );
  }

  /// Runs a write that does not go through [_commit] (delete, dispatch) and
  /// maps unexpected failures to the same `write_failed` code.
  Future<T> _translateWrite<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on CatalogException {
      rethrow;
    } on Object catch (error) {
      throw CatalogException(
        'write_failed',
        CatalogErrorSanitizer.sanitize('$error'),
      );
    }
  }

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

  int? _maxRunCount(CatalogRequest req) {
    final raw = req.arguments['max_run_count'];
    if (raw == null) return null;
    if (raw is! num) {
      throw CatalogException(
        'invalid_argument',
        'max_run_count must be a number',
      );
    }
    final value = raw.toInt();
    if (value < 0) {
      throw CatalogException('invalid_argument', 'max_run_count must be >= 0');
    }
    return value == 0 ? null : value;
  }

  int _graceMinutes(CatalogRequest req) {
    final raw = req.arguments['missed_run_grace_minutes'];
    if (raw == null) return 15;
    if (raw is! num) {
      throw CatalogException(
        'invalid_argument',
        'missed_run_grace_minutes must be a number',
      );
    }
    final value = raw.toInt();
    if (value < 0) {
      throw CatalogException(
        'invalid_argument',
        'missed_run_grace_minutes must be >= 0',
      );
    }
    return value;
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
}
