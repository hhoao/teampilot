import 'package:flutter/material.dart';
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

/// Full or compact automation editor. Returns the saved [Automation] on confirm.
class AutomationEditorDialog extends StatefulWidget {
  const AutomationEditorDialog({
    this.initial,
    this.compact = false,
    this.workspaceId,
    this.sessionId,
    this.defaultName,
    super.key,
  });

  final Automation? initial;
  final bool compact;
  final String? workspaceId;
  final String? sessionId;
  final String? defaultName;

  static Future<Automation?> show(
    BuildContext context, {
    Automation? initial,
    bool compact = false,
    String? workspaceId,
    String? sessionId,
    String? defaultName,
  }) {
    return showDialog<Automation>(
      context: context,
      builder: (_) => AutomationEditorDialog(
        initial: initial,
        compact: compact,
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
  late AutomationAction _action;
  late AutomationScope _scope;
  late CliTool _cli;
  late bool _reuseSession;
  late bool _enabled;
  late AutomationScheduleDraft _schedule;
  String? _errorMessage;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final workspaceId = initial?.workspaceId ?? widget.workspaceId ?? '';
    final sessionId = initial?.sessionId ?? widget.sessionId;
    final compact = widget.compact;

    _nameCtl = TextEditingController(
      text: initial?.name ?? widget.defaultName ?? '',
    );
    _messageCtl = TextEditingController(text: initial?.message ?? '');
    _targetMemberCtl = TextEditingController(
      text: initial?.targetMemberId ?? 'team-lead',
    );
    _action = initial?.action ??
        (compact ? AutomationAction.sendToLead : AutomationAction.sendToLead);
    _scope = initial?.scope ??
        (sessionId != null && sessionId.isNotEmpty
            ? AutomationScope.session
            : AutomationScope.workspace);
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

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final workspaceId =
        widget.initial?.workspaceId ?? widget.workspaceId ?? '';
    final sessionId = _scope == AutomationScope.session
        ? (widget.initial?.sessionId ?? widget.sessionId)
        : null;

    final automation = Automation(
      id: widget.initial?.id ?? const Uuid().v4(),
      name: name,
      action: _action,
      scope: _scope,
      workspaceId: workspaceId,
      sessionId: sessionId,
      targetMemberId: _targetMemberCtl.text.trim().isEmpty
          ? 'team-lead'
          : _targetMemberCtl.text.trim(),
      message: message,
      cli: _action == AutomationAction.launchPrompt ? _cli : null,
      reuseSession: _reuseSession,
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
      createdAtMs: widget.initial?.createdAtMs ?? nowMs,
      updatedAtMs: nowMs,
    );

    try {
      automation.validate();
    } on ArgumentError catch (e) {
      setState(() => _errorMessage = e.message);
      return;
    }

    final nextRun = _enabled
        ? _calculator.computeNextRunAtMs(automation, afterMs: nowMs)
        : null;
    final saved = automation.copyWith(
      nextRunAtMs: nextRun,
      clearNextRunAtMs: nextRun == null,
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
    final compact = widget.compact;
    final title = _isEditing
        ? (compact ? l10n.automationsCompactTitle : l10n.automationsEditTitle)
        : (compact ? l10n.automationsCompactTitle : l10n.automationsCreateTitle);

    return AppDialog(
      maxWidth: compact ? 480 : 560,
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
          if (!compact) ...[
            const SizedBox(height: 16),
            Text(l10n.automationsAction, style: styles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            AppDropdownField<AutomationAction>(
              items: AutomationAction.values,
              initialItem: _action,
              decoration: AppDropdownDecorations.themed(context),
              itemLabel: (a) => _actionLabel(l10n, a),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _action = value);
              },
            ),
            const SizedBox(height: 12),
            Text(l10n.automationsScope, style: styles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            AppDropdownField<AutomationScope>(
              items: AutomationScope.values,
              initialItem: _scope,
              decoration: AppDropdownDecorations.themed(context),
              itemLabel: (s) => _scopeLabel(l10n, s),
              onChanged: (value) {
                if (value == null) return;
                setState(() => _scope = value);
              },
            ),
            if (_action == AutomationAction.launchPrompt) ...[
              const SizedBox(height: 12),
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
            ],
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

String _actionLabel(AppLocalizations l10n, AutomationAction action) {
  return switch (action) {
    AutomationAction.sendToLead => l10n.automationsSendToLead,
    AutomationAction.launchPrompt => l10n.automationsLaunchPrompt,
  };
}

String _scopeLabel(AppLocalizations l10n, AutomationScope scope) {
  return switch (scope) {
    AutomationScope.session => l10n.automationsScopeSession,
    AutomationScope.workspace => l10n.automationsScopeWorkspace,
  };
}
