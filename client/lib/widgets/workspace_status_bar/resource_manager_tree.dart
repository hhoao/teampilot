import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/resource_manager_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/resource_manager/resource_memory_format.dart';
import '../../services/resource_manager/resource_tree_merge.dart';
import 'resource_memory_sparkline.dart';

/// Two-level Resource Manager tree: worktree groups → terminal leaves.
class ResourceManagerTree extends StatelessWidget {
  const ResourceManagerTree({
    required this.tree,
    this.onActivateLeaf,
    super.key,
  });

  final ResourceTreeViewModel tree;
  final void Function(ResourceTreeLeafVm leaf)? onActivateLeaf;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;

    if (tree.groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Text(
          l10n.resourceManagerEmptyTree,
          style: styles.xs.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.resourceManagerColumnName,
                  style: styles.xs.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  l10n.resourceManagerColumnCpu,
                  textAlign: TextAlign.right,
                  style: styles.xs.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  l10n.resourceManagerColumnMemory,
                  textAlign: TextAlign.right,
                  style: styles.xs.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 28),
            ],
          ),
        ),
        for (final group in tree.groups)
          _GroupSection(
            group: group,
            onActivateLeaf: onActivateLeaf,
          ),
      ],
    );
  }
}

class _GroupSection extends StatefulWidget {
  const _GroupSection({
    required this.group,
    this.onActivateLeaf,
  });

  final ResourceTreeGroupVm group;
  final void Function(ResourceTreeLeafVm leaf)? onActivateLeaf;

  @override
  State<_GroupSection> createState() => _GroupSectionState();
}

class _GroupSectionState extends State<_GroupSection> {
  var _expanded = true;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final group = widget.group;

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
                  _expanded
                      ? Icons.expand_more
                      : Icons.chevron_right,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    group.groupLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: styles.xs.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (group.memoryHistory.length >= 2) ...[
                  ResourceMemorySparkline(samples: group.memoryHistory),
                  const SizedBox(width: 6),
                ],
                SizedBox(
                  width: 48,
                  child: Text(
                    formatResourceCpu(group.aggregateCpu),
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
                    formatResourceMemory(group.aggregateMemoryBytes),
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
          for (final leaf in group.leaves)
            _LeafRow(
              leaf: leaf,
              onActivate: widget.onActivateLeaf,
            ),
      ],
    );
  }
}

class _LeafRow extends StatelessWidget {
  const _LeafRow({
    required this.leaf,
    this.onActivate,
  });

  final ResourceTreeLeafVm leaf;
  final void Function(ResourceTreeLeafVm leaf)? onActivate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final dimmed = !leaf.connected;

    return InkWell(
      onTap: onActivate == null ? null : () => onActivate!(leaf),
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 3, 8, 3),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: leaf.connected
                      ? const Color(0xFF22C55E)
                      : cs.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  leaf.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: styles.xs,
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  leaf.cpuDisplay,
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
                  leaf.memoryDisplay,
                  textAlign: TextAlign.right,
                  style: styles.xs.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(
                width: 28,
                child: TpIconButton(
                  icon: Icons.close,
                  tooltip: l10n.resourceManagerKill,
                  size: 22,
                  iconSize: 12,
                  compact: true,
                  color: cs.onSurfaceVariant,
                  onTap: () {
                    unawaited(
                      context.read<ResourceManagerCubit>().killLeaf(leaf.key),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
