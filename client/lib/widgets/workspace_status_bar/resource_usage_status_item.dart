import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/resource_manager_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../pages/home_workspace/global_resource_manager_host.dart';
import '../../services/resource_manager/resource_tree_merge.dart';
import 'resource_manager_panel.dart';
import 'workspace_status_bar.dart';

/// Closed status-bar pill + Resource Manager popover (`resource-usage`).
class ResourceUsageStatusItem implements WorkspaceStatusBarItem {
  ResourceUsageStatusItem({this.onNavigateLeaf});

  /// Optional navigate hook. When null, [buildSegment] resolves
  /// [ResourceManagerNavigateScope] from its build context (must be under
  /// [GlobalResourceManagerHost]).
  final void Function(ResourceTreeLeafVm leaf)? onNavigateLeaf;

  @override
  String get id => 'resource-usage';

  @override
  Widget buildSegment(BuildContext context, {required bool compact}) {
    return _ResourceUsageStatusSegment(
      compact: compact,
      onNavigateLeaf:
          onNavigateLeaf ?? ResourceManagerNavigateScope.maybeOf(context),
    );
  }
}

class _ResourceUsageStatusSegment extends StatefulWidget {
  const _ResourceUsageStatusSegment({
    required this.compact,
    this.onNavigateLeaf,
  });

  final bool compact;
  final void Function(ResourceTreeLeafVm leaf)? onNavigateLeaf;

  @override
  State<_ResourceUsageStatusSegment> createState() =>
      _ResourceUsageStatusSegmentState();
}

class _ResourceUsageStatusSegmentState
    extends State<_ResourceUsageStatusSegment> {
  final _popover = TpPopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return BlocListener<ResourceManagerCubit, ResourceManagerState>(
      listenWhen: (previous, next) => previous.isOpen != next.isOpen,
      listener: (context, state) {
        if (state.isOpen) {
          if (!_popover.isOpen) _popover.show();
        } else if (_popover.isOpen) {
          _popover.hide();
        }
      },
      child: BlocBuilder<ResourceManagerCubit, ResourceManagerState>(
        buildWhen: (previous, next) =>
            previous.terminalCount != next.terminalCount ||
            previous.isOpen != next.isOpen,
        builder: (context, state) {
          final l10n = context.l10n;
          final tooltip =
              '${l10n.resourceManagerTooltip(state.terminalCount)}\n'
              '${l10n.resourceManagerTooltipHint}';

          return TpActionMenuAnchor(
            controller: _popover,
            fixedPanelWidth: ResourceManagerPanel.panelWidth,
            padding: EdgeInsets.zero,
            closeOnTapOutside: true,
            anchor: const TpAnchor(
              // Open above the pill: attach panel bottom to pill top, 8px gap
              // (Orca PopoverContent side="top" sideOffset={8}).
              childAlignment: Alignment.bottomRight,
              overlayAlignment: Alignment.topRight,
              offset: Offset(0, -8),
            ),
            onOpen: () {
              unawaited(context.read<ResourceManagerCubit>().openPanel());
            },
            onClose: () {
              context.read<ResourceManagerCubit>().closePanel();
            },
            popoverBuilder: (context, _) => ResourceManagerPanel(
              onNavigateLeaf: widget.onNavigateLeaf,
            ),
            child: Tooltip(
              message: tooltip,
              child: _PillButton(
                compact: widget.compact,
                terminalCount: state.terminalCount,
                selected: state.isOpen,
                color: cs.onSurfaceVariant,
                onTap: _popover.toggle,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.compact,
    required this.terminalCount,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final bool compact;
  final int terminalCount;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final fill = cs.onSurface.withValues(alpha: 0.07);

    return TpHover(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      backgroundColor: selected ? fill : null,
      hoverColor: fill,
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.terminal, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '$terminalCount',
            style: styles.xs.copyWith(
              color: color,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
