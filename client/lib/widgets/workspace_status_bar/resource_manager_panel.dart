import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/resource_manager_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/resource_manager/resource_memory_format.dart';
import '../../services/resource_manager/resource_tree_merge.dart';
import 'resource_manager_tree.dart';
import 'resource_memory_sparkline.dart';

/// Open Resource Manager popover body (header, totals, tree, Space stub).
class ResourceManagerPanel extends StatelessWidget {
  const ResourceManagerPanel({
    this.onNavigateLeaf,
    super.key,
  });

  /// Optional navigate hook (Task 9 wires workbench focus). Always closes panel.
  final void Function(ResourceTreeLeafVm leaf)? onNavigateLeaf;

  static const double panelWidth = 416;
  static const double maxTreeHeight = 280;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ResourceManagerCubit, ResourceManagerState>(
      builder: (context, state) {
        final l10n = context.l10n;
        final styles = TpTextStyles.of(context);
        final cs = Theme.of(context).colorScheme;
        final cubit = context.read<ResourceManagerCubit>();
        final tree = state.tree;
        final snapshot = state.snapshot;

        return SizedBox(
          width: panelWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                hasError: state.error != null,
                onRefresh: () => unawaited(cubit.refresh()),
                onKillAll: () => unawaited(_confirmKillAll(context, cubit)),
              ),
              if (state.error != null)
                Padding(
                  key: const Key('resource-manager-error'),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: cs.error.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n.resourceManagerMetricsError,
                          style: styles.xs.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              _TotalsRow(state: state),
              if (snapshot?.app != null)
                _AppRow(appCpu: snapshot!.app!.cpu, appMemory: snapshot.app!.memoryBytes, history: snapshot.app!.history),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: maxTreeHeight),
                child: SingleChildScrollView(
                  child: ResourceManagerTree(
                    tree: tree ??
                        const ResourceTreeViewModel(
                          terminalCount: 0,
                          groups: [],
                        ),
                    onActivateLeaf: (leaf) {
                      onNavigateLeaf?.call(leaf);
                      cubit.closePanel();
                    },
                  ),
                ),
              ),
              const _SpaceStub(),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.hasError,
    required this.onRefresh,
    required this.onKillAll,
  });

  final bool hasError;
  final VoidCallback onRefresh;
  final VoidCallback onKillAll;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      child: Row(
        children: [
          Icon(Icons.memory, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.resourceManagerPanelTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: styles.xs.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (hasError)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Icon(
                Icons.error_outline,
                size: 14,
                color: cs.error.withValues(alpha: 0.8),
              ),
            ),
          TpIconButton(
            icon: Icons.refresh,
            tooltip: l10n.resourceManagerRefresh,
            size: 26,
            iconSize: 14,
            compact: true,
            color: cs.onSurfaceVariant,
            onTap: onRefresh,
          ),
          TpIconButton(
            icon: Icons.delete_outline,
            tooltip: l10n.resourceManagerKillAll,
            size: 26,
            iconSize: 14,
            compact: true,
            color: cs.onSurfaceVariant,
            onTap: onKillAll,
          ),
        ],
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.state});

  final ResourceManagerState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final snapshot = state.snapshot;
    final totalCpu = state.tree?.totalCpu ?? snapshot?.totalCpu;
    final totalMemory = state.tree?.totalMemory ?? snapshot?.totalMemory;
    final hostPercent = snapshot?.host?.memoryUsagePercent;
    final history = snapshot?.totalMemoryHistory ?? const <int>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 2,
              children: [
                Text(
                  formatResourceCpu(totalCpu),
                  style: styles.xs.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  formatResourceMemory(totalMemory),
                  style: styles.xs.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (hostPercent != null)
                  Text(
                    l10n.resourceManagerSystemMemoryPercent(
                      hostPercent.toStringAsFixed(0),
                    ),
                    style: styles.xs.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (history.isNotEmpty) ResourceMemorySparkline(samples: history),
        ],
      ),
    );
  }
}

class _AppRow extends StatefulWidget {
  const _AppRow({
    required this.appCpu,
    required this.appMemory,
    required this.history,
  });

  final double? appCpu;
  final int? appMemory;
  final List<int> history;

  @override
  State<_AppRow> createState() => _AppRowState();
}

class _AppRowState extends State<_AppRow> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    l10n.resourceManagerAppProcess,
                    style: styles.xs.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (widget.history.length >= 2) ...[
                  ResourceMemorySparkline(samples: widget.history),
                  const SizedBox(width: 6),
                ],
                SizedBox(
                  width: 48,
                  child: Text(
                    formatResourceCpu(widget.appCpu),
                    textAlign: TextAlign.right,
                    style: styles.xs.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    formatResourceMemory(widget.appMemory),
                    textAlign: TextAlign.right,
                    style: styles.xs.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 28),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 12, 6),
            child: Text(
              l10n.resourceManagerAppProcess,
              style: styles.xs.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _SpaceStub extends StatelessWidget {
  const _SpaceStub();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.25),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          children: [
            Icon(Icons.storage_outlined, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.resourceManagerSpace,
                        style: styles.xs.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      TpStatusBadge(
                        label: l10n.resourceManagerSpaceBeta,
                        tone: TpStatusBadgeTone.neutral,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.resourceManagerSpaceNotScanned,
                    style: styles.xs.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmKillAll(
  BuildContext context,
  ResourceManagerCubit cubit,
) async {
  final l10n = context.l10n;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return TpDialog(
        maxWidth: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TpDialogHeader(
              title: l10n.resourceManagerKillAllConfirmTitle,
              onClose: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(height: 12),
            Text(l10n.resourceManagerKillAllConfirmBody),
            TpDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(l10n.resourceManagerKillAll),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
  if (confirmed == true) {
    await cubit.killAll();
  }
}
