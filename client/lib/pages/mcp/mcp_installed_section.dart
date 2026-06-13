import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/mcp_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_server.dart';
import '../../services/mcp/mcp_credentials_store.dart';
import '../../services/mcp/mcp_oauth_flow.dart';
import '../../widgets/settings/workspace_settings_widgets.dart';
import 'mcp_oauth_connect_dialog.dart';
import 'mcp_shared_widgets.dart';

class McpInstalledSection extends StatefulWidget {
  const McpInstalledSection({
    required this.state,
    required this.onImport,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onGoDiscovery,
    required this.onOAuthConnected,
    super.key,
  });

  final McpState state;
  final VoidCallback onImport;
  final VoidCallback onAdd;
  final void Function(McpServer server) onEdit;
  final void Function(McpServer server) onDelete;
  final VoidCallback onGoDiscovery;
  final VoidCallback onOAuthConnected;

  @override
  State<McpInstalledSection> createState() => _McpInstalledSectionState();
}

class _McpInstalledSectionState extends State<McpInstalledSection> {
  final _credentials = McpCredentialsStore();
  Map<String, bool>? _oauthStatus;
  int _oauthStatusEpoch = 0;

  @override
  void initState() {
    super.initState();
    _reloadOAuthStatus();
  }

  @override
  void didUpdateWidget(covariant McpInstalledSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.servers != widget.state.servers) {
      _reloadOAuthStatus();
    }
  }

  Future<void> _reloadOAuthStatus() async {
    final epoch = ++_oauthStatusEpoch;
    final servers = widget.state.servers;
    final configDir = McpOAuthFlow.claudeAppConfigDir();
    final data = await _credentials.read(configDir);
    final next = <String, bool>{};
    for (final server in servers) {
      if (!mcpServerShowsOAuthConnect(server)) continue;
      next[server.id] = _credentials.hasAccessToken(
        data,
        server.configKey,
        server.server,
      );
    }
    if (!mounted || epoch != _oauthStatusEpoch) return;
    setState(() => _oauthStatus = next);
  }

  Future<void> _connectOAuth(McpServer server) async {
    final ok = await showMcpOAuthConnectDialog(
      context: context,
      server: server,
      configDir: McpOAuthFlow.claudeAppConfigDir(),
    );
    if (!mounted || ok != true) return;
    await _reloadOAuthStatus();
    if (!mounted) return;
    widget.onOAuthConnected();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.mcpOAuthConnectSuccess)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = widget.state;
    final cubit = context.read<McpCubit>();
    final servers = state.servers;
    final toolbarBusy = state.busyIds.isNotEmpty;
    final loading = state.status == McpLoadStatus.loading && servers.isEmpty;

    return McpWorkspaceCard(
      child: Column(
        children: [
          McpCardHeader(
            title: l10n.mcpInstalledCount(servers.length),
            trailing: CardHeaderActionRow(
              children: [
                OutlinedButton.icon(
                  onPressed: toolbarBusy ? null : widget.onImport,
                  icon: Icon(
                    Icons.download_outlined,
                    size: context.appIconSizes.md,
                  ),
                  label: Text(l10n.mcpImportExisting),
                ),
                OutlinedButton.icon(
                  onPressed: toolbarBusy ? null : widget.onAdd,
                  icon: Icon(Icons.add, size: context.appIconSizes.md),
                  label: Text(l10n.mcpAddButton),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (state.status == McpLoadStatus.error)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                state.errorMessage ?? 'Error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            )
          else if (servers.isEmpty)
            McpEmptyBlock(
              icon: Icons.dns_outlined,
              title: l10n.mcpNoInstalled,
              hint: l10n.mcpNoInstalledHint,
              actionLabel: l10n.mcpEmptyGoDiscovery,
              onAction: widget.onGoDiscovery,
            )
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: servers.length,
                itemBuilder: (context, index) {
                  final server = servers[index];
                  return McpInstalledServerRow(
                    server: server,
                    busy: state.busyIds.contains(server.id),
                    onEdit: () => widget.onEdit(server),
                    onDelete: () => widget.onDelete(server),
                    onToggleEnabled: (enabled) =>
                        cubit.toggleEnabled(server, enabled),
                    oauthAuthenticated: mcpServerShowsOAuthConnect(server)
                        ? (_oauthStatus == null
                              ? null
                              : (_oauthStatus![server.id] ?? false))
                        : null,
                    onOAuthConnect: mcpServerShowsOAuthConnect(server)
                        ? () => _connectOAuth(server)
                        : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
