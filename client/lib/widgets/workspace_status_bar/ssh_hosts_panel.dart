import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/ssh_connection_cubit.dart';
import '../../l10n/l10n_extensions.dart';

/// Open Remote Hosts popover body (header, host rows, Manage).
class SshHostsPanel extends StatelessWidget {
  const SshHostsPanel({this.onManage, super.key});

  /// Jump to SSH profile management (caller closes the popover).
  final VoidCallback? onManage;

  static const double panelWidth = 320;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SshConnectionCubit, SshConnectionState>(
      builder: (context, state) {
        final l10n = context.l10n;
        final styles = TpTextStyles.of(context);
        final cs = Theme.of(context).colorScheme;
        final cubit = context.read<SshConnectionCubit>();
        final connected = state.connectedHosts;
        final inactive = state.inactiveHosts;

        return SizedBox(
          width: panelWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                child: Text(
                  l10n.sshHostsPanelTitle,
                  style: styles.xs.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    height: 1.0,
                  ),
                ),
              ),
              for (final host in connected)
                _HostRow(
                  host: host,
                  onConnect: () => unawaited(cubit.connect(host.profileId)),
                  onDisconnect: () =>
                      unawaited(cubit.disconnect(host.profileId)),
                ),
              for (final host in inactive)
                _HostRow(
                  host: host,
                  onConnect: () => unawaited(cubit.connect(host.profileId)),
                  onDisconnect: () =>
                      unawaited(cubit.disconnect(host.profileId)),
                ),
              const TpActionMenuDivider(),
              _ManageRow(onTap: onManage),
            ],
          ),
        );
      },
    );
  }
}

class _HostRow extends StatelessWidget {
  const _HostRow({
    required this.host,
    required this.onConnect,
    required this.onDisconnect,
  });

  final SshHostConnectionVm host;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  Color _dotColor(ColorScheme cs) => switch (host.status) {
    SshHostUiStatus.connected => const Color(0xFF10B981),
    SshHostUiStatus.connecting ||
    SshHostUiStatus.reconnecting => Colors.amber.shade500,
    SshHostUiStatus.error ||
    SshHostUiStatus.authFailed => cs.error,
    SshHostUiStatus.disconnected =>
      cs.onSurfaceVariant.withValues(alpha: 0.45),
  };

  String _statusLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (host.status) {
      SshHostUiStatus.disconnected => l10n.sshProfileStatusDisconnected,
      SshHostUiStatus.connecting => l10n.sshProfileStatusConnecting,
      SshHostUiStatus.reconnecting => l10n.sshProfileStatusReconnecting,
      SshHostUiStatus.connected => l10n.sshProfileStatusConnected,
      SshHostUiStatus.authFailed => l10n.sshProfileStatusAuthFailed,
      SshHostUiStatus.error => l10n.sshProfileStatusError,
    };
  }

  bool get _reconnectable =>
      host.status == SshHostUiStatus.disconnected ||
      host.status == SshHostUiStatus.error ||
      host.status == SshHostUiStatus.authFailed;

  bool get _busy =>
      host.status == SshHostUiStatus.connecting ||
      host.status == SshHostUiStatus.reconnecting;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final detail = host.errorDetail?.trim();
    final showDetail =
        (host.status == SshHostUiStatus.error ||
            host.status == SshHostUiStatus.authFailed) &&
        detail != null &&
        detail.isNotEmpty;
    final subtitle = showDetail
        ? '${l10n.sshHostsRowKind} · ${_statusLabel(context)} · $detail'
        : '${l10n.sshHostsRowKind} · ${_statusLabel(context)}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _dotColor(cs),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  host.label,
                  style: styles.sm.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: styles.xs.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
          if (!_busy) ...[
            const SizedBox(width: 8),
            if (_reconnectable)
              _ActionChip(label: l10n.sshProfileConnect, onTap: onConnect)
            else if (host.status == SshHostUiStatus.connected)
              _ActionChip(
                label: l10n.sshProfileDisconnect,
                onTap: onDisconnect,
                muted: true,
              ),
          ],
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverFill = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return TpHover(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      hoverColor: hoverFill,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Text(
        label,
        style: styles.xs.copyWith(
          fontWeight: FontWeight.w500,
          color: muted ? cs.onSurfaceVariant : cs.onSurface,
          height: 1.2,
        ),
      ),
    );
  }
}

class _ManageRow extends StatelessWidget {
  const _ManageRow({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverFill = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
      child: TpHover(
        onTap: onTap,
        enabled: onTap != null,
        borderRadius: BorderRadius.circular(6),
        hoverColor: hoverFill,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        height: 34,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.sshHostsManage,
            style: styles.sm.copyWith(color: cs.onSurface, height: 1.2),
          ),
        ),
      ),
    );
  }
}
