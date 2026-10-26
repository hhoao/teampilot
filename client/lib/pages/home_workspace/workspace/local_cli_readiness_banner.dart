import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../cubits/session_preferences_cubit.dart';
import '../../../l10n/l10n_extensions.dart';
import '../../../models/cli_binary_kind.dart';
import '../../../models/install_job/install_job_scope.dart';
import '../../../models/team_config.dart';
import '../../../services/chat/launch/pre_send/local_binary_requirements.dart';
import '../../../services/cli/acp_adapter_discovery.dart';
import '../../../services/cli/cli_executable_discovery.dart';
import '../../../services/cli/codex/capabilities/acp_adapter_installer.dart';
import '../../../services/cli/installer_types.dart';
import '../../../services/cli/registry/capabilities/acp_settings_capability.dart';
import '../../../services/cli/registry/capabilities/cli_executable_capability.dart';
import '../../../services/cli/registry/cli_display_name.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../services/install/install_job_enqueue.dart';
import '../../../services/install/install_job_registry.dart';
import '../../../widgets/app_toast/app_toast.dart';
import '../../config/config_workspace.dart';

/// Banner under the compose card when the local host lacks a required CLI or
/// ACP adapter.
///
/// Mirrors [RemoteCliMachineReadinessPanel]: each row offers an in-app Install
/// (local install job) and Detect (PATH/well-known discovery) action, so the
/// user is not forced into Settings. Settings stays available for manual paths.
class LocalCliReadinessBanner extends StatefulWidget {
  const LocalCliReadinessBanner({required this.missing, super.key});

  final List<LocalBinaryRequirement> missing;

  @override
  State<LocalCliReadinessBanner> createState() =>
      _LocalCliReadinessBannerState();
}

class _LocalCliReadinessBannerState extends State<LocalCliReadinessBanner> {
  String? _busyKey;

  static bool _looksAbsolute(String value) =>
      value.contains('/') || value.contains(r'\');

  bool _supportsInstaller(CliToolRegistry registry, LocalBinaryRequirement req) {
    if (req.kind == CliBinaryKind.adapter) {
      return registry
              .capability<AcpSettingsCapability>(req.cli)
              ?.adapterInstaller !=
          null;
    }
    return registry
            .capability<CliExecutableCapability>(req.cli)
            ?.supportsInstaller ??
        false;
  }

  Future<void> _install(
    LocalBinaryRequirement requirement,
    CliToolRegistry registry,
  ) async {
    if (_busyKey != null) return;
    setState(() => _busyKey = requirement.key);
    try {
      final jobs = context.read<InstallJobRegistry>();
      final cubit = context.read<SessionPreferencesCubit>();
      final l10n = context.l10n;
      final result = requirement.kind == CliBinaryKind.adapter
          ? await _installAdapter(jobs, cubit, registry, requirement.cli, l10n)
          : await jobs.installCli(
              cli: requirement.cli,
              scope: const InstallJobScopeLocal(),
              title: l10n.cliInstallInstalling,
              onSucceeded: (installResult) async {
                final path = installResult.executablePath?.trim() ?? '';
                if (path.isEmpty) return;
                if (_looksAbsolute(path)) {
                  cubit.mergeLocatedExecutables({requirement.cli: path});
                }
                await cubit.setCliExecutablePathFor(requirement.cli, path);
              },
            );
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
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<CliInstallResult> _installAdapter(
    InstallJobRegistry jobs,
    SessionPreferencesCubit cubit,
    CliToolRegistry registry,
    CliTool cli,
    AppLocalizations l10n,
  ) {
    final installer = registry
        .capability<AcpSettingsCapability>(cli)
        ?.adapterInstaller;
    Future<void> onSucceeded(CliInstallResult installResult) async {
      final path = installResult.executablePath?.trim() ?? '';
      if (path.isEmpty || !_looksAbsolute(path)) return;
      cubit.mergeLocatedAcpAdapters({cli: path});
      await cubit.setAcpAdapterPathFor(cli, path);
    }

    final title = l10n.cliInstallInstalling;
    return installer is CodexAcpAdapterInstaller
        ? jobs.installCodexAcpAdapter(title: title, onSucceeded: onSucceeded)
        : jobs.installClaudeAcpAdapter(title: title, onSucceeded: onSucceeded);
  }

  Future<void> _locate(
    LocalBinaryRequirement requirement,
    CliToolRegistry registry,
  ) async {
    if (_busyKey != null) return;
    final cubit = context.read<SessionPreferencesCubit>();
    final l10n = context.l10n;
    final def = registry.tryGet(requirement.cli);
    final label = def != null
        ? cliDisplayName(def, l10n, registry: registry)
        : requirement.cli.value;
    setState(() => _busyKey = requirement.key);
    try {
      final path = requirement.kind == CliBinaryKind.adapter
          ? (await AcpAdapterDiscovery(
              registry: registry,
            ).locateLocal())[requirement.cli]?.trim() ??
                ''
          : (await CliExecutableDiscovery(
              registry: registry,
            ).locateLocalCli(requirement.cli))
                  ?.trim() ??
              '';
      if (!mounted) return;
      if (path.isEmpty) {
        AppToast.show(
          context,
          message: l10n.cliExecutablePathLocateFailed(label),
          variant: TpToastVariant.error,
        );
        return;
      }
      if (requirement.kind == CliBinaryKind.adapter) {
        cubit.mergeLocatedAcpAdapters({requirement.cli: path});
        await cubit.setAcpAdapterPathFor(requirement.cli, path);
      } else {
        cubit.mergeLocatedExecutables({requirement.cli: path});
        await cubit.setCliExecutablePathFor(requirement.cli, path);
      }
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.cliExecutablePathLocateSuccess(label, path),
        variant: TpToastVariant.success,
      );
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        message: l10n.cliExecutablePathLocateFailed(label),
        variant: TpToastVariant.error,
      );
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missing = widget.missing;
    if (missing.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final registry = CliToolRegistryScope.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TpCard.outlined(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.landingLaunchLocalCliMissingTitle,
                style: TpTextStyles.of(context).mdMedium,
              ),
              const SizedBox(height: 8),
              for (final requirement in missing)
                _LocalBinaryRow(
                  requirement: requirement,
                  registry: registry,
                  busy: _busyKey == requirement.key,
                  canInstall: _supportsInstaller(registry, requirement),
                  onInstall: () => unawaited(_install(requirement, registry)),
                  onLocate: () => unawaited(_locate(requirement, registry)),
                ),
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => openCliConfigManagement(context),
                  child: Text(l10n.landingLaunchLocalCliOpenSettings),
                ),
              ),
              Text(
                l10n.landingLaunchLocalCliMissingHint,
                style: TpTextStyles.of(context).smColored(cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocalBinaryRow extends StatelessWidget {
  const _LocalBinaryRow({
    required this.requirement,
    required this.registry,
    required this.busy,
    required this.canInstall,
    required this.onInstall,
    required this.onLocate,
  });

  final LocalBinaryRequirement requirement;
  final CliToolRegistry registry;
  final bool busy;
  final bool canInstall;
  final VoidCallback onInstall;
  final VoidCallback onLocate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final def = registry.tryGet(requirement.cli);
    final cliLabel = def != null
        ? cliDisplayName(def, l10n, registry: registry)
        : requirement.cli.value;
    final subtitle = requirement.kind == CliBinaryKind.adapter
        ? l10n.landingLaunchLocalAdapterMissingDetail(cliLabel)
        : l10n.landingLaunchLocalCliMissingDetail(cliLabel);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              style: TpTextStyles.of(context).mdColored(cs.onSurface),
            ),
          ),
          if (canInstall) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: busy ? null : onInstall,
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.cliInstallButton),
            ),
          ],
          const SizedBox(width: 4),
          TextButton(
            onPressed: busy ? null : onLocate,
            child: Text(l10n.cliExecutablePathLocate),
          ),
        ],
      ),
    );
  }
}
