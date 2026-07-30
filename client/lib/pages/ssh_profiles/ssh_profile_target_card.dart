import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/ssh_profile.dart';
import '../../theme/workspace_surface_layers.dart';
import 'ssh_profile_connection_status.dart';

enum _SshProfileTargetAction {
  refresh,
  edit,
  configure,
  delete,
  test,
  connect,
  disconnect,
}

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
    this.onConfigure,
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
  final VoidCallback? onConfigure;

  static const _leadingWidth = 32.0;
  static const _actionsGap = 8.0;
  static const _infoMinWidth = 96.0;
  static const _compactIconActionWidth = 40.0;
  static const _disconnectButtonWidth = 120.0;
  static const _connectingButtonWidth = 150.0;
  static const _testConnectButtonsWidth = 196.0;

  Color _statusColor(ColorScheme cs) => switch (status) {
    SshProfileConnectionStatus.connected => const Color(0xFF10B981),
    SshProfileConnectionStatus.connecting ||
    SshProfileConnectionStatus.reconnecting => Colors.amber.shade500,
    SshProfileConnectionStatus.error ||
    SshProfileConnectionStatus.authFailed => cs.error,
    SshProfileConnectionStatus.disconnected => cs.onSurfaceVariant.withValues(
      alpha: 0.45,
    ),
  };

  String _statusLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (status) {
      SshProfileConnectionStatus.disconnected =>
        l10n.sshProfileStatusDisconnected,
      SshProfileConnectionStatus.connecting => l10n.sshProfileStatusConnecting,
      SshProfileConnectionStatus.reconnecting =>
        l10n.sshProfileStatusReconnecting,
      SshProfileConnectionStatus.connected => l10n.sshProfileStatusConnected,
      SshProfileConnectionStatus.authFailed => l10n.sshProfileStatusAuthFailed,
      SshProfileConnectionStatus.error => l10n.sshProfileStatusError,
    };
  }

  bool get _connected => status == SshProfileConnectionStatus.connected;

  bool get _connecting =>
      status == SshProfileConnectionStatus.connecting ||
      status == SshProfileConnectionStatus.reconnecting;

  double _inlineActionsMinWidth() {
    final iconCount = onConfigure != null ? 5 : 4;
    var width = iconCount * _compactIconActionWidth;
    if (_connected) {
      width += 4 + _disconnectButtonWidth;
    } else if (_connecting) {
      width += 4 + _connectingButtonWidth;
    } else {
      width += 4 + _testConnectButtonsWidth;
    }
    return width;
  }

  bool _showInlineActions(double maxWidth) {
    return maxWidth >=
        _leadingWidth +
            _actionsGap +
            _infoMinWidth +
            _actionsGap +
            _inlineActionsMinWidth();
  }

  void _handleAction(_SshProfileTargetAction action) {
    switch (action) {
      case _SshProfileTargetAction.refresh:
        onRefresh();
      case _SshProfileTargetAction.edit:
        onEdit();
      case _SshProfileTargetAction.configure:
        onConfigure?.call();
      case _SshProfileTargetAction.delete:
        onDelete();
      case _SshProfileTargetAction.test:
        onTest();
      case _SshProfileTargetAction.connect:
        onConnect();
      case _SshProfileTargetAction.disconnect:
        onDisconnect();
    }
  }

  List<TpActionMenuSpec> _overflowMenuSpecs(BuildContext context) {
    final l10n = context.l10n;
    return [
      TpActionMenuSpec.item(
        value: _SshProfileTargetAction.refresh,
        icon: Icons.refresh,
        label: l10n.sshProfileRefresh,
        enabled: !busy,
      ),
      TpActionMenuSpec.item(
        value: _SshProfileTargetAction.edit,
        icon: Icons.edit_outlined,
        label: l10n.sshProfileEdit,
        enabled: !busy,
      ),
      if (onConfigure != null)
        TpActionMenuSpec.item(
          value: _SshProfileTargetAction.configure,
          icon: Icons.tune_outlined,
          label: l10n.configure,
          enabled: !busy,
        ),
      if (_connected)
        TpActionMenuSpec.item(
          value: _SshProfileTargetAction.disconnect,
          icon: Icons.link_off,
          label: l10n.sshProfileDisconnect,
          enabled: !busy,
        )
      else if (_connecting)
        TpActionMenuSpec.item(
          value: _SshProfileTargetAction.connect,
          icon: Icons.sync,
          label: status == SshProfileConnectionStatus.reconnecting
              ? l10n.sshProfileStatusReconnecting
              : l10n.sshProfileStatusConnecting,
          enabled: false,
        )
      else ...[
        TpActionMenuSpec.item(
          value: _SshProfileTargetAction.test,
          icon: Icons.phonelink_outlined,
          label: l10n.sshProfileTest,
          enabled: !busy && !testing,
        ),
        TpActionMenuSpec.item(
          value: _SshProfileTargetAction.connect,
          icon: Icons.terminal,
          label: l10n.sshProfileConnect,
          enabled: !busy,
        ),
      ],
      TpActionMenuSpec.item(
        value: _SshProfileTargetAction.delete,
        icon: Icons.delete_outline,
        label: l10n.sshProfileDelete,
        enabled: !busy,
        destructive: true,
      ),
    ];
  }

  Widget _buildOverflowMenu(BuildContext context) {
    return TpActionMenuButton(
      tooltip: context.l10n.logViewerActionsMenu,
      icon: Icon(Icons.more_vert, size: context.tpIconSizes.sm),
      size: TpIconButton.kCompactSize,
      specs: _overflowMenuSpecs(context),
      onSelected: (value) {
        if (value is _SshProfileTargetAction) {
          _handleAction(value);
        }
      },
    );
  }

  Widget _buildInlineActions(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
        if (onConfigure != null)
          _IconAction(
            tooltip: l10n.configure,
            icon: Icons.tune_outlined,
            onPressed: busy ? null : onConfigure,
          ),
        _IconAction(
          tooltip: l10n.sshProfileDelete,
          icon: Icons.delete_outline,
          onPressed: busy ? null : onDelete,
          destructive: true,
        ),
        if (_connected) ...[
          const SizedBox(width: 4),
          OutlinedButton.icon(
            onPressed: busy ? null : onDisconnect,
            icon: const Icon(Icons.link_off, size: 16),
            label: Text(l10n.sshProfileDisconnect),
          ),
        ] else if (_connecting) ...[
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
            label: Text(
              status == SshProfileConnectionStatus.reconnecting
                  ? l10n.sshProfileStatusReconnecting
                  : l10n.sshProfileStatusConnecting,
            ),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: workspaceCardDecoration(cs, radius: 12, borderAlpha: 0.5),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showInlineActions = _showInlineActions(constraints.maxWidth);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
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
                            style: TpTextStyles.of(context).mdSemiboldTightSnug,
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
                        Flexible(
                          child: Text(
                            _statusLabel(context),
                            style: TpTextStyles.of(context).mutedXs,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      profile.hostIdentifier,
                      style: TpTextStyles.of(context).mutedSm,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (statusError != null && statusError!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        statusError!,
                        style: TpTextStyles.of(context).smColored(cs.error),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (showInlineActions)
                _buildInlineActions(context)
              else
                _buildOverflowMenu(context),
            ],
          );
        },
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
