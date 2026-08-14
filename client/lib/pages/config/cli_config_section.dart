import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/session_preferences.dart';
import '../../models/team_config.dart';
import '../../services/app/connection_mode_service.dart';
import '../../services/cli/registry/capabilities/cli_executable_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../utils/ui/app_keys.dart';
import 'cli_executable_path_settings_row.dart';
import 'toolchain_path_settings_row.dart';

class CliConfigWorkspace extends StatelessWidget {
  const CliConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
        const Expanded(child: _CliControls()),
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
    final styles = TpTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: styles.lgSemiboldSnug),
        const SizedBox(height: 6),
        Text(subtitle, style: styles.mutedMd),
      ],
    );
  }
}

class _CliControls extends StatelessWidget {
  const _CliControls();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<SessionPreferencesCubit>();
    final isSshMode = context.select<ConnectionModeService, bool>(
      (service) => service.isSshMode,
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- AI CLI -----------------------------------------------------
          TpSectionHeader(title: l10n.cliConfigAiCliGroup),
          const SizedBox(height: 8),
          TpCard.outlined(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final def in CliToolRegistry.builtIn().launchable)
                  _buildCliRow(def.id, cubit, isSshMode, l10n),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // ---- Toolchain --------------------------------------------------
          TpSectionHeader(title: l10n.cliConfigToolchainGroup),
          const SizedBox(height: 8),
          TpCard.outlined(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ToolchainPathSettingsRow(
                  cubit: cubit,
                  toolId: SessionPreferences.toolchainGit,
                  title: l10n.toolchainGitLabel,
                  subtitle: isSshMode
                      ? l10n.toolchainPathDescriptionSsh(l10n.toolchainGit)
                      : l10n.toolchainPathDescription(l10n.toolchainGit),
                  fallbackExecutable: 'git',
                  fieldKey: AppKeys.gitToolchainPathField,
                  browseKey: AppKeys.gitToolchainPathBrowseButton,
                  resetKey: AppKeys.gitToolchainPathResetButton,
                  installKey: AppKeys.gitToolchainInstallButton,
                  debouncerTag: 'git_toolchain_path',
                  leadingIcon: Icons.account_tree_outlined,
                  showDividerBelow: true,
                ),
                ToolchainPathSettingsRow(
                  cubit: cubit,
                  toolId: SessionPreferences.toolchainNode,
                  title: l10n.toolchainNodeLabel,
                  subtitle: isSshMode
                      ? l10n.toolchainPathDescriptionSsh(l10n.toolchainNode)
                      : l10n.toolchainPathDescription(l10n.toolchainNode),
                  fallbackExecutable: 'node',
                  fieldKey: AppKeys.nodeToolchainPathField,
                  browseKey: AppKeys.nodeToolchainPathBrowseButton,
                  resetKey: AppKeys.nodeToolchainPathResetButton,
                  installKey: AppKeys.nodeToolchainInstallButton,
                  debouncerTag: 'node_toolchain_path',
                  leadingIcon: Icons.javascript_outlined,
                  showDividerBelow: false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildCliRow(
  CliTool cli,
  SessionPreferencesCubit cubit,
  bool isSshMode,
  AppLocalizations l10n,
) {
  final registry = CliToolRegistry.builtIn();
  final spec =
      registry.capability<CliExecutableCapability>(cli)?.executablePathRowSpec;
  if (spec == null) return const SizedBox.shrink();

  final label = l10n.appProviderToolLabel(cli);

  return CliExecutablePathSettingsRow(
    cubit: cubit,
    cli: cli,
    title: spec.isCustomTitle
        ? l10n.claudeCliExecutablePathLabel
        : l10n.cliExecutablePathLabelFor(label),
    subtitle: spec.isCustomTitle
        ? isSshMode
            ? l10n.claudeCliExecutablePathDescriptionSsh
            : l10n.claudeCliExecutablePathDescription
        : isSshMode
            ? l10n.cliExecutablePathDescriptionSshFor(label)
            : l10n.cliExecutablePathDescriptionFor(label),
    fieldKey: ValueKey(spec.fieldKey),
    browseKey: ValueKey(spec.browseKey),
    resetKey: ValueKey(spec.resetKey),
    debouncerTag: spec.debouncerTag,
    installKey: ValueKey(spec.installKey),
    showDividerBelow: spec.showDividerBelow,
  );
}
