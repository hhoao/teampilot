import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/mcp_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../models/mcp_probe_snapshot.dart';
import '../../models/mcp_server.dart';

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
    final l10n = context.l10n;
    return TpDialog(
      maxWidth: 480,
      maxHeight: 480,
      child: TpDialogPinnedLayout(
        header: TpDialogHeader(title: l10n.mcpToolsDialogTitle(server.name)),
        body: BlocBuilder<McpCubit, McpState>(
          bloc: cubit,
          builder: (context, state) {
            return _McpToolsDialogBody(probe: state.probes[server.id]);
          },
        ),
        footer: TpDialogActions(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            TextButton(
              key: const Key('mcp-tools-reload'),
              onPressed: () => cubit.probeOne(server.id),
              child: Text(l10n.mcpToolsReload),
            ),
          ],
        ),
      ),
    );
  }
}

class _McpToolsDialogBody extends StatelessWidget {
  const _McpToolsDialogBody({required this.probe});

  final McpProbeSnapshot? probe;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final status = probe?.status ?? McpProbeStatus.checking;
    switch (status) {
      case McpProbeStatus.checking:
        return const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case McpProbeStatus.online:
        final tools = probe?.tools ?? const [];
        if (tools.isEmpty) {
          return Text(l10n.mcpToolsEmpty, style: styles.sm);
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tools.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final tool = tools[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tool.name, style: styles.mdSemibold),
                if (tool.description.isNotEmpty)
                  Text(tool.description, style: styles.mutedSm),
              ],
            );
          },
        );
      case McpProbeStatus.offline:
        return Text(l10n.mcpProbeOfflineHint, style: styles.sm);
      case McpProbeStatus.needsAuth:
        return Text(l10n.mcpProbeNeedsAuth, style: styles.sm);
    }
  }
}
