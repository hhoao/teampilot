import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cli_preset.dart';
import '../../../models/runtime_target.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';
import '../../../services/cli/installer_types.dart';
import '../../../services/cli/registry/capabilities/installer_capability.dart';
import '../../../services/cli/registry/cli_display_name.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';
import '../../../services/remote/remote_cli_readiness.dart';
import '../../../services/remote/remote_cli_requirements.dart';
import '../../../theme/app_text_styles.dart';
import '../../../widgets/cli_install_progress_panel.dart';
import '../../../widgets/settings/workspace_settings_widgets.dart';

/// Per-SSH-host CLI locate status and user-driven install for Machines placement.
class RemoteCliMachineReadinessPanel extends StatefulWidget {
  const RemoteCliMachineReadinessPanel({
    required this.workspace,
    required this.team,
    required this.placement,
    required this.selectedTargetId,
    required this.globalPresets,
    required this.selectableTargets,
    required this.readiness,
    super.key,
  });

  final Workspace workspace;
  final TeamProfile team;
  final MemberPlacementByTarget placement;
  final String selectedTargetId;
  final List<CliPreset> globalPresets;
  final List<RuntimeTarget> selectableTargets;
  final RemoteCliReadinessService readiness;

  @override
  State<RemoteCliMachineReadinessPanel> createState() =>
      _RemoteCliMachineReadinessPanelState();
}

class _RemoteCliMachineReadinessPanelState
    extends State<RemoteCliMachineReadinessPanel> {
  final _readinessByKey = <String, RemoteCliReadiness>{};
  var _probeGeneration = 0;
  String? _installingKey;
  CliInstallProgress? _installProgress;

  @override
  void initState() {
    super.initState();
    _scheduleProbe();
  }

  @override
  void didUpdateWidget(covariant RemoteCliMachineReadinessPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedTargetId != widget.selectedTargetId ||
        oldWidget.placement != widget.placement ||
        oldWidget.team != widget.team) {
      _scheduleProbe();
    }
  }

  RuntimeTarget? get _selectedTarget {
    for (final target in widget.selectableTargets) {
      if (target.id == widget.selectedTargetId) return target;
    }
    return null;
  }

  List<RemoteCliRequirement> get _requirementsForHost {
    final target = _selectedTarget;
    if (target == null || target.kind != RuntimeKind.ssh) return const [];
    final all = remoteCliRequirementsForPlacement(
      workspace: widget.workspace,
      team: widget.team,
      placement: widget.placement,
      globalPresets: widget.globalPresets,
      selectableTargets: widget.selectableTargets,
    );
    return [
      for (final req in all)
        if (req.target.id == target.id) req,
    ];
  }

  void _scheduleProbe() {
    final generation = ++_probeGeneration;
    unawaited(_probe(generation));
  }

  Future<void> _probe(int generation) async {
    final requirements = _requirementsForHost;
    if (requirements.isEmpty) {
      if (!mounted || generation != _probeGeneration) return;
      setState(() => _readinessByKey.clear());
      return;
    }

    final next = <String, RemoteCliReadiness>{};
    for (final requirement in requirements) {
      if (!mounted || generation != _probeGeneration) return;
      next[requirement.cacheKey] = RemoteCliProbing(
        targetId: requirement.target.id,
        cli: requirement.cli,
      );
      setState(() => _readinessByKey
        ..clear()
        ..addAll(next));

      final result = await widget.readiness.probe(
        target: requirement.target,
        cli: requirement.cli,
      );
      if (!mounted || generation != _probeGeneration) return;
      next[requirement.cacheKey] = result;
      setState(() => _readinessByKey[requirement.cacheKey] = result);
    }
  }

  Future<void> _install(RemoteCliRequirement requirement) async {
    if (_installingKey != null) return;
    setState(() {
      _installingKey = requirement.cacheKey;
      _installProgress = null;
    });
    try {
      final result = await widget.readiness.install(
        target: requirement.target,
        cli: requirement.cli,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _installProgress = progress);
        },
      );
      if (!mounted) return;
      setState(() => _readinessByKey[requirement.cacheKey] = result);
    } finally {
      if (mounted) {
        setState(() {
          _installingKey = null;
          _installProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final requirements = _requirementsForHost;
    if (requirements.isEmpty) return const SizedBox.shrink();

    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final registry = CliToolRegistryScope.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SettingsSurfaceCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.remoteCliMachineReadinessTitle,
                style: AppTextStyles.of(context).mdMedium,
              ),
              const SizedBox(height: 8),
              for (final requirement in requirements)
                _CliReadinessRow(
                  requirement: requirement,
                  readiness: _readinessByKey[requirement.cacheKey],
                  registry: registry,
                  installing: _installingKey == requirement.cacheKey,
                  onInstall: () => unawaited(_install(requirement)),
                ),
              if (_installingKey != null && _installProgress != null) ...[
                const SizedBox(height: 8),
                CliInstallProgressPanel(
                  phase: _installProgress!.phase,
                  logLines: [
                    if ((_installProgress!.detail ?? '').trim().isNotEmpty)
                      _installProgress!.detail!.trim(),
                  ],
                ),
              ] else if (requirements.any((r) {
                final state = _readinessByKey[r.cacheKey];
                return state is RemoteCliMissing || state is RemoteCliFailed;
              })) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.remoteCliMachineReadinessInstallHint,
                  style: AppTextStyles.of(context).smColored(cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CliReadinessRow extends StatelessWidget {
  const _CliReadinessRow({
    required this.requirement,
    required this.readiness,
    required this.registry,
    required this.installing,
    required this.onInstall,
  });

  final RemoteCliRequirement requirement;
  final RemoteCliReadiness? readiness;
  final CliToolRegistry registry;
  final bool installing;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final def = registry.tryGet(requirement.cli);
    final cliLabel = def != null
        ? cliDisplayName(def, l10n, registry: registry)
        : requirement.cli.value;
    final supportsInstaller =
        registry.capability<InstallerCapability>(requirement.cli)?.supportsInstaller ??
        false;

    final (icon, color, subtitle) = switch (readiness) {
      null || RemoteCliProbing() => (
        Icons.hourglass_empty,
        cs.onSurfaceVariant,
        l10n.remoteCliMachineReadinessProbing,
      ),
      RemoteCliReady(:final path) => (
        Icons.check_circle_outline,
        cs.primary,
        l10n.remoteCliMachineReadinessReady(cliLabel, path),
      ),
      RemoteCliMissing() => (
        Icons.error_outline,
        cs.error,
        l10n.remoteCliMachineReadinessMissing(cliLabel),
      ),
      RemoteCliFailed(:final message) => (
        Icons.error_outline,
        cs.error,
        l10n.remoteCliMachineReadinessFailed(cliLabel, message),
      ),
      RemoteCliInstalling() => (
        Icons.download_outlined,
        cs.onSurfaceVariant,
        l10n.cliInstallInstalling,
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cliLabel, style: AppTextStyles.of(context).md),
                Text(
                  subtitle,
                  style: AppTextStyles.of(context).smColored(color),
                ),
              ],
            ),
          ),
          if (supportsInstaller &&
              (readiness is RemoteCliMissing ||
                  readiness is RemoteCliFailed)) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: installing ? null : onInstall,
              child: installing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.cliInstallButton),
            ),
          ],
        ],
      ),
    );
  }
}
