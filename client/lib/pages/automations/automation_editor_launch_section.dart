import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/expert_hub_cubit.dart';
import '../../cubits/launch_profile_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../pages/expert_hub/expert_landing_picker_sheet.dart';
import '../../pages/home_workspace/workspace/workspace_landing_location_fields.dart';
import '../../services/expert_hub/expert_member_resolver.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/cli/cli_preset_dropdown_field.dart';
import '../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../widgets/dropdown/app_dropdown_field.dart';
import '../../widgets/form/app_form_field.dart';
import '../../widgets/form/app_form_field_layout.dart';

/// Launch parameters for launch-prompt automations — mirrors landing compose.
class AutomationEditorLaunchSection extends StatelessWidget {
  const AutomationEditorLaunchSection({
    required this.workspace,
    required this.isPersonal,
    required this.projectFolderPath,
    required this.workingDirectoryPath,
    required this.presetId,
    required this.teamId,
    required this.expertKey,
    required this.dangerouslySkipPermissions,
    required this.targetMemberId,
    required this.labelWidth,
    required this.onProjectChanged,
    required this.onWorktreeChanged,
    required this.onIsPersonalChanged,
    required this.onPresetChanged,
    required this.onTeamChanged,
    required this.onExpertChanged,
    required this.onPermissionsChanged,
    required this.onTargetMemberChanged,
    super.key,
  });

  final Workspace workspace;
  final bool isPersonal;
  final String? projectFolderPath;
  final String? workingDirectoryPath;
  final String? presetId;
  final String? teamId;
  final String? expertKey;
  final bool dangerouslySkipPermissions;
  final String targetMemberId;
  final double labelWidth;
  final ValueChanged<String?> onProjectChanged;
  final ValueChanged<String?> onWorktreeChanged;
  final ValueChanged<bool> onIsPersonalChanged;
  final ValueChanged<String?> onPresetChanged;
  final ValueChanged<String?> onTeamChanged;
  final ValueChanged<String?> onExpertChanged;
  final ValueChanged<bool> onPermissionsChanged;
  final ValueChanged<String> onTargetMemberChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final teams = context.watch<LaunchProfileCubit>().state.teams;
    final hubState = context.watch<ExpertHubCubit>().state;
    final team = teams.where((t) => t.id == teamId).firstOrNull;
    final teamMembers =
        team?.members.where((m) => m.isValid).toList(growable: false) ??
        const <TeamMemberConfig>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorkspaceLandingLocationFields(
          workspace: workspace,
          projectFolderPath: projectFolderPath,
          workingDirectoryPath: workingDirectoryPath,
          labelWidth: labelWidth,
          onProjectChanged: onProjectChanged,
          onWorktreeChanged: onWorktreeChanged,
        ),
        AppFormField<String>(
          key: ValueKey('launch-mode-$isPersonal'),
          id: 'launchMode',
          initialValue: isPersonal ? 'simple' : 'team',
          label: Text(l10n.automationsLaunchMode),
          layoutStyle: AppFormFieldLayoutStyle.inline,
          labelWidth: labelWidth,
          builder: (state) {
            return AppDropdownField<String>(
              items: const ['simple', 'team'],
              initialItem: state.value ?? 'simple',
              decoration: AppDropdownDecorations.themed(context),
              itemLabel: (value) => value == 'simple'
                  ? l10n.workspaceChatLandingModeSimple
                  : l10n.workspaceChatLandingModeTeam,
              onChanged: (value) {
                if (value == null) return;
                state.didChange(value);
                onIsPersonalChanged(value == 'simple');
              },
            );
          },
        ),
        const SizedBox(height: 12),
        if (isPersonal) ...[
          AppFormField<String>(
            key: ValueKey('preset-${presetId ?? ''}'),
            id: 'presetId',
            initialValue: presetId ?? '',
            label: Text(l10n.presetPickerTitle),
            layoutStyle: AppFormFieldLayoutStyle.inline,
            labelWidth: labelWidth,
            validator: (v) =>
                (v == null || v.trim().isEmpty)
                ? l10n.workspaceCliPresetsEmptyHint
                : null,
            builder: (state) {
              return CliPresetDropdownField(
                selectedPresetId: state.value,
                onChanged: (value) {
                  state.didChange(value ?? '');
                  onPresetChanged(value);
                },
              );
            },
          ),
          const SizedBox(height: 12),
          AppFormField<String>(
            key: ValueKey('expert-${expertKey ?? ''}'),
            id: 'expertKey',
            initialValue: expertKey ?? '',
            label: Text(l10n.hubPublishKindExpert),
            layoutStyle: AppFormFieldLayoutStyle.inline,
            labelWidth: labelWidth,
            builder: (state) {
              final label = ExpertMemberResolver.labelForKey(
                key: expertKey,
                fallbackLabel: l10n.expertHubNoneSelected,
                hubState: hubState,
              );
              return Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: () async {
                    final key = await showExpertLandingPickerSheet(
                      context,
                      selectedKey: expertKey,
                    );
                    if (!context.mounted) return;
                    state.didChange(key ?? '');
                    onExpertChanged(key);
                  },
                  child: Text(label),
                ),
              );
            },
          ),
        ] else ...[
          AppFormField<String>(
            key: ValueKey('team-${teamId ?? ''}'),
            id: 'teamId',
            initialValue: teamId ?? '',
            label: Text(l10n.selectTeam),
            layoutStyle: AppFormFieldLayoutStyle.inline,
            labelWidth: labelWidth,
            validator: (v) {
              if (teams.isEmpty) return l10n.automationsValidationRequired;
              final id = v?.trim() ?? '';
              if (id.isEmpty) return l10n.automationsValidationRequired;
              return null;
            },
            builder: (state) {
              if (teams.isEmpty) {
                return Text(
                  l10n.automationsValidationRequired,
                  style: AppTextStyles.of(context).mdColored(
                    Theme.of(context).colorScheme.error,
                  ),
                );
              }
              final initial = teams.any((t) => t.id == state.value)
                  ? state.value
                  : teams.first.id;
              return AppDropdownField<String>(
                items: teams.map((t) => t.id).toList(growable: false),
                initialItem: initial,
                decoration: AppDropdownDecorations.themed(context),
                itemLabel: (id) {
                  final match = teams.where((t) => t.id == id).firstOrNull;
                  return match?.name.trim().isNotEmpty == true
                      ? match!.name.trim()
                      : id;
                },
                onChanged: (value) {
                  if (value == null) return;
                  state.didChange(value);
                  onTeamChanged(value);
                },
              );
            },
          ),
          const SizedBox(height: 12),
          AppFormField<String>(
            key: ValueKey('target-member-$targetMemberId'),
            id: 'targetMemberId',
            initialValue: targetMemberId,
            label: Text(l10n.automationsTargetMember),
            layoutStyle: AppFormFieldLayoutStyle.inline,
            labelWidth: labelWidth,
            validator: (v) {
              if (teamMembers.isEmpty) {
                return l10n.automationsValidationRequired;
              }
              final id = v?.trim() ?? '';
              if (id.isEmpty) return l10n.automationsValidationRequired;
              return null;
            },
            builder: (state) {
              if (teamMembers.isEmpty) {
                return Text(
                  l10n.automationsValidationRequired,
                  style: AppTextStyles.of(context).mdColored(
                    Theme.of(context).colorScheme.error,
                  ),
                );
              }
              final initial = teamMembers.any((m) => m.id == state.value)
                  ? state.value
                  : teamMembers.first.id;
              return AppDropdownField<String>(
                items: teamMembers.map((m) => m.id).toList(growable: false),
                initialItem: initial,
                decoration: AppDropdownDecorations.themed(context),
                itemLabel: (memberId) {
                  final member = teamMembers
                      .where((m) => m.id == memberId)
                      .firstOrNull;
                  return member?.name ?? memberId;
                },
                onChanged: (value) {
                  if (value == null) return;
                  state.didChange(value);
                  onTargetMemberChanged(value);
                },
              );
            },
          ),
        ],
        const SizedBox(height: 12),
        AppFormField<bool>(
          key: ValueKey('permissions-$dangerouslySkipPermissions'),
          id: 'dangerouslySkipPermissions',
          initialValue: dangerouslySkipPermissions,
          label: Text(l10n.automationsPermissions),
          layoutStyle: AppFormFieldLayoutStyle.inline,
          labelWidth: labelWidth,
          builder: (state) {
            return AppDropdownField<bool>(
              items: const [false, true],
              initialItem: state.value ?? false,
              decoration: AppDropdownDecorations.themed(context),
              itemLabel: (value) => value
                  ? l10n.workspaceChatLandingFullAccessPermissions
                  : l10n.workspaceChatLandingDefaultPermissions,
              onChanged: (value) {
                if (value == null) return;
                state.didChange(value);
                onPermissionsChanged(value);
              },
            );
          },
        ),
      ],
    );
  }
}
