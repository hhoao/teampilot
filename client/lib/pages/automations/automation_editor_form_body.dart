import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/app_session.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../services/automation/automation_schedule_calculator.dart';
import '../../services/automation/automation_schedule_defaults.dart';
import '../../utils/session/session_display_title.dart';
import '../../widgets/cli/cli_brand_icon.dart';
import 'package:shared_ui/shared_ui.dart';
import 'automation_editor_dialog.dart' show AutomationEditorKind;
import 'automation_editor_launch_section.dart';
import 'automation_command_working_directory_field.dart';
import 'automation_schedule_picker.dart';

/// Label column width for the automation editor inline form.
const double kAutomationEditorFormLabelWidth = 160;

/// Field body for [AutomationEditorDialog] under an [TpForm].
class AutomationEditorFormBody extends StatelessWidget {
  const AutomationEditorFormBody({
    required this.kind,
    required this.nameController,
    required this.messageController,
    required this.maxRunCountController,
    required this.schedule,
    required this.onScheduleChanged,
    required this.calculator,
    required this.enabled,
    required this.onEnabledChanged,
    required this.runLimitReached,
    required this.reuseSession,
    required this.onReuseSessionChanged,
    required this.reuseSessionSubtitle,
    this.boundSessionId,
    this.boundSession,
    this.boundCli,
    this.onSwitchSession,
    this.onUnbindSession,
    this.commandController,
    this.commandError,
    this.onCommandChanged,
    this.timeoutController,
    this.catchUpOnce = false,
    this.onCatchUpChanged,
    this.onMaxRunCountChanged,
    this.workspace,
    this.isPersonal = true,
    this.projectFolderPath,
    this.workingDirectoryPath,
    this.presetId,
    this.teamId,
    this.expertKey,
    this.targetMemberId = 'team-lead',
    this.onIsPersonalChanged,
    this.onProjectChanged,
    this.onWorktreeChanged,
    this.onPresetChanged,
    this.onTeamChanged,
    this.onExpertChanged,
    this.onTargetMemberChanged,
    super.key,
  });

  final AutomationEditorKind kind;
  final TextEditingController nameController;
  final TextEditingController messageController;
  final TextEditingController maxRunCountController;
  final AutomationScheduleDraft schedule;
  final ValueChanged<AutomationScheduleDraft> onScheduleChanged;
  final AutomationScheduleCalculator calculator;
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final bool runLimitReached;
  final bool reuseSession;
  final ValueChanged<bool> onReuseSessionChanged;
  final String reuseSessionSubtitle;

  /// Current binding (launchPrompt + reuseSession only).
  final String? boundSessionId;
  final AppSession? boundSession;
  final CliTool? boundCli;
  final VoidCallback? onSwitchSession;
  final VoidCallback? onUnbindSession;
  final TextEditingController? commandController;
  final String? commandError;
  final ValueChanged<String>? onCommandChanged;
  final TextEditingController? timeoutController;
  final bool catchUpOnce;
  final ValueChanged<bool>? onCatchUpChanged;
  final VoidCallback? onMaxRunCountChanged;
  final Workspace? workspace;
  final bool isPersonal;
  final String? projectFolderPath;
  final String? workingDirectoryPath;
  final String? presetId;
  final String? teamId;
  final String? expertKey;
  final String targetMemberId;
  final ValueChanged<bool>? onIsPersonalChanged;
  final ValueChanged<String?>? onProjectChanged;
  final ValueChanged<String?>? onWorktreeChanged;
  final ValueChanged<String?>? onPresetChanged;
  final ValueChanged<String?>? onTeamChanged;
  final ValueChanged<String?>? onExpertChanged;
  final ValueChanged<String>? onTargetMemberChanged;

  bool get isScheduledMessage => kind == AutomationEditorKind.scheduledMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bodyStyle = TpTextStyles.of(context).md;
    final monospaceStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpFormField<String>(
          id: 'name',
          initialValue: nameController.text,
          label: Text(l10n.automationsName),
          layoutStyle: TpFormFieldLayoutStyle.inline,
          labelWidth: kAutomationEditorFormLabelWidth,
          validator: (v) => (v == null || v.trim().isEmpty)
              ? l10n.automationsValidationRequired
              : null,
          builder: (state) {
            return TextField(
              controller: nameController,
              focusNode: state.focusNode,
              onChanged: state.didChange,
              decoration: InputDecoration(
                errorText: state.hasError ? '' : null,
                errorStyle: const TextStyle(height: 0, fontSize: 0),
              ),
            );
          },
        ),
        if (kind != AutomationEditorKind.runCommand) ...[
          const SizedBox(height: 12),
          TpTextareaFormField(
            id: 'message',
            controller: messageController,
            label: Text(l10n.automationsMessage),
            layoutStyle: TpFormFieldLayoutStyle.inline,
            labelWidth: kAutomationEditorFormLabelWidth,
            minHeight: tpTextareaHeightForLines(bodyStyle, lines: 2),
            maxHeight: tpTextareaHeightForLines(bodyStyle, lines: 5),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? l10n.automationsValidationRequired
                : null,
          ),
        ],
        if (kind == AutomationEditorKind.runCommand) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('automationCommandField'),
            controller: commandController,
            minLines: 3,
            maxLines: 8,
            style: monospaceStyle,
            onChanged: onCommandChanged,
            decoration: InputDecoration(
              labelText: l10n.automationsCommand,
              helperText: l10n.automationsCommandHelp,
              errorText: commandError,
            ),
          ),
          if (workspace != null) ...[
            const SizedBox(height: 12),
            AutomationCommandWorkingDirectoryField(
              workspace: workspace!,
              workingDirectoryPath: workingDirectoryPath,
              labelWidth: kAutomationEditorFormLabelWidth,
              onChanged: onWorktreeChanged ?? (_) {},
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  key: const Key('automationTimeoutField'),
                  controller: timeoutController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.automationsCommandTimeout,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: SwitchListTile(
                  value: catchUpOnce,
                  onChanged: onCatchUpChanged,
                  title: Text(l10n.automationsCatchUpOnce),
                ),
              ),
            ],
          ),
        ],
        if (kind == AutomationEditorKind.launchPrompt && workspace != null) ...[
          const SizedBox(height: 12),
          AutomationEditorLaunchSection(
            workspace: workspace!,
            isPersonal: isPersonal,
            projectFolderPath: projectFolderPath,
            workingDirectoryPath: workingDirectoryPath,
            presetId: presetId,
            cliFilter: boundCli,
            teamId: teamId,
            expertKey: expertKey,
            targetMemberId: targetMemberId,
            labelWidth: kAutomationEditorFormLabelWidth,
            onProjectChanged: onProjectChanged ?? (_) {},
            onWorktreeChanged: onWorktreeChanged ?? (_) {},
            onIsPersonalChanged: onIsPersonalChanged ?? (_) {},
            onPresetChanged: onPresetChanged ?? (_) {},
            onTeamChanged: onTeamChanged ?? (_) {},
            onExpertChanged: onExpertChanged ?? (_) {},
            onTargetMemberChanged: onTargetMemberChanged ?? (_) {},
          ),
          const SizedBox(height: 12),
          TpFormField<bool>(
            id: 'reuseSession',
            initialValue: reuseSession,
            label: Text(l10n.automationsReuseSession),
            description: Text(reuseSessionSubtitle),
            layoutStyle: TpFormFieldLayoutStyle.inline,
            labelWidth: kAutomationEditorFormLabelWidth,
            builder: (state) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Switch(
                  value: state.value ?? false,
                  onChanged: (v) {
                    state.didChange(v);
                    onReuseSessionChanged(v);
                  },
                ),
              );
            },
          ),
          if (reuseSession) ...[
            const SizedBox(height: 12),
            _AutomationBoundSessionRow(
              labelWidth: kAutomationEditorFormLabelWidth,
              sessionId: boundSessionId,
              session: boundSession,
              cli: boundCli,
              onSwitch: onSwitchSession ?? () {},
              onUnbind: onUnbindSession ?? () {},
            ),
          ],
        ],
        const SizedBox(height: 12),
        AutomationSchedulePicker(
          draft: schedule,
          calculator: calculator,
          labelWidth: kAutomationEditorFormLabelWidth,
          onChanged: onScheduleChanged,
        ),
        // Once/countdown schedules fire exactly once, so the run limit has
        // nothing to configure — saving stores the implicit maxRunCount of 1.
        if (schedule.mode == AutomationScheduleMode.recurring) ...[
          const SizedBox(height: 12),
          TpFormField<String>(
            id: 'maxRunCount',
            initialValue: maxRunCountController.text,
            label: Text(l10n.automationsMaxRunCount),
            description: Text(l10n.automationsMaxRunCountHint),
            layoutStyle: TpFormFieldLayoutStyle.inline,
            labelWidth: kAutomationEditorFormLabelWidth,
            validator: (v) {
              final raw = v?.trim() ?? '';
              if (raw.isEmpty) return null;
              final parsed = int.tryParse(raw);
              if (parsed == null || parsed < 1) {
                return l10n.automationsInvalidMaxRunCount;
              }
              return null;
            },
            builder: (state) {
              return TextField(
                controller: maxRunCountController,
                focusNode: state.focusNode,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (value) {
                  state.didChange(value);
                  onMaxRunCountChanged?.call();
                },
                decoration: InputDecoration(
                  errorText: state.hasError ? '' : null,
                  errorStyle: const TextStyle(height: 0, fontSize: 0),
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 12),
        TpFormField<bool>(
          key: ValueKey('enabled-$enabled-$runLimitReached'),
          id: 'enabled',
          initialValue: runLimitReached ? false : enabled,
          label: Text(l10n.automationsEnabled),
          layoutStyle: TpFormFieldLayoutStyle.inline,
          labelWidth: kAutomationEditorFormLabelWidth,
          builder: (state) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Switch(
                value: runLimitReached ? false : (state.value ?? false),
                onChanged: runLimitReached
                    ? null
                    : (v) {
                        state.didChange(v);
                        onEnabledChanged(v);
                      },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AutomationBoundSessionRow extends StatelessWidget {
  const _AutomationBoundSessionRow({
    required this.labelWidth,
    required this.sessionId,
    required this.session,
    required this.cli,
    required this.onSwitch,
    required this.onUnbind,
  });

  final double labelWidth;
  final String? sessionId;
  final AppSession? session;
  final CliTool? cli;
  final VoidCallback onSwitch;
  final VoidCallback onUnbind;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hasBinding = sessionId?.trim().isNotEmpty ?? false;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              l10n.automationsBoundSession,
              style: TpTextStyles.of(context).md,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasBinding)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    l10n.automationsBoundSessionPending,
                    style: TpTextStyles.of(context).sm,
                  ),
                )
              else ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (session == null)
                      Flexible(
                        child: Text(
                          l10n.automationsBoundSessionUnavailable,
                          style: TpTextStyles.of(context).sm,
                        ),
                      )
                    else ...[
                      if (cli != null) ...[
                        CliBrandIcon(cli: cli!, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              sessionListDisplayTitle(session!, l10n),
                              overflow: TextOverflow.ellipsis,
                              style: TpTextStyles.of(context).md,
                            ),
                            if (cli != null)
                              Text(cli!.value, style: TpTextStyles.of(context).sm),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      key: const Key('automationSwitchSession'),
                      onPressed: onSwitch,
                      child: Text(l10n.automationsSwitchSession),
                    ),
                    OutlinedButton(
                      key: const Key('automationUnbindSession'),
                      onPressed: onUnbind,
                      child: Text(l10n.automationsUnbindSession),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
