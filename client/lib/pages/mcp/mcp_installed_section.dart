import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/mcp_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_server.dart';
import '../../services/mcp/mcp_credentials_store.dart';
import '../../services/mcp/mcp_oauth_flow.dart';
import '../../theme/workspace_surface_layers.dart';
import 'mcp_oauth_connect_dialog.dart';
import 'mcp_shared_widgets.dart';

class McpInstalledSection extends StatefulWidget {
  const McpInstalledSection({
    required this.onImport,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onGoDiscovery,
    required this.onOAuthConnected,
    super.key,
  });

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

  Future<void> _reloadOAuthStatus() async {
    final epoch = ++_oauthStatusEpoch;
    final cubit = context.read<McpCubit>();
    final servers = cubit.state.servers.where((s) => s.enabled).toList();
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
    final messenger = ScaffoldMessenger.of(context);
    final message = context.l10n.mcpOAuthConnectSuccess;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<McpCubit>().state;
    final cs = Theme.of(context).colorScheme;
    final enabled = state.servers.where((s) => s.enabled).toList();

    if (state.status == McpLoadStatus.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.status == McpLoadStatus.error) {
      return Center(child: Text(state.errorMessage ?? 'Error'));
    }

    if (_oauthStatus == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return BlocListener<McpCubit, McpState>(
      listenWhen: (a, b) =>
          a.status != b.status ||
          a.servers.length != b.servers.length ||
          a.servers != b.servers,
      listener: (_, _) => _reloadOAuthStatus(),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        McpWorkspaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              McpCardHeader(
                title: l10n.mcpInstalledSectionTitle,
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: widget.onImport,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text(l10n.mcpImportExisting),
                    ),
                    FilledButton.icon(
                      onPressed: widget.onAdd,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.mcpAddButton),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: workspaceInsetDecoration(cs, radius: 8),
                child: Text(
                  l10n.mcpConfiguredCount(enabled.length),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: enabled.isEmpty
              ? McpWorkspaceCard(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(l10n.mcpEmpty),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: widget.onGoDiscovery,
                        child: Text(l10n.mcpEmptyGoDiscovery),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: enabled.length,
                  itemBuilder: (context, index) {
                    final server = enabled[index];
                    final showOAuth = mcpServerShowsOAuthConnect(server);
                    return McpInstalledServerCard(
                      server: server,
                      busy: state.busyIds.contains(server.id),
                      onEdit: () => widget.onEdit(server),
                      onDelete: () => widget.onDelete(server),
                      oauthAuthenticated: showOAuth
                          ? (_oauthStatus![server.id] ?? false)
                          : null,
                      onOAuthConnect: showOAuth
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
