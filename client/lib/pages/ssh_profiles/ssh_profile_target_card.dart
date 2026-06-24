import 'package:flutter/material.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/ssh_profile.dart';
import '../../theme/workspace_surface_layers.dart';
import 'ssh_profile_connection_status.dart';

class SshProfileTargetCard extends StatelessWidget {
  const SshProfileTargetCard({
    super.key,
    required this.profile,
    required this.status,
    this.statusError,
    required this.testing,
    required this.busy,
    required this.onTest,
    required this.onConnect,
    required this.onDisconnect,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
    this.footer,
  });

  final SshProfile profile;
  final SshProfileConnectionStatus status;
  final String? statusError;
  final bool testing;
  final bool busy;
  final VoidCallback onTest;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;
  final Widget? footer;

  Color _statusColor(ColorScheme cs) => switch (status) {
    SshProfileConnectionStatus.connected => const Color(0xFF10B981),
    SshProfileConnectionStatus.connecting => Colors.amber.shade500,
    SshProfileConnectionStatus.error => cs.error,
    SshProfileConnectionStatus.disconnected => cs.onSurfaceVariant.withValues(
      alpha: 0.45,
    ),
  };

  String _statusLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (status) {
      SshProfileConnectionStatus.disconnected => l10n.sshProfileStatusDisconnected,
      SshProfileConnectionStatus.connecting => l10n.sshProfileStatusConnecting,
      SshProfileConnectionStatus.connected => l10n.sshProfileStatusConnected,
      SshProfileConnectionStatus.error => l10n.sshProfileStatusError,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final connected = status == SshProfileConnectionStatus.connected;
    final connecting = status == SshProfileConnectionStatus.connecting;

    return Container(
      decoration: workspaceCardDecoration(cs, radius: 12, borderAlpha: 0.5),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.dns_outlined, size: 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.name,
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _statusColor(cs),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _statusLabel(context),
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.hostIdentifier,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (statusError != null && statusError!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        statusError!,
                        style: tt.bodySmall?.copyWith(color: cs.error),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _IconAction(
                tooltip: l10n.sshProfileRefresh,
                icon: Icons.refresh,
                onPressed: busy ? null : onRefresh,
              ),
              _IconAction(
                tooltip: l10n.sshProfileEdit,
                icon: Icons.edit_outlined,
                onPressed: busy ? null : onEdit,
              ),
              _IconAction(
                tooltip: l10n.sshProfileDelete,
                icon: Icons.delete_outline,
                onPressed: busy ? null : onDelete,
                destructive: true,
              ),
              if (connected) ...[
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: busy ? null : onDisconnect,
                  icon: const Icon(Icons.link_off, size: 16),
                  label: Text(l10n.sshProfileDisconnect),
                ),
              ] else if (connecting) ...[
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: null,
                  icon: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                  label: Text(l10n.sshProfileStatusConnecting),
                ),
              ] else ...[
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: (busy || testing) ? null : onTest,
                  icon: testing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.primary,
                          ),
                        )
                      : const Icon(Icons.phonelink_outlined, size: 16),
                  label: Text(l10n.sshProfileTest),
                ),
                const SizedBox(width: 6),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onConnect,
                  icon: const Icon(Icons.terminal, size: 16),
                  label: Text(l10n.sshProfileConnect),
                ),
              ],
            ],
          ),
          if (footer != null) ...[const SizedBox(height: 8), footer!],
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(
        icon,
        size: 20,
        color: destructive ? cs.error : cs.onSurfaceVariant,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
