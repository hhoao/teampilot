import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/workspace_tools_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import 'tool_view.dart';

/// Closable open-tab strip for right tools. Opened tabs stay mounted (keep-
/// alive); hide/show of the pane is owned by the shell drawer, not this
/// widget. Empty open-set shows a picker; [+] opens the same picker for
/// tools not yet open.
class TabbedPanel extends StatefulWidget {
  const TabbedPanel({required this.views, this.scopeId, super.key});

  final List<ToolView> views;

  /// When set, open/selected tabs are stored in [WorkspaceToolsCubit].
  final String? scopeId;

  @override
  State<TabbedPanel> createState() => _TabbedPanelState();
}

class _TabbedPanelState extends State<TabbedPanel> {
  final List<String> _localOpenIds = [];
  String? _localSelectedId;
  var _picking = false;
  var _autoOpenScheduled = false;

  Map<String, ToolView> get _byId => {
    for (final view in widget.views) view.id: view,
  };

  List<String> get _catalogIds => [for (final v in widget.views) v.id];

  List<String> _openIds(BuildContext context) {
    final scope = widget.scopeId;
    if (scope == null) return List<String>.of(_localOpenIds);
    return context.select<WorkspaceToolsCubit, List<String>>(
      (c) => c.openIdsFor(scope),
    );
  }

  String? _selectedId(BuildContext context) {
    final scope = widget.scopeId;
    if (scope == null) return _localSelectedId;
    return context.select<WorkspaceToolsCubit, String?>(
      (c) => c.selectedIdFor(scope),
    );
  }

  void _schedulePrune() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scope = widget.scopeId;
      final available = _catalogIds;
      if (scope != null) {
        context.read<WorkspaceToolsCubit>().pruneToAvailable(scope, available);
        return;
      }
      final nextOpen = [
        for (final id in _localOpenIds)
          if (available.contains(id)) id,
      ];
      if (nextOpen.length == _localOpenIds.length &&
          (_localSelectedId == null || available.contains(_localSelectedId))) {
        return;
      }
      setState(() {
        _localOpenIds
          ..clear()
          ..addAll(nextOpen);
        if (_localSelectedId != null && !nextOpen.contains(_localSelectedId)) {
          _localSelectedId = nextOpen.isEmpty ? null : nextOpen.last;
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant TabbedPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(
      [for (final v in oldWidget.views) v.id],
      _catalogIds,
    )) {
      _schedulePrune();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePrune();
  }

  void _open(String id) {
    final scope = widget.scopeId;
    if (scope != null) {
      context.read<WorkspaceToolsCubit>().ensureOpenAndSelect(scope, id);
    } else {
      setState(() {
        if (!_localOpenIds.contains(id)) _localOpenIds.add(id);
        _localSelectedId = id;
      });
    }
    setState(() => _picking = false);
  }

  void _select(String id) {
    final scope = widget.scopeId;
    if (scope != null) {
      context.read<WorkspaceToolsCubit>().selectTool(scope, id);
    } else {
      setState(() => _localSelectedId = id);
    }
    setState(() => _picking = false);
  }

  void _close(String id) {
    final scope = widget.scopeId;
    if (scope != null) {
      context.read<WorkspaceToolsCubit>().closeTool(scope, id);
    } else {
      setState(() {
        final index = _localOpenIds.indexOf(id);
        if (index < 0) return;
        _localOpenIds.removeAt(index);
        if (_localSelectedId == id) {
          if (_localOpenIds.isEmpty) {
            _localSelectedId = null;
          } else if (index > 0) {
            _localSelectedId = _localOpenIds[index - 1];
          } else {
            _localSelectedId = _localOpenIds.first;
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.views.isEmpty) return const SizedBox.shrink();

    final byId = _byId;
    final openIds = [
      for (final id in _openIds(context))
        if (byId.containsKey(id)) id,
    ];
    final selectedId = _selectedId(context);
    final effectiveSelected =
        selectedId != null && openIds.contains(selectedId)
        ? selectedId
        : (openIds.isEmpty ? null : openIds.last);
    final showPicker = _picking || openIds.isEmpty;
    final closedViews = [
      for (final view in widget.views)
        if (!openIds.contains(view.id)) view,
    ];

    if (widget.views.length == 1 &&
        openIds.isEmpty &&
        !_picking &&
        !_autoOpenScheduled) {
      _autoOpenScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _open(widget.views.single.id);
      });
    }

    return Column(
      children: [
        if (openIds.isNotEmpty) ...[
          _TabStrip(
            openViews: [for (final id in openIds) byId[id]!],
            selectedId: effectiveSelected,
            canAdd: closedViews.isNotEmpty,
            picking: _picking,
            onSelect: _select,
            onClose: _close,
            onAdd: () => setState(() => _picking = true),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ],
        Expanded(
          child: showPicker
              ? _OpenTabPicker(
                  views: openIds.isEmpty ? widget.views : closedViews,
                  onOpen: _open,
                )
              : _OpenTabBodies(
                  openViews: [for (final id in openIds) byId[id]!],
                  selectedId: effectiveSelected!,
                ),
        ),
      ],
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.openViews,
    required this.selectedId,
    required this.canAdd,
    required this.picking,
    required this.onSelect,
    required this.onClose,
    required this.onAdd,
  });

  final List<ToolView> openViews;
  final String? selectedId;
  final bool canAdd;
  final bool picking;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final view in openViews)
                  _OpenTabChip(
                    view: view,
                    active: view.id == selectedId && !picking,
                    onSelect: () => onSelect(view.id),
                    onClose: () => onClose(view.id),
                  ),
              ],
            ),
          ),
          if (canAdd)
            Tooltip(
              message: context.l10n.rightToolsOpenTabTitle,
              child: TpHover(
                width: 36,
                height: 40,
                borderRadius: BorderRadius.zero,
                onTap: onAdd,
                child: Icon(
                  Icons.add,
                  size: context.tpIconSizes.md,
                  color: picking ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OpenTabChip extends StatelessWidget {
  const _OpenTabChip({
    required this.view,
    required this.active,
    required this.onSelect,
    required this.onClose,
  });

  final ToolView view;
  final bool active;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final color = active ? cs.primary : cs.onSurfaceVariant;
    return Tooltip(
      message: view.label,
      waitDuration: const Duration(milliseconds: 400),
      child: TpHover(
        onTap: onSelect,
        height: 40,
        borderRadius: BorderRadius.zero,
        hoverColor: cs.onSurface.withValues(alpha: 0.05),
        // Stretch to the strip height so the active bottom border sits flush
        // with the edge; TpHover centers a content-sized child by default.
        child: SizedBox(
          height: double.infinity,
          child: Container(
            padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: active ? cs.primary : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(view.icon, size: context.tpIconSizes.md, color: color),
                if (view.badgeCount > 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: cs.error,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    constraints: const BoxConstraints(minWidth: 14),
                    child: Text(
                      '${view.badgeCount}',
                      textAlign: TextAlign.center,
                      style: styles.xsSemiboldSnugColored(cs.onError),
                    ),
                  ),
                ],
                TpHover(
                  width: 24,
                  height: 24,
                  borderRadius: BorderRadius.circular(4),
                  onTap: onClose,
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OpenTabPicker extends StatelessWidget {
  const _OpenTabPicker({required this.views, required this.onOpen});

  final List<ToolView> views;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    if (views.isEmpty) {
      return Center(
        child: Text(
          l10n.rightToolsOpenTabEmpty,
          style: styles.mdColored(cs.onSurfaceVariant),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const maxContentWidth = 280.0;
        final content = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxContentWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.rightToolsOpenTabTitle,
                textAlign: TextAlign.center,
                style: styles.xl,
              ),
              SizedBox(height: spacing.sm),
              Text(
                l10n.rightToolsOpenTabSubtitle,
                textAlign: TextAlign.center,
                style: styles.smColored(cs.onSurfaceVariant),
              ),
              SizedBox(height: spacing.xl),
              for (final view in views) ...[
                _PickerTile(view: view, onTap: () => onOpen(view.id)),
                SizedBox(height: spacing.sm),
              ],
              SizedBox(height: spacing.lg),
            ],
          ),
        );
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.xl,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({required this.view, required this.onTap});

  final ToolView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final spacing = context.tpSpacing;
    return TpHover(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.55),
      hoverColor: cs.onSurface.withValues(alpha: 0.06),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.md,
        ),
        child: Row(
          children: [
            Icon(view.icon, size: context.tpIconSizes.md, color: cs.onSurface),
            SizedBox(width: spacing.sm),
            Expanded(
              child: Text(view.label, style: styles.md),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenTabBodies extends StatelessWidget {
  const _OpenTabBodies({required this.openViews, required this.selectedId});

  final List<ToolView> openViews;
  final String selectedId;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final view in openViews)
          TpKeepAliveLayer(
            active: view.id == selectedId,
            child: KeyedSubtree(
              key: ValueKey<String>('right-tool-body-${view.id}'),
              child: view.child,
            ),
          ),
      ],
    );
  }
}
