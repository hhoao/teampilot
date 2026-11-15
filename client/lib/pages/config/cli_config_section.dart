import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/session_preferences_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/session_preferences.dart';
import '../../services/app/connection_mode_service.dart';
import '../../services/acp/acp_proxy_install.dart';
import '../../services/acp/acp_proxy_route.dart';
import '../../services/cli/cli_version_probe.dart';
import '../../services/cli/installer_types.dart';
import '../../services/cli/registry/capabilities/cli_executable_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../utils/ui/app_keys.dart';
import 'acp_proxy_machine_card.dart';
import 'cli_readiness_card.dart';
import 'toolchain_path_settings_row.dart';

class CliConfigWorkspace extends StatelessWidget {
  const CliConfigWorkspace({
    this.showHeading = true,
    this.versionProbe,
    this.acpProxyStatus,
    this.acpProxyAction,
    super.key,
  });

  final bool showHeading;

  /// Test seam: skip real `npm view` when pumping settings.
  final CliVersionProbe? versionProbe;

  /// Test seam for the remote keep-alive card. Null uses SSH.
  final Future<AcpProxyProbeSnapshot> Function()? acpProxyStatus;

  /// Test seam for install, update, and start. Null uses SSH.
  final Future<CliInstallResult> Function(AcpProxyCardAction action)?
  acpProxyAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeading) ...[
          _CliHeading(
            title: l10n.cli.config,
            subtitle: l10n.cli.configPageSubtitle,
          ),
          const SizedBox(height: 16),
        ],
        Expanded(
          child: _CliControls(
            versionProbe: versionProbe,
            acpProxyStatus: acpProxyStatus,
            acpProxyAction: acpProxyAction,
          ),
        ),
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
  const _CliControls({
    this.versionProbe,
    this.acpProxyStatus,
    this.acpProxyAction,
  });

  final CliVersionProbe? versionProbe;
  final Future<AcpProxyProbeSnapshot> Function()? acpProxyStatus;
  final Future<CliInstallResult> Function(AcpProxyCardAction action)?
  acpProxyAction;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<SessionPreferencesCubit>();
    final isSshMode = context.select<ConnectionModeService, bool>(
      (service) => service.isSshMode,
    );
    final registry = CliToolRegistry.builtIn();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TpSectionHeader(title: l10n.cli.configAiCliGroup),
          const SizedBox(height: 8),
          if (isSshMode) ...[
            AcpProxyMachineCard(
              loadStatus: acpProxyStatus,
              runAction: acpProxyAction,
            ),
            const SizedBox(height: 8),
          ],
          for (final def in registry.launchable)
            if (registry.capability<CliExecutableCapability>(def.id) != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TpCard.outlined(
                  child: CliReadinessCard(
                    cli: def.id,
                    cubit: cubit,
                    versionProbe: versionProbe,
                  ),
                ),
              ),
          const SizedBox(height: 24),
          TpSectionHeader(title: l10n.cli.configToolchainGroup),
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
                      ? l10n.toolchainPathDescriptionSsh(
                          tool: l10n.toolchainGit,
                        )
                      : l10n.toolchainPathDescription(tool: l10n.toolchainGit),
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
                      ? l10n.toolchainPathDescriptionSsh(
                          tool: l10n.toolchainNode,
                        )
                      : l10n.toolchainPathDescription(tool: l10n.toolchainNode),
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
