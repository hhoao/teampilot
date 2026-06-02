import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../cubits/mcp_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_server.dart';
import '../../services/app/platform_utils.dart';
import '../../utils/app_keys.dart';
import '../../widgets/settings/workspace_section_host.dart';
import 'mcp_form_page.dart';
import 'mcp_management_page.dart';
import 'mcp_routes.dart';
import 'mcp_shared_widgets.dart';

/// MCP add/edit as an internal workspace route (not split beside the list).
class McpFormNavPage extends StatelessWidget {
  const McpFormNavPage({this.serverId, super.key});

  /// When set, loads the server from [McpCubit] for edit mode.
  final String? serverId;

  bool get _isAdd => serverId == null;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<McpCubit, McpState>(
      listenWhen: (a, b) =>
          a.errorMessage != b.errorMessage && b.errorMessage != null,
      listener: (context, state) {
        if (!context.mounted || state.errorMessage == null) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(state.errorMessage!)),
        );
        context.read<McpCubit>().clearError();
      },
      builder: (context, state) {
        final existing = _resolveExisting(state);
        final form = _buildForm(context, existing);

        return WorkspaceAdaptiveSectionPage(
          pageKey: AppKeys.mcpFormDetail,
          title: context.l10n.mcpNavTitle,
          subtitle: context.l10n.mcpSubtitle,
          bodyAnimationKey: ValueKey(serverId ?? 'mcp-add'),
          nav: WorkspaceEnumNavPanel<McpSection>(
            sections: McpSection.values,
            current: McpSection.installed,
            basePath: '/mcp',
            descriptor: (s) => s,
            onSelect: (target) => _goSection(context, target),
          ),
          body: form,
        );
      },
    );
  }

  McpServer? _resolveExisting(McpState state) {
    if (_isAdd) return null;
    final id = serverId!.trim();
    for (final server in state.servers) {
      if (server.id == id) return server;
    }
    return null;
  }

  Widget _buildForm(BuildContext context, McpServer? existing) {
    if (!_isAdd && existing == null) {
      return Center(child: Text(context.l10n.mcpServerNotFound));
    }

    return McpWorkspaceCard(
      child: McpFormPage(
        key: ValueKey(existing?.id ?? 'mcp-add'),
        existing: existing,
        onCancel: () => _returnToInstalled(context),
        onSaved: (_) async {
          await context.read<McpCubit>().loadAll();
          if (context.mounted) _returnToInstalled(context);
        },
      ),
    );
  }

  void _returnToInstalled(BuildContext context) {
    if (useAndroidHubNavigation(context)) {
      if (context.canPop()) {
        context.pop();
        return;
      }
    }
    context.go(mcpInstalledRoute);
  }

  void _goSection(BuildContext context, McpSection target) {
    navigateMcpSection(context, target);
  }
}
