import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/mcp_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_probe_snapshot.dart';
import '../../models/mcp_server.dart';
import '../../theme/app_fonts.dart';
import '../../theme/workspace_surface_layers.dart';
import 'mcp_shared_widgets.dart';

Future<void> showMcpToolsDialog(
  BuildContext context, {
  required McpCubit cubit,
  required McpServer server,
}) {
  return showTpDialog<void>(
    context: context,
    builder: (_) => McpToolsDialog(cubit: cubit, server: server),
  );
}

class McpToolsDialog extends StatelessWidget {
  const McpToolsDialog({required this.cubit, required this.server, super.key});

  final McpCubit cubit;
  final McpServer server;

  @override
  Widget build(BuildContext context) {
    return TpDialog(
      maxWidth: 560,
      maxHeight: 640,
      child: BlocBuilder<McpCubit, McpState>(
        bloc: cubit,
        builder: (context, state) {
          final probe = state.probes[server.id];
          final checking =
              (probe?.status ?? McpProbeStatus.checking) ==
              McpProbeStatus.checking;
          return TpDialogPinnedLayout(
            header: TpDialogHeader(title: server.name),
            body: _McpToolsDialogBody(serverId: server.id, probe: probe),
            footer: _McpToolsDialogFooter(
              checking: checking,
              onReload: () => cubit.probeOne(server.id),
            ),
          );
        },
      ),
    );
  }
}

class _McpToolsDialogBody extends StatelessWidget {
  const _McpToolsDialogBody({required this.serverId, required this.probe});

  final String serverId;
  final McpProbeSnapshot? probe;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.tpSpacing;
    final status = probe?.status ?? McpProbeStatus.checking;
    final tools = probe?.tools ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        McpProbeStatusLine(serverId: serverId, probe: probe),
        SizedBox(height: spacing.lg),
        switch (status) {
          McpProbeStatus.checking => const _McpToolsBusy(),
          McpProbeStatus.online =>
            tools.isEmpty
                ? _McpToolsMessage(
                    icon: Icons.handyman_outlined,
                    title: l10n.mcpToolsEmpty,
                  )
                : _McpToolsList(tools: tools),
          McpProbeStatus.offline => _McpToolsMessage(
            icon: Icons.cloud_off_outlined,
            title: l10n.mcpProbeOffline,
            hint: l10n.mcpProbeOfflineHint,
          ),
          McpProbeStatus.needsAuth => _McpToolsMessage(
            icon: Icons.lock_outline,
            title: l10n.mcpProbeNeedsAuth,
          ),
        },
      ],
    );
  }
}

class _McpToolsBusy extends StatelessWidget {
  const _McpToolsBusy();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 200),
      child: Center(child: TpIndeterminateSpinner(size: 24)),
    );
  }
}

class _McpToolsMessage extends StatelessWidget {
  const _McpToolsMessage({required this.icon, required this.title, this.hint});

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 200),
      child: TpEmptyState(icon: icon, title: title, hint: hint, centered: true),
    );
  }
}

class _McpToolsList extends StatelessWidget {
  const _McpToolsList({required this.tools});

  final List<McpProbeTool> tools;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TpSectionHeader(
          title: l10n.mcpToolsSection,
          padding: EdgeInsets.only(bottom: context.tpSpacing.sm),
        ),
        Container(
          decoration: workspaceInsetDecoration(cs, radius: 10),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < tools.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.45),
                  ),
                _McpToolRow(tool: tools[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _McpToolRow extends StatelessWidget {
  const _McpToolRow({required this.tool});

  final McpProbeTool tool;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.handyman_outlined,
              size: context.tpIconSizes.sm,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tool.name,
                  style: appMonoTextStyle(
                    context,
                    base: styles.smSemibold,
                    color: cs.onSurface,
                  ),
                ),
                if (tool.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    tool.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: styles.mutedSm,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _McpToolsDialogFooter extends StatelessWidget {
  const _McpToolsDialogFooter({required this.checking, required this.onReload});

  final bool checking;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final spacing = context.tpSpacing;
    final iconSize = context.tpIconSizes.sm;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: spacing.lg),
        const TpDialogDivider(),
        Padding(
          padding: EdgeInsets.only(top: spacing.lg),
          child: Row(
            children: [
              OutlinedButton.icon(
                key: const Key('mcp-tools-reload'),
                onPressed: checking ? null : onReload,
                icon: checking
                    ? TpIndeterminateSpinner(size: iconSize)
                    : Icon(Icons.refresh, size: iconSize),
                label: Text(l10n.mcpToolsReload),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.mcpToolsDone),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
