import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_ui/shared_ui.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../models/cli_preset.dart';
import '../../../models/install_job/install_cancel_policy.dart';
import '../../../models/install_job/install_job_scope.dart';
import '../../../models/install_job/install_job_spec.dart';
import '../../../models/runtime_target.dart';
import '../../../models/team_config.dart';
import '../../../models/workspace.dart';
import '../../../models/workspace_topology.dart';
import '../../../services/cli/installer_types.dart';
import '../../../services/cli/registry/capabilities/cli_executable_capability.dart';
import '../../../services/cli/registry/cli_display_name.dart';
import '../../../services/cli/registry/cli_tool_registry_scope.dart';
import '../../../services/cli/registry/cli_tool_registry.dart';
import '../../../services/install/install_job_keys.dart';
import '../../../services/install/install_job_registry.dart';
import '../../../services/remote/remote_cli_readiness.dart';
import '../../../services/remote/remote_cli_requirements.dart';

/// Per-SSH-host CLI locate status and user-driven install for Machines placement.
class RemoteCliMachineReadinessPanel extends StatefulWidget {
  const RemoteCliMachineReadinessPanel({
    required this.readiness,
    this.workspace,
    this.team,
    this.placement,
    this.selectedTargetId,
    this.globalPresets = const [],
    this.selectableTargets = const [],
    this.fixedRequirements,
    this.onReadinessChanged,
    super.key,
  });

  final Workspace? workspace;
  final TeamProfile? team;
  final MemberPlacementByTarget? placement;
  final String? selectedTargetId;
  final List<CliPreset> globalPresets;
  final List<RuntimeTarget> selectableTargets;
  final RemoteCliReadinessService readiness;

  /// When set, skips placement-derived requirements (e.g. compose landing).
  final List<RemoteCliRequirement>? fixedRequirements;
  final VoidCallback? onReadinessChanged;

  @override
  State<RemoteCliMachineReadinessPanel> createState() =>
      _RemoteCliMachineReadinessPanelState();
}

class _RemoteCliMachineReadinessPanelState
    extends State<RemoteCliMachineReadinessPanel> {
  final _readinessByKey = <String, RemoteCliReadiness>{};
  var _probeGeneration = 0;
  String? _installingKey;

  @override
  void initState() {
    super.initState();
    _scheduleProbe();
  }

  @override
  void didUpdateWidget(covariant RemoteCliMachineReadinessPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.fixedRequirements, widget.fixedRequirements) ||
        oldWidget.selectedTargetId != widget.selectedTargetId ||
        oldWidget.placement != widget.placement ||
        oldWidget.team != widget.team) {
      _scheduleProbe();
    }
  }

  RuntimeTarget? get _selectedTarget {
    final targetId = widget.selectedTargetId;
    if (targetId == null) return null;
    for (final target in widget.selectableTargets) {
      if (target.id == targetId) return target;
    }
    return null;
  }

  List<RemoteCliRequirement> get _requirementsForHost {
    final fixed = widget.fixedRequirements;
    if (fixed != null) return fixed;

    final workspace = widget.workspace;
    final team = widget.team;
    final placement = widget.placement;
    if (workspace == null || team == null || placement == null) {
      return const [];
    }

    final target = _selectedTarget;
    if (target == null || !usesSshTransport(target.kind)) return const [];
    final all = remoteCliRequirementsForPlacement(
      workspace: workspace,
      team: team,
      placement: placement,
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
    setState(() => _installingKey = requirement.cacheKey);
    try {
      final registry = context.read<InstallJobRegistry>();
      final l10n = context.l10n;
      final cliRegistry = CliToolRegistryScope.of(context);
      final def = cliRegistry.tryGet(requirement.cli);
      final cliLabel = def != null
          ? cliDisplayName(def, l10n, registry: cliRegistry)
          : requirement.cli.value;
      final hostLabel = requirement.target.label.trim().isNotEmpty
          ? requirement.target.label
          : requirement.target.id;
      final profileId = requirement.target.sshProfileId ?? '';
      final scope = profileId.isEmpty
          ? const InstallJobScopeLocal()
          : InstallJobScopeSsh(profileId);
      final key = InstallJobKeys.cli(requirement.cli.value, scope: scope);

      final result = await registry.enqueue(
        InstallJobSpec<RemoteCliReadiness>(
          key: key,
          title: 'Install $cliLabel on $hostLabel',
          workspaceId: widget.workspace?.workspaceId,
          cancelPolicy: InstallCancelPolicy.cooperative,
          historyMessageFor: (readiness) => switch (readiness) {
            RemoteCliReady() => '$cliLabel ready on $hostLabel',
            _ => null,
          },
          run: (ctx) async {
            final readiness = await widget.readiness.install(
              target: requirement.target,
              cli: requirement.cli,
              onProgress: (progress) {
                final phaseLabel = switch (progress.phase) {
                  CliInstallPhase.checkingNpm => 'Checking npm',
                  CliInstallPhase.bootstrappingNode => 'Bootstrapping Node',
                  CliInstallPhase.installingCli => 'Installing CLI',
                  CliInstallPhase.locatingExecutable => 'Locating executable',
                  CliInstallPhase.syncingRemoteWorkspace =>
                    'Syncing remote workspace',
                };
                final detail = progress.detail?.trim();
                if (detail != null && detail.isNotEmpty) {
                  ctx.reportPhase(phaseLabel, detail: detail);
                } else {
                  ctx.reportPhase(phaseLabel);
                }
              },
            );
            if (readiness is RemoteCliFailed) {
              throw StateError(readiness.message);
            }
            return readiness;
          },
        ),
      );
      if (!mounted) return;
      setState(() => _readinessByKey[requirement.cacheKey] = result);
      widget.onReadinessChanged?.call();
    } finally {
      if (mounted) {
        setState(() => _installingKey = null);
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
      child: TpCard.outlined(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.remoteCliMachineReadinessTitle,
                style: TpTextStyles.of(context).mdMedium,
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
              if (requirements.any((r) {
                final state = _readinessByKey[r.cacheKey];
                return state is RemoteCliMissing || state is RemoteCliFailed;
              })) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.remoteCliMachineReadinessInstallHint,
                  style: TpTextStyles.of(context).smColored(cs.onSurfaceVariant),
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
        registry.capability<CliExecutableCapability>(requirement.cli)?.supportsInstaller ??
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
                Text(cliLabel, style: TpTextStyles.of(context).md),
                Text(
                  subtitle,
                  style: TpTextStyles.of(context).smColored(color),
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
