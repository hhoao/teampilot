import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../cubits/project_profile_cubit.dart';
import '../../../../l10n/l10n_extensions.dart';
import '../../../../models/project_profile.dart';
import '../../../../models/team_config.dart';
import '../../../../services/cli/registry/cli_display_name.dart';
import '../../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../../widgets/app_provider/brand_dropdown_rows.dart';
import '../../../../widgets/app_dialog.dart';
import '../../../../widgets/dropdown/app_dropdown_decoration.dart';
import '../../../../widgets/dropdown/app_dropdown_field.dart';
import '../../../../widgets/settings/workspace_settings_widgets.dart';
import 'project_cli_config_list.dart';

/// Default CLI picker + per-CLI provider/model defaults for personal projects.
class ProjectCliDefaultsSection extends StatelessWidget {
  const ProjectCliDefaultsSection({
    required this.profile,
    required this.cubit,
    super.key,
  });

  final ProjectProfile profile;
  final ProjectProfileCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dropdownDeco = AppDropdownDecorations.themed(context);
    final cliRegistry = CliToolRegistryScope.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSurfaceCard(
          child: SettingsLabeledStackedRow(
            title: l10n.teamCliLabel,
            subtitle: l10n.projectCliDefaultSubtitle,
            body: AppDropdownField<String>(
              items: [for (final def in cliRegistry.launchable) def.id.value],
              initialItem: CliTool.claude.value, // TODO: migrate to presets — was profile.cli.value
              decoration: dropdownDeco,
              onChanged: (value) {
                if (value == null) return;
                unawaited(cubit.setCli(CliTool.decode(value)));
              },
              itemBuilder: (context, value) => cliDropdownRow(
                context,
                cli: CliTool.decode(value),
                label: cliDisplayName(
                  cliRegistry.tryGet(CliTool.decode(value))!,
                  l10n,
                ),
                registry: cliRegistry,
              ),
            ),
            showDividerBelow: false,
          ),
        ),
        const SizedBox(height: 12),
        ProjectCliConfigList(profile: profile, cubit: cubit),
      ],
    );
  }
}

/// CLI defaults editor (sidebar config button and similar entry points).
Future<void> showProjectCliDefaultsDialog(
  BuildContext context, {
  required String projectId,
}) {
  final l10n = context.l10n;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return BlocBuilder<ProjectProfileCubit, ProjectProfileState>(
        builder: (context, state) {
          if (state.projectId != projectId ||
              state.status == ProjectProfileLoadStatus.loading ||
              state.status == ProjectProfileLoadStatus.idle) {
            return AppDialog(
              maxWidth: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppDialogHeader(title: l10n.projectCliDefaultsTitle),
                  const SizedBox(height: 24),
                  const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              ),
            );
          }
          if (state.status == ProjectProfileLoadStatus.error) {
            return AppDialog(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppDialogHeader(title: l10n.projectCliDefaultsTitle),
                  const SizedBox(height: 16),
                  Text(state.errorMessage ?? 'Failed to load profile'),
                  AppDialogActions(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(l10n.cancel),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
          final profile = state.profile;
          if (profile == null) {
            return AppDialog(
              maxWidth: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppDialogHeader(title: l10n.projectCliDefaultsTitle),
                  const SizedBox(height: 24),
                  const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              ),
            );
          }

          return AppDialog(
            maxWidth: 560,
            scrollable: true,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.85,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppDialogHeader(title: l10n.projectCliDefaultsTitle),
                const SizedBox(height: 16),
                ProjectCliDefaultsSection(
                  key: ValueKey('project-cli-defaults-${profile.projectId}'),
                  profile: profile,
                  cubit: context.read<ProjectProfileCubit>(),
                ),
                AppDialogActions(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: Text(l10n.cancel),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
