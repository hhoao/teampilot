import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/resource_manager_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/resource_manager/resource_memory_format.dart';
import '../../services/resource_manager/resource_tree_merge.dart';
import 'resource_memory_sparkline.dart';

/// Metric column widths shared by header / group / leaf / app rows.
const double kResourceManagerCpuColumnWidth = 48;
const double kResourceManagerMemoryColumnWidth = 72;
const double kResourceManagerTrailingGutterWidth = 28;

/// Two-level Resource Manager tree: worktree groups → terminal leaves.
class ResourceManagerTree extends StatelessWidget {
  const ResourceManagerTree({
    required this.tree,
    this.onActivateLeaf,
    this.includeColumnHeader = true,
    super.key,
  });

  final ResourceTreeViewModel tree;
  final void Function(ResourceTreeLeafVm leaf)? onActivateLeaf;

  /// When false, the panel owns a sticky [ResourceManagerColumnHeader] above
  /// the scroll viewport (Orca parity).
  final bool includeColumnHeader;

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
        if (includeColumnHeader) const ResourceManagerColumnHeader(),
        for (final group in tree.groups)
          _GroupSection(
            group: group,
            onActivateLeaf: onActivateLeaf,
          ),
      ],
    );
  }
}

/// Sticky Name | CPU | Memory header row for the Resource Manager body.
class ResourceManagerColumnHeader extends StatelessWidget {
  const ResourceManagerColumnHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;

    return Padding(
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
            width: kResourceManagerCpuColumnWidth,
            child: Text(
              l10n.resourceManagerColumnCpu,
              textAlign: TextAlign.right,
              softWrap: false,
              maxLines: 1,
              style: styles.xs.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: kResourceManagerMemoryColumnWidth,
            child: Text(
              l10n.resourceManagerColumnMemory,
              textAlign: TextAlign.right,
              softWrap: false,
              maxLines: 1,
              style: styles.xs.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: kResourceManagerTrailingGutterWidth),
        ],
      ),
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
        _ResourceManagerHoverRow(
          onTap: () => setState(() => _expanded = !_expanded),
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
              _MetricText(
                formatResourceCpu(group.aggregateCpu),
                width: kResourceManagerCpuColumnWidth,
              ),
              _MetricText(
                formatResourceMemory(group.aggregateMemoryBytes),
                width: kResourceManagerMemoryColumnWidth,
              ),
              const SizedBox(width: kResourceManagerTrailingGutterWidth),
            ],
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

    return _ResourceManagerHoverRow(
      onTap: onActivate == null ? null : () => onActivate!(leaf),
      padding: const EdgeInsets.fromLTRB(28, 3, 8, 3),
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
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
            _MetricText(
              leaf.cpuDisplay,
              width: kResourceManagerCpuColumnWidth,
            ),
            _MetricText(
              leaf.memoryDisplay,
              width: kResourceManagerMemoryColumnWidth,
            ),
            SizedBox(
              width: kResourceManagerTrailingGutterWidth,
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
    );
  }
}

/// Right-aligned metric cell that never wraps (e.g. `295.5 MB` stays one line).
class _MetricText extends StatelessWidget {
  const _MetricText(this.text, {required this.width});

  final String text;
  final double width;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: Text(
        text,
        textAlign: TextAlign.right,
        softWrap: false,
        maxLines: 1,
        overflow: TextOverflow.visible,
        style: styles.xs.copyWith(
          color: cs.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Orca-like row hover: muted surface highlight under the pointer.
class _ResourceManagerHoverRow extends StatefulWidget {
  const _ResourceManagerHoverRow({
    required this.child,
    required this.padding,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  State<_ResourceManagerHoverRow> createState() =>
      _ResourceManagerHoverRowState();
}

class _ResourceManagerHoverRowState extends State<_ResourceManagerHoverRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      opaque: true,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: Material(
        color: _hovered
            ? cs.onSurface.withValues(alpha: 0.06)
            : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          mouseCursor: widget.onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          hoverColor: Colors.transparent,
          splashColor: cs.onSurface.withValues(alpha: 0.06),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
  }
}
