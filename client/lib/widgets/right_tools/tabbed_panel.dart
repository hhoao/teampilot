import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/workspace_tools_cubit.dart';
import '../../theme/app_icon_sizes.dart';
import '../hover_widget.dart';
import 'tool_view.dart';

/// VSCode-style tool panel: a horizontal row of icon buttons at the top
/// switches the single visible view. Driven by a uniform [ToolView] list so
/// callers control which views (and conditional ones) appear.
class TabbedPanel extends StatefulWidget {
  const TabbedPanel({required this.views, this.scopeId, super.key});

  final List<ToolView> views;

  /// When set, the selected tool index is persisted per-scope in
  /// [WorkspaceToolsCubit] (one scope == one workspaceId) so it survives workspace
  /// switches. When null, selection is local widget state.
  final String? scopeId;

  @override
  State<TabbedPanel> createState() => _TabbedPanelState();
}

class _TabbedPanelState extends State<TabbedPanel> {
  int _localSelected = 0;
  final Set<int> _visitedIndices = {0};

  void _select(int index) {
    final scope = widget.scopeId;
    setState(() => _visitedIndices.add(index));
    if (scope == null) {
      setState(() => _localSelected = index);
    } else {
      context.read<WorkspaceToolsCubit>().setSelectedIndex(scope, index);
    }
  }

  /// Lazy-mount off-tab bodies once visited; the selected tab always mounts
  /// immediately so a restored [WorkspaceToolsCubit] index is not blank until
  /// the next frame (or a second tap).
  bool _mountChild(int index, int selected) =>
      index == selected || _visitedIndices.contains(index);

  void _rememberVisit(int index) {
    if (_visitedIndices.contains(index)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _visitedIndices.contains(index)) return;
      setState(() => _visitedIndices.add(index));
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.views.isEmpty) return const SizedBox.shrink();
    if (widget.views.length == 1) return widget.views.single.child;

    final selected = widget.scopeId == null
        ? _localSelected
        : context.select<WorkspaceToolsCubit, int>(
            (c) => c.selectedIndexFor(widget.scopeId!),
          );
    final clamped = selected.clamp(0, widget.views.length - 1);
    _rememberVisit(clamped);

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              for (var i = 0; i < widget.views.length; i++)
                _SwitcherButton(
                  view: widget.views[i],
                  active: i == clamped,
                  onTap: () => _select(i),
                ),
            ],
          ),
        ),
        Divider(height: 1, thickness: 1, color: cs.outlineVariant),
        Expanded(
          child: IndexedStack(
            index: clamped,
            sizing: StackFit.expand,
            children: [
              for (var i = 0; i < widget.views.length; i++)
                _mountChild(i, clamped)
                    ? widget.views[i].child
                    : const SizedBox.shrink(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SwitcherButton extends StatelessWidget {
  const _SwitcherButton({
    required this.view,
    required this.active,
    required this.onTap,
  });

  final ToolView view;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = active ? cs.primary : cs.onSurfaceVariant;
    return Tooltip(
      message: view.label,
      child: HoverWidget(
        width: 44,
        height: 40,
        borderRadius: BorderRadius.zero,
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? cs.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(view.icon, size: context.appIconSizes.md, color: color),
              if (view.badgeCount > 0)
                Positioned(
                  right: -6,
                  top: -4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: cs.error,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(minWidth: 14),
                    child: Text(
                      '${view.badgeCount}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: cs.onError,
                        fontSize: 9,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
