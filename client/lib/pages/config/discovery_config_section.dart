import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/discovery_settings_cubit.dart';
import '../../l10n/l10n_extensions.dart';

/// Global "Discovery & Marketplaces" settings: auto-refresh policy for the
/// skills / plugins / MCP discovery pages.
class DiscoveryConfigWorkspace extends StatelessWidget {
  const DiscoveryConfigWorkspace({this.showHeading = true, super.key});

  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<DiscoverySettingsCubit, DiscoverySettingsState>(
      builder: (context, state) {
        return SingleChildScrollView(
          child: TpCard.outlined(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showHeading) ...[
                  TpSectionHeader(title: l10n.discoverySettingsTitle),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: Text(
                      l10n.discoverySettingsSubtitle,
                      style: TpTextStyles.of(context).smMediumColored(
                        Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                _DiscoveryAutoRefreshRow(
                  enabled: state.autoRefreshEnabled,
                  onChanged: (value) => context
                      .read<DiscoverySettingsCubit>()
                      .setAutoRefreshEnabled(value),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DiscoveryAutoRefreshRow extends StatelessWidget {
  const _DiscoveryAutoRefreshRow({
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.storefront_outlined,
            size: 22,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.discoveryAutoRefreshTitle,
                  style: styles.lgColored(cs.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.discoveryAutoRefreshSubtitle,
                  style: styles.smColored(cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(value: enabled, onChanged: onChanged),
        ],
      ),
    );
  }
}
