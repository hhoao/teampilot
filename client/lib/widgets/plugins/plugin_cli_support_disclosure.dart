import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/plugin.dart';
import '../../services/cli/registry/capabilities/display_capability.dart';
import '../../services/cli/registry/capabilities/plugin_provisioner_capability.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/plugin/plugin_cli_support.dart';
import '../../theme/app_text_styles.dart';

class PluginCliSupportDisclosure extends StatelessWidget {
  const PluginCliSupportDisclosure({
    super.key,
    required this.capabilities,
    this.registry,
  });

  final PluginCapabilities capabilities;
  final CliToolRegistry? registry;

  @override
  Widget build(BuildContext context) {
    if (!pluginCapabilitiesDisclosable(capabilities)) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final reg = registry ?? CliToolRegistry.builtIn();
    final statuses = analyzePluginCliSupportForLaunchClis(
      capabilities,
      registry: reg,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final status in statuses)
            _SupportChip(
              label: _statusLabel(l10n, reg, status),
              level: status.level,
              muted: muted,
            ),
        ],
      ),
    );
  }

  String _statusLabel(
    AppLocalizations l10n,
    CliToolRegistry registry,
    PluginCliSupportStatus status,
  ) {
    final cliLabel =
        registry.capability<DisplayCapability>(status.tool)?.label(l10n) ??
        status.tool.name;
    return switch (status.level) {
      PluginCliSupportLevel.fullySupported =>
        l10n.pluginCliSupportFully(cliLabel),
      PluginCliSupportLevel.partiallySupported => l10n.pluginCliSupportPartial(
        cliLabel,
        _droppedLabels(l10n, status.dropped),
      ),
      PluginCliSupportLevel.notApplicable =>
        l10n.pluginCliSupportNotApplicable(cliLabel),
    };
  }

  String _droppedLabels(
    AppLocalizations l10n,
    Set<PluginComponentKind> dropped,
  ) {
    final labels = dropped.map((k) => _componentLabel(l10n, k)).toList()
      ..sort();
    return labels.join(', ');
  }

  String _componentLabel(AppLocalizations l10n, PluginComponentKind kind) =>
      switch (kind) {
        PluginComponentKind.skills => l10n.pluginComponentSkills,
        PluginComponentKind.agents => l10n.pluginComponentAgents,
        PluginComponentKind.commands => l10n.pluginComponentCommands,
        PluginComponentKind.hooks => l10n.pluginComponentHooks,
        PluginComponentKind.mcp => l10n.pluginComponentMcp,
        PluginComponentKind.rules => l10n.pluginComponentRules,
        PluginComponentKind.apps => l10n.pluginComponentApps,
      };
}

class _SupportChip extends StatelessWidget {
  const _SupportChip({
    required this.label,
    required this.level,
    required this.muted,
  });

  final String label;
  final PluginCliSupportLevel level;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (level) {
      PluginCliSupportLevel.fullySupported => (
        const Color(0xFFDCFCE7),
        const Color(0xFF166534),
      ),
      PluginCliSupportLevel.partiallySupported => (
        const Color(0xFFFEF9C3),
        const Color(0xFF854D0E),
      ),
      PluginCliSupportLevel.notApplicable => (
        const Color(0xFFF3F4F6),
        muted,
      ),
    };
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? fg.withValues(alpha: 0.18)
        : bg;
    final foreground = isDark ? fg.withValues(alpha: 0.95) : fg;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTextStyles.of(context).caption.copyWith(
          color: foreground,
          fontSize: 11,
        ),
      ),
    );
  }
}
