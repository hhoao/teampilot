import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/mcp_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_server.dart';
import '../../theme/workspace_surface_layers.dart';
import 'mcp_shared_widgets.dart';

class McpInstalledSection extends StatelessWidget {
  const McpInstalledSection({
    required this.onImport,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onGoDiscovery,
    super.key,
  });

  final VoidCallback onImport;
  final VoidCallback onAdd;
  final void Function(McpServer server) onEdit;
  final void Function(McpServer server) onDelete;
  final VoidCallback onGoDiscovery;

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

    return Column(
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
                      onPressed: onImport,
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: Text(l10n.mcpImportExisting),
                    ),
                    FilledButton.icon(
                      onPressed: onAdd,
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
                        onPressed: onGoDiscovery,
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
                    return McpInstalledServerCard(
                      server: server,
                      busy: state.busyIds.contains(server.id),
                      onEdit: () => onEdit(server),
                      onDelete: () => onDelete(server),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
