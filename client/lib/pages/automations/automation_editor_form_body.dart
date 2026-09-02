import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/workspace.dart';
import '../../models/launch_security_policy.dart';
import '../../services/automation/automation_schedule_calculator.dart';
import '../../services/automation/automation_schedule_defaults.dart';
import 'package:shared_ui/shared_ui.dart';
import 'automation_editor_launch_section.dart';
import 'automation_schedule_picker.dart';

/// Label column width for the automation editor inline form.
const double kAutomationEditorFormLabelWidth = 160;

/// Field body for [AutomationEditorDialog] under an [TpForm].
class AutomationEditorFormBody extends StatelessWidget {
  const AutomationEditorFormBody({
    required this.isScheduledMessage,
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
    this.onMaxRunCountChanged,
    this.workspace,
    this.isPersonal = true,
    this.projectFolderPath,
    this.workingDirectoryPath,
    this.presetId,
    this.teamId,
    this.expertKey,
    this.launchSecurityPolicy = LaunchSecurityPolicy.fullAccess,
    this.targetMemberId = 'team-lead',
    this.onIsPersonalChanged,
    this.onProjectChanged,
    this.onWorktreeChanged,
    this.onPresetChanged,
    this.onTeamChanged,
    this.onExpertChanged,
    this.onPermissionsChanged,
    this.onTargetMemberChanged,
    super.key,
  });

  final bool isScheduledMessage;
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
  final VoidCallback? onMaxRunCountChanged;
  final Workspace? workspace;
  final bool isPersonal;
  final String? projectFolderPath;
  final String? workingDirectoryPath;
  final String? presetId;
  final String? teamId;
  final String? expertKey;
  final LaunchSecurityPolicy launchSecurityPolicy;
  final String targetMemberId;
  final ValueChanged<bool>? onIsPersonalChanged;
  final ValueChanged<String?>? onProjectChanged;
  final ValueChanged<String?>? onWorktreeChanged;
  final ValueChanged<String?>? onPresetChanged;
  final ValueChanged<String?>? onTeamChanged;
  final ValueChanged<String?>? onExpertChanged;
  final ValueChanged<LaunchSecurityPolicy>? onPermissionsChanged;
  final ValueChanged<String>? onTargetMemberChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bodyStyle = TpTextStyles.of(context).md;

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
        if (!isScheduledMessage && workspace != null) ...[
          const SizedBox(height: 12),
          AutomationEditorLaunchSection(
            workspace: workspace!,
            isPersonal: isPersonal,
            projectFolderPath: projectFolderPath,
            workingDirectoryPath: workingDirectoryPath,
            presetId: presetId,
            teamId: teamId,
            expertKey: expertKey,
            launchSecurityPolicy: launchSecurityPolicy,
            targetMemberId: targetMemberId,
            labelWidth: kAutomationEditorFormLabelWidth,
            onProjectChanged: onProjectChanged ?? (_) {},
            onWorktreeChanged: onWorktreeChanged ?? (_) {},
            onIsPersonalChanged: onIsPersonalChanged ?? (_) {},
            onPresetChanged: onPresetChanged ?? (_) {},
            onTeamChanged: onTeamChanged ?? (_) {},
            onExpertChanged: onExpertChanged ?? (_) {},
            onPermissionsChanged: onPermissionsChanged ?? (_) {},
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
