import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/resource_manager_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../pages/home_workspace/workspace/workspace_resource_manager_scope.dart';
import '../../services/resource_manager/resource_memory_format.dart';
import '../../services/resource_manager/resource_tree_merge.dart';
import 'resource_manager_panel.dart';
import 'workspace_status_bar.dart';

/// Closed status-bar pill + Resource Manager popover (`resource-usage`).
class ResourceUsageStatusItem implements WorkspaceStatusBarItem {
  ResourceUsageStatusItem({this.onNavigateLeaf});

  /// Optional navigate hook. When null, [buildSegment] resolves
  /// [ResourceManagerNavigateScope] from its build context (must be under
  /// [WorkspaceResourceManagerScope]).
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

  String _memoryLabel(ResourceManagerState state) {
    return formatResourceMemory(state.snapshot?.totalMemory);
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
            previous.snapshot?.totalMemory != next.snapshot?.totalMemory ||
            previous.isOpen != next.isOpen,
        builder: (context, state) {
          final l10n = context.l10n;
          final memoryLabel = _memoryLabel(state);
          final tooltip =
              '${l10n.resourceManagerTooltip(memoryLabel, state.terminalCount)}\n'
              '${l10n.resourceManagerTooltipHint}';

          return TpActionMenuAnchor(
            controller: _popover,
            fixedPanelWidth: ResourceManagerPanel.panelWidth,
            padding: EdgeInsets.zero,
            closeOnTapOutside: true,
            anchor: const TpAnchor(
              childAlignment: Alignment.topRight,
              overlayAlignment: Alignment.bottomRight,
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
                memoryLabel: memoryLabel,
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

class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.compact,
    required this.memoryLabel,
    required this.terminalCount,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final bool compact;
  final String memoryLabel;
  final int terminalCount;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final styles = TpTextStyles.of(context);
    final cs = Theme.of(context).colorScheme;
    final compact = widget.compact;
    final shortMemory = widget.memoryLabel == kResourceMetricEmDash
        ? kResourceMetricEmDash
        : widget.memoryLabel.replaceAll(' MB', '');

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 8,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: widget.selected || _hovered
                ? cs.onSurface.withValues(alpha: 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.memory, size: 13, color: widget.color),
              const SizedBox(width: 4),
              Text(
                compact ? shortMemory : widget.memoryLabel,
                style: styles.xs.copyWith(
                  color: widget.color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  '·',
                  style: styles.xs.copyWith(
                    color: widget.color.withValues(alpha: 0.5),
                  ),
                ),
              ),
              Icon(Icons.terminal, size: 12, color: widget.color),
              const SizedBox(width: 4),
              Text(
                '${widget.terminalCount}',
                style: styles.xs.copyWith(
                  color: widget.color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
