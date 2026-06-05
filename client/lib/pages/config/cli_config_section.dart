import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/team_config.dart';
import '../../utils/app_keys.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'cli_executable_path_settings_row.dart';

class CliConfigWorkspace extends StatelessWidget {
  const CliConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.watch<SessionPreferencesCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          _CliHeading(
            title: l10n.cliConfig,
            subtitle: l10n.cliConfigPageSubtitle,
          ),
          const SizedBox(height: 16),
        ],
        _CliControls(cubit: cubit),
      ],
    );
  }
}

class _CliHeading extends StatelessWidget {
  const _CliHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: tt.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _CliControls extends StatelessWidget {
  const _CliControls({required this.cubit});

  final SessionPreferencesCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isSshMode = cubit.isSshMode;

    return Expanded(
      child: SingleChildScrollView(
        child: SettingsSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CliExecutablePathSettingsRow(
                cubit: cubit,
                cli: CliTool.claude,
                title: l10n.claudeCliExecutablePathLabel,
                subtitle: isSshMode
                    ? l10n.claudeCliExecutablePathDescriptionSsh
                    : l10n.claudeCliExecutablePathDescription,
                fieldKey: AppKeys.claudeCliExecutablePathField,
                browseKey: AppKeys.claudeCliExecutablePathBrowseButton,
                resetKey: AppKeys.claudeCliExecutablePathResetButton,
                debouncerTag: 'claude_cli_executable_path',
                installKey: AppKeys.claudeCliInstallButton,
                showDividerBelow: true,
              ),
              CliExecutablePathSettingsRow(
                cubit: cubit,
                cli: CliTool.codex,
                title: l10n.cliExecutablePathLabelFor(
                  l10n.appProviderToolCodex,
                ),
                subtitle: isSshMode
                    ? l10n.cliExecutablePathDescriptionSshFor(
                        l10n.appProviderToolCodex,
                      )
                    : l10n.cliExecutablePathDescriptionFor(
                        l10n.appProviderToolCodex,
                      ),
                fieldKey: AppKeys.codexCliExecutablePathField,
                browseKey: AppKeys.codexCliExecutablePathBrowseButton,
                resetKey: AppKeys.codexCliExecutablePathResetButton,
                debouncerTag: 'codex_cli_executable_path',
                installKey: AppKeys.codexCliInstallButton,
                showDividerBelow: true,
              ),
              CliExecutablePathSettingsRow(
                cubit: cubit,
                cli: CliTool.opencode,
                title: l10n.cliExecutablePathLabelFor(
                  l10n.appProviderToolOpencode,
                ),
                subtitle: isSshMode
                    ? l10n.cliExecutablePathDescriptionSshFor(
                        l10n.appProviderToolOpencode,
                      )
                    : l10n.cliExecutablePathDescriptionFor(
                        l10n.appProviderToolOpencode,
                      ),
                fieldKey: AppKeys.opencodeCliExecutablePathField,
                browseKey: AppKeys.opencodeCliExecutablePathBrowseButton,
                resetKey: AppKeys.opencodeCliExecutablePathResetButton,
                debouncerTag: 'opencode_cli_executable_path',
                installKey: AppKeys.opencodeCliInstallButton,
                showDividerBelow: false,
              ),
              CliExecutablePathSettingsRow(
                cubit: cubit,
                cli: CliTool.flashskyai,
                title: l10n.cliExecutablePathLabel,
                subtitle: isSshMode
                    ? l10n.cliExecutablePathDescriptionSsh
                    : l10n.cliExecutablePathDescription,
                fieldKey: AppKeys.cliExecutablePathField,
                browseKey: AppKeys.cliExecutablePathBrowseButton,
                resetKey: AppKeys.cliExecutablePathResetButton,
                debouncerTag: 'cli_executable_path',
                showDividerBelow: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
