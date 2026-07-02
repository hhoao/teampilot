import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../cubits/automation_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/automation.dart';
import '../../models/team_config.dart';
import '../../services/automation/automation_schedule_calculator.dart';
import '../../services/cli/registry/cli_display_name.dart';
import '../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import 'automation_schedule_picker.dart';

enum AutomationEditorKind { scheduledMessage, launchPrompt }

/// Editor for session scheduled messages or workspace launch-prompt automations.
class AutomationEditorDialog extends StatefulWidget {
  const AutomationEditorDialog({
    this.initial,
    this.kind = AutomationEditorKind.launchPrompt,
    this.workspaceId,
    this.sessionId,
    this.defaultName,
    super.key,
  });

  final Automation? initial;
  final AutomationEditorKind kind;
  final String? workspaceId;
  final String? sessionId;
  final String? defaultName;

  static Future<Automation?> show(
    BuildContext context, {
    Automation? initial,
    AutomationEditorKind kind = AutomationEditorKind.launchPrompt,
    String? workspaceId,
    String? sessionId,
    String? defaultName,
  }) {
    return showDialog<Automation>(
      context: context,
      builder: (_) => AutomationEditorDialog(
        initial: initial,
        kind: kind,
        workspaceId: workspaceId,
        sessionId: sessionId,
        defaultName: defaultName,
      ),
    );
  }

  @override
  State<AutomationEditorDialog> createState() => _AutomationEditorDialogState();
}

class _AutomationEditorDialogState extends State<AutomationEditorDialog> {
  final _calculator = AutomationScheduleCalculator();
  late final TextEditingController _nameCtl;
  late final TextEditingController _messageCtl;
  late final TextEditingController _targetMemberCtl;
  late final TextEditingController _maxRunCountCtl;
  late CliTool _cli;
  late bool _reuseSession;
  late bool _enabled;
  late AutomationScheduleDraft _schedule;
  String? _errorMessage;

  bool get _isScheduledMessage =>
      widget.kind == AutomationEditorKind.scheduledMessage;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final workspaceId = initial?.workspaceId ?? widget.workspaceId ?? '';

    _nameCtl = TextEditingController(
      text: initial?.name ?? widget.defaultName ?? '',
    );
    _messageCtl = TextEditingController(text: initial?.message ?? '');
    _targetMemberCtl = TextEditingController(
      text: initial?.targetMemberId ?? 'team-lead',
    );
    _maxRunCountCtl = TextEditingController(
      text: initial?.maxRunCount?.toString() ?? '',
    );
    _cli = initial?.cli ?? CliTool.claude;
    _reuseSession = initial?.reuseSession ?? false;
    _enabled = initial?.enabled ?? true;
    _schedule = initial != null
        ? scheduleDraftFromAutomation(initial)
        : AutomationScheduleDraft(
            preset: AutomationSchedulePreset.daily,
            minute: 0,
            hourMinute: '09:00',
            timezone: DateTime.now().timeZoneName,
          );

    if (workspaceId.isEmpty && initial == null) {
      _errorMessage = 'workspaceId required';
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _messageCtl.dispose();
    _targetMemberCtl.dispose();
    _maxRunCountCtl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final name = _nameCtl.text.trim();
    final message = _messageCtl.text.trim();
    if (name.isEmpty || message.isEmpty) {
      setState(() => _errorMessage = l10n.automationsValidationRequired);
      return;
    }

    if (_schedule.preset == AutomationSchedulePreset.custom) {
      final cron = _schedule.customCron?.trim() ?? '';
      if (!_calculator.isValidCron(cron)) {
        setState(() => _errorMessage = l10n.automationsInvalidCron);
        return;
      }
    }

    try {
      parseHourMinute(_schedule.hourMinute);
    } on Object {
      setState(() => _errorMessage = l10n.automationsInvalidTime);
      return;
    }

    final maxRunRaw = _maxRunCountCtl.text.trim();
    int? maxRunCount;
    if (maxRunRaw.isNotEmpty) {
      final parsed = int.tryParse(maxRunRaw);
      if (parsed == null || parsed < 1) {
        setState(() => _errorMessage = l10n.automationsInvalidMaxRunCount);
        return;
      }
      maxRunCount = parsed;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final workspaceId =
        widget.initial?.workspaceId ?? widget.workspaceId ?? '';
    final sessionId = _isScheduledMessage
        ? (widget.initial?.sessionId ?? widget.sessionId)
        : null;

    final automation = Automation(
      id: widget.initial?.id ?? const Uuid().v4(),
      name: name,
      action: _isScheduledMessage
          ? AutomationAction.scheduledMessage
          : AutomationAction.launchPrompt,
      workspaceId: workspaceId,
      sessionId: sessionId,
      targetMemberId: _targetMemberCtl.text.trim().isEmpty
          ? 'team-lead'
          : _targetMemberCtl.text.trim(),
      message: message,
      cli: _isScheduledMessage ? null : _cli,
      reuseSession: _isScheduledMessage ? false : _reuseSession,
      preset: _schedule.preset,
      customCron: _schedule.customCron,
      dayOfWeek: _schedule.dayOfWeek,
      minute: _schedule.minute,
      hourMinute: _schedule.hourMinute,
      timezone: _schedule.timezone,
      dtstartMs: widget.initial?.dtstartMs ?? nowMs,
      enabled: _enabled,
      nextRunAtMs: widget.initial?.nextRunAtMs,
      lastRunAtMs: widget.initial?.lastRunAtMs,
      maxRunCount: maxRunCount,
      runCount: widget.initial?.runCount ?? 0,
      createdAtMs: widget.initial?.createdAtMs ?? nowMs,
      updatedAtMs: nowMs,
    );

    try {
      automation.validate();
    } on ArgumentError catch (e) {
      setState(() => _errorMessage = e.message);
      return;
    }

    final nextRun = _enabled && !automation.isRunLimitReached
        ? _calculator.computeNextRunAtMs(automation, afterMs: nowMs)
        : null;
    final saved = automation.copyWith(
      nextRunAtMs: nextRun,
      clearNextRunAtMs: nextRun == null,
      enabled: _enabled && !automation.isRunLimitReached,
    );

    final cubit = context.read<AutomationCubit>();
    await cubit.save(saved);
    if (!mounted) return;
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = AppTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final title = _isEditing
        ? (_isScheduledMessage
            ? l10n.automationsCompactTitle
            : l10n.automationsEditTitle)
        : (_isScheduledMessage
            ? l10n.automationsCompactTitle
            : l10n.automationsCreateTitle);

    return AppDialog(
      maxWidth: _isScheduledMessage ? 480 : 560,
      scrollable: true,
      maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppDialogHeader(title: title),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            Text(
              _errorMessage!,
              style: styles.bodySmall.copyWith(color: cs.error),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _nameCtl,
            decoration: InputDecoration(labelText: l10n.automationsName),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageCtl,
            decoration: InputDecoration(labelText: l10n.automationsMessage),
            minLines: 2,
            maxLines: 5,
          ),
          if (!_isScheduledMessage) ...[
            const SizedBox(height: 16),
            Text(l10n.automationsCli, style: styles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            AppDropdownField<CliTool>(
              items: CliTool.values,
              initialItem: _cli,
              decoration: AppDropdownDecorations.themed(context),
              itemLabel: (cli) {
                final registry = CliToolRegistryScope.of(context);
                final def = registry.tryGet(cli);
                if (def == null) return cli.value;
                return cliDisplayName(def, l10n, registry: registry);
              },
              onChanged: (value) {
                if (value == null) return;
                setState(() => _cli = value);
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.automationsReuseSession),
              value: _reuseSession,
              onChanged: (v) => setState(() => _reuseSession = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _targetMemberCtl,
              decoration: InputDecoration(labelText: l10n.automationsTargetMember),
            ),
          ],
          const SizedBox(height: 16),
          AutomationSchedulePicker(
            draft: _schedule,
            calculator: _calculator,
            onChanged: (draft) => setState(() => _schedule = draft),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxRunCountCtl,
            decoration: InputDecoration(
              labelText: l10n.automationsMaxRunCount,
              hintText: l10n.automationsMaxRunCountHint,
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.automationsEnabled),
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          AppDialogActions(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: _save,
                child: Text(l10n.save),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
