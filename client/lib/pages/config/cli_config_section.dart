import 'dart:io' show Platform;

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
import '../../services/install/install_job_enqueue.dart';
import '../../services/install/install_job_keys.dart';
import '../../services/install/install_job_registry.dart';
import '../../utils/ui/app_keys.dart';
import '../../widgets/app_toast/app_toast.dart';
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
  final spec = registry
      .capability<CliExecutableCapability>(cli)
      ?.executablePathRowSpec;
  if (spec == null) return const SizedBox.shrink();

  final label = l10n.appProviderToolLabel(cli);

  final pathRow = _buildCliPathRow(cli, cubit, isSshMode, l10n, spec, label);
  // Per-CLI extra settings row: built per `def.id` here, not scattered
  // through feature code.
  if (cli == CliTool.claude) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pathRow,
        ClaudePersonalAcpSettingsRow(cubit: cubit),
      ],
    );
  }
  if (cli == CliTool.cursor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pathRow,
        CursorPersonalAcpSettingsRow(cubit: cubit),
      ],
    );
  }
  if (cli == CliTool.codex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pathRow,
        CodexPersonalAcpSettingsRow(cubit: cubit),
      ],
    );
  }
  return pathRow;
}

/// Shared personal-ACP default switch.
///
/// Disabled on Android (ACP spawns a local process; remote SSH exec is not
/// available there yet).
class PersonalAcpSettingsRow extends StatelessWidget {
  const PersonalAcpSettingsRow({
    required this.switchKey,
    required this.label,
    required this.description,
    required this.androidDescription,
    required this.value,
    required this.onChanged,
    this.trailing,
    super.key,
  });

  final Key switchKey;
  final String label;
  final String description;
  final String androidDescription;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: switchKey,
          title: Text(label),
          subtitle: Text(onChanged == null ? androidDescription : description),
          value: value,
          onChanged: onChanged,
        ),
        if (trailing != null) trailing!,
        const Divider(height: 1),
      ],
    );
  }
}

/// Claude: run new personal sessions as terminal-less ACP chat.
class ClaudePersonalAcpSettingsRow extends StatelessWidget {
  const ClaudePersonalAcpSettingsRow({
    required this.cubit,
    @visibleForTesting this.isAndroidOverride,
    super.key,
  });

  final SessionPreferencesCubit cubit;
  final bool? isAndroidOverride;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isAndroid = isAndroidOverride ?? Platform.isAndroid;
    return BlocBuilder<SessionPreferencesCubit, SessionPreferencesState>(
      bloc: cubit,
      buildWhen: (a, b) =>
          a.preferences.claudePersonalAcpDefault !=
          b.preferences.claudePersonalAcpDefault,
      builder: (context, state) {
        return PersonalAcpSettingsRow(
          switchKey: AppKeys.claudePersonalAcpSwitch,
          label: l10n.claudePersonalAcpDefaultLabel,
          description: l10n.claudePersonalAcpDefaultDescription,
          androidDescription: l10n.claudePersonalAcpAndroidDisabled,
          value: !isAndroid && state.preferences.claudePersonalAcpDefault,
          onChanged: isAndroid
              ? null
              : (value) => cubit.setClaudePersonalAcpDefault(value),
          trailing: isAndroid ? null : const _ClaudeAcpAdapterInstallButton(),
        );
      },
    );
  }
}

/// Cursor: run new personal sessions as terminal-less ACP chat.
///
/// No adapter install button — `cursor-agent acp` is built in.
class CursorPersonalAcpSettingsRow extends StatelessWidget {
  const CursorPersonalAcpSettingsRow({
    required this.cubit,
    @visibleForTesting this.isAndroidOverride,
    super.key,
  });

  final SessionPreferencesCubit cubit;
  final bool? isAndroidOverride;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isAndroid = isAndroidOverride ?? Platform.isAndroid;
    return BlocBuilder<SessionPreferencesCubit, SessionPreferencesState>(
      bloc: cubit,
      buildWhen: (a, b) =>
          a.preferences.cursorPersonalAcpDefault !=
          b.preferences.cursorPersonalAcpDefault,
      builder: (context, state) {
        return PersonalAcpSettingsRow(
          switchKey: AppKeys.cursorPersonalAcpSwitch,
          label: l10n.cursorPersonalAcpDefaultLabel,
          description: l10n.cursorPersonalAcpDefaultDescription,
          androidDescription: l10n.claudePersonalAcpAndroidDisabled,
          value: !isAndroid && state.preferences.cursorPersonalAcpDefault,
          onChanged: isAndroid
              ? null
              : (value) => cubit.setCursorPersonalAcpDefault(value),
        );
      },
    );
  }
}

class _ClaudeAcpAdapterInstallButton extends StatefulWidget {
  const _ClaudeAcpAdapterInstallButton();

  @override
  State<_ClaudeAcpAdapterInstallButton> createState() =>
      _ClaudeAcpAdapterInstallButtonState();
}

class _ClaudeAcpAdapterInstallButtonState
    extends State<_ClaudeAcpAdapterInstallButton> {
  Future<void> _install() async {
    final registry = context.read<InstallJobRegistry>();
    final title = context.l10n.cliInstallInstalling;
    setState(() {});
    try {
      final result = await registry.installClaudeAcpAdapter(title: title);
      if (!mounted) return;
      AppToast.show(
        context,
        message: result.message,
        variant: result.success ? TpToastVariant.success : TpToastVariant.error,
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: error.toString(),
        variant: TpToastVariant.error,
      );
    } finally {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = context.read<InstallJobRegistry>();
    final installing = registry.isRunning(InstallJobKeys.claudeAcpAdapter());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          key: AppKeys.claudeAcpAdapterInstallButton,
          onPressed: installing ? null : _install,
          icon: installing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.download_outlined, size: context.tpIconSizes.md),
          label: Text(
            installing
                ? l10n.cliInstallInstalling
                : l10n.claudeAcpAdapterInstallButton,
          ),
        ),
      ),
    );
  }
}

/// Codex: run new personal sessions as terminal-less ACP chat.
///
/// Disabled on Android (ACP spawns a local process; remote SSH exec is not
/// available there yet).
class CodexPersonalAcpSettingsRow extends StatelessWidget {
  const CodexPersonalAcpSettingsRow({
    required this.cubit,
    @visibleForTesting this.isAndroidOverride,
    super.key,
  });

  final SessionPreferencesCubit cubit;
  final bool? isAndroidOverride;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isAndroid = isAndroidOverride ?? Platform.isAndroid;
    return BlocBuilder<SessionPreferencesCubit, SessionPreferencesState>(
      bloc: cubit,
      buildWhen: (a, b) =>
          a.preferences.codexPersonalAcpDefault !=
          b.preferences.codexPersonalAcpDefault,
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              key: AppKeys.codexPersonalAcpSwitch,
              title: Text(l10n.codexPersonalAcpDefaultLabel),
              subtitle: Text(
                isAndroid
                    ? l10n.codexPersonalAcpAndroidDisabled
                    : l10n.codexPersonalAcpDefaultDescription,
              ),
              value: !isAndroid && state.preferences.codexPersonalAcpDefault,
              onChanged: isAndroid
                  ? null
                  : (value) => cubit.setCodexPersonalAcpDefault(value),
            ),
            // Desktop-only: ACP spawns a local process. Install is
            // user-initiated here; connect never installs.
            if (!isAndroid) const _CodexAcpAdapterInstallButton(),
            const Divider(height: 1),
          ],
        );
      },
    );
  }
}

class _CodexAcpAdapterInstallButton extends StatefulWidget {
  const _CodexAcpAdapterInstallButton();

  @override
  State<_CodexAcpAdapterInstallButton> createState() =>
      _CodexAcpAdapterInstallButtonState();
}

class _CodexAcpAdapterInstallButtonState
    extends State<_CodexAcpAdapterInstallButton> {
  Future<void> _install() async {
    final registry = context.read<InstallJobRegistry>();
    final title = context.l10n.cliInstallInstalling;
    setState(() {});
    try {
      final result = await registry.installCodexAcpAdapter(title: title);
      if (!mounted) return;
      AppToast.show(
        context,
        message: result.message,
        variant: result.success ? TpToastVariant.success : TpToastVariant.error,
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: error.toString(),
        variant: TpToastVariant.error,
      );
    } finally {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final registry = context.read<InstallJobRegistry>();
    final installing = registry.isRunning(InstallJobKeys.codexAcpAdapter());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton.icon(
          key: AppKeys.codexAcpAdapterInstallButton,
          onPressed: installing ? null : _install,
          icon: installing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.download_outlined, size: context.tpIconSizes.md),
          label: Text(
            installing
                ? l10n.cliInstallInstalling
                : l10n.claudeAcpAdapterInstallButton,
          ),
        ),
      ),
    );
  }
}

Widget _buildCliPathRow(
  CliTool cli,
  SessionPreferencesCubit cubit,
  bool isSshMode,
  AppLocalizations l10n,
  CliExecutablePathRowSpec spec,
  String label,
) {
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
