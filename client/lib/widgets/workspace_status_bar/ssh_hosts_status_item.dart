import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/ssh_connection_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import 'ssh_hosts_panel.dart';
import 'workspace_status_bar.dart';

/// Closed status-bar pill + Remote Hosts popover (`ssh-hosts`).
class SshHostsStatusItem implements WorkspaceStatusBarItem {
  SshHostsStatusItem({
    this.onManage,
    this.onOpenTerminal,
    this.homeSshProfileId,
  });

  /// Navigate to SSH profile management (Task 6 wires GoRouter).
  final VoidCallback? onManage;

  /// Open a floating terminal for the given SSH profile id.
  final ValueChanged<String>? onOpenTerminal;

  /// Resolves the current home's SSH profile id. The status bar hides this
  /// host: the home storage-pool connection is kept in `SshConnectionCubit`
  /// for boot/banner reconnect, but must not appear among workload hosts.
  final String? Function()? homeSshProfileId;

  @override
  String get id => 'ssh-hosts';

  @override
  Widget buildSegment(BuildContext context, {required bool compact}) {
    return _SshHostsStatusSegment(
      compact: compact,
      onManage: onManage,
      onOpenTerminal: onOpenTerminal,
      homeSshProfileId: homeSshProfileId,
    );
  }
}

class _SshHostsStatusSegment extends StatefulWidget {
  const _SshHostsStatusSegment({
    required this.compact,
    this.onManage,
    this.onOpenTerminal,
    this.homeSshProfileId,
  });

  final bool compact;
  final VoidCallback? onManage;
  final ValueChanged<String>? onOpenTerminal;
  final String? Function()? homeSshProfileId;

  @override
  State<_SshHostsStatusSegment> createState() => _SshHostsStatusSegmentState();
}

class _SshHostsStatusSegmentState extends State<_SshHostsStatusSegment> {
  final _popover = TpPopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SshConnectionCubit, SshConnectionState>(
      buildWhen: (previous, next) {
        // Resolve the home id fresh on every comparison: a home switch can
        // change which host is hidden even between the same cubit states.
        final homeId = widget.homeSshProfileId?.call();
        final prev = previous.excluding(homeId);
        final curr = next.excluding(homeId);
        return prev.connectedCount != curr.connectedCount ||
            prev.overallStatus != curr.overallStatus ||
            prev.isEmpty != curr.isEmpty;
      },
      builder: (context, state) {
        final visible = state.excluding(widget.homeSshProfileId?.call());
        if (visible.isEmpty) return const SizedBox.shrink();

        final l10n = context.l10n;
        final connecting =
            visible.overallStatus == SshHostsOverallStatus.connecting;
        final label = connecting
            ? l10n.ssh.hostsPillConnecting
            : l10n.ssh.hostsPillCount(count: visible.connectedCount);

        return TpActionMenuAnchor(
          controller: _popover,
          fixedPanelWidth: SshHostsPanel.panelWidth,
          closeOnTapOutside: true,
          anchor: const TpAnchor(
            // Open above the pill: attach panel bottom to pill top, 8px gap
            // (Orca PopoverContent side="top" sideOffset={8}).
            childAlignment: Alignment.bottomRight,
            overlayAlignment: Alignment.topRight,
            offset: Offset(0, -8),
          ),
          popoverBuilder: (context, menu) => SshHostsPanel(
            homeSshProfileId: widget.homeSshProfileId,
            onManage: () {
              menu.close();
              widget.onManage?.call();
            },
            onOpenTerminal: widget.onOpenTerminal == null
                ? null
                : (profileId) {
                    menu.close();
                    widget.onOpenTerminal?.call(profileId);
                  },
          ),
          child: Tooltip(
            message: l10n.ssh.hostsPanelTitle,
            child: _PillButton(
              key: const Key('ssh-hosts-pill'),
              compact: widget.compact,
              label: label,
              overallStatus: visible.overallStatus,
              onTap: _popover.toggle,
            ),
          ),
        );
      },
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    super.key,
    required this.compact,
    required this.label,
    required this.overallStatus,
    required this.onTap,
  });

  final bool compact;
  final String label;
  final SshHostsOverallStatus overallStatus;
  final VoidCallback onTap;

  Color _dotColor(ColorScheme cs) {
    switch (overallStatus) {
      case SshHostsOverallStatus.connected:
      case SshHostsOverallStatus.partial:
        return const Color(0xFF10B981);
      case SshHostsOverallStatus.connecting:
        return Colors.amber.shade500;
      case SshHostsOverallStatus.disconnected:
        return cs.onSurfaceVariant.withValues(alpha: 0.4);
    }
  }

  Widget _leadingIcon(ColorScheme cs) {
    final connecting = overallStatus == SshHostsOverallStatus.connecting;
    if (connecting) {
      return SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: Colors.amber.shade500,
        ),
      );
    }

    final allDisconnected = overallStatus == SshHostsOverallStatus.disconnected;
    final icon = allDisconnected
        ? Icons.cloud_off_outlined
        : Icons.dns_outlined;
    final color = overallStatus == SshHostsOverallStatus.connected
        ? const Color(0xFF10B981)
        : cs.onSurfaceVariant;
    return Icon(icon, size: 13, color: color);
  }

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final compact = this.compact;
    final muted = cs.onSurfaceVariant;

    return TpHover(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      hoverColor: cs.onSurface.withValues(alpha: 0.07),
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _leadingIcon(cs),
          if (!compact) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: styles.xs.copyWith(
                color: muted,
                height: 1.0,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          const SizedBox(width: 6),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _dotColor(cs),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
