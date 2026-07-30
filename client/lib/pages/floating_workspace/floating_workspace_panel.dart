import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/floating_workspace/floating_panel_visibility.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_state.dart';
import '../../cubits/shortcut_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../services/commands/command_bus.dart';
import '../../services/commands/command_catalog.dart';
import '../../services/commands/command_ids.dart';
import '../../services/commands/key_chord.dart';
import '../../services/commands/key_chord_formatter.dart';
import '../../services/commands/keybinding_resolver.dart';
import '../../services/floating_workspace/close_floating_tab.dart';
import '../../services/floating_workspace/floating_maximize_insets.dart';
import '../../services/floating_workspace/floating_surface_registry.dart';
import '../../theme/workspace_surface_layers.dart';
import 'floating_workspace_chrome.dart';
import 'floating_workspace_close_shortcut.dart';
import 'floating_workspace_empty.dart';
import 'floating_workspace_tab_bar.dart';

const double _kMinPanelWidth = 320;
const double _kMinPanelHeight = 240;
const double _kResizeHandle = 6;
const double _kTitleBarHeight = 40;

/// Floating workspace overlay panel: chrome, tabs, drag, and edge resize.
class FloatingWorkspacePanel extends StatefulWidget {
  const FloatingWorkspacePanel({super.key});

  @override
  State<FloatingWorkspacePanel> createState() => _FloatingWorkspacePanelState();
}

class _FloatingWorkspacePanelState extends State<FloatingWorkspacePanel> {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FloatingWorkspaceCubit, FloatingWorkspaceState>(
      builder: (context, state) => _buildForState(context, state),
    );
  }

  Widget _buildForState(BuildContext context, FloatingWorkspaceState state) {
    final hasTabs = state.activeBucket.tabs.isNotEmpty;
    final keepAliveMinimized =
        state.visibility == FloatingPanelVisibility.minimized && hasTabs;

    if (state.visibility == FloatingPanelVisibility.hidden ||
        (state.visibility == FloatingPanelVisibility.minimized && !hasTabs)) {
      return const SizedBox.shrink();
    }

    final registry = context.read<FloatingSurfaceRegistry>();
    Widget child = FloatingWorkspaceCloseShortcut(
      registry: registry,
      autofocus: state.visibility == FloatingPanelVisibility.open,
      child: _FloatingWorkspacePanelBody(
        key: const Key('floating_workspace_panel'),
        state: state,
        registry: registry,
      ),
    );

    if (keepAliveMinimized) {
      child = Offstage(
        key: const Key('floating_workspace_panel_keep_alive'),
        offstage: true,
        child: TickerMode(
          enabled: false,
          child: IgnorePointer(child: child),
        ),
      );
    }

    return child;
  }
}

class _FloatingWorkspacePanelBody extends StatelessWidget {
  const _FloatingWorkspacePanelBody({
    required this.state,
    required this.registry,
    super.key,
  });

  final FloatingWorkspaceState state;
  final FloatingSurfaceRegistry registry;

  @override
  Widget build(BuildContext context) {
    final insetsListenable = context.read<FloatingMaximizeInsets>().listenable;
    return ValueListenableBuilder<EdgeInsets?>(
      valueListenable: insetsListenable,
      builder: (context, insets, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final hostSize = Size(constraints.maxWidth, constraints.maxHeight);
            final safe = insets ?? EdgeInsets.zero;

            final Rect positioned;
            if (state.isMaximized &&
                state.visibility == FloatingPanelVisibility.open) {
              positioned = Rect.fromLTRB(
                safe.left,
                safe.top,
                hostSize.width - safe.right,
                hostSize.height - safe.bottom,
              );
            } else {
              positioned = clampFloatingPanelBounds(state.panelBounds, hostSize);
            }

            return Stack(
              children: [
                Positioned(
                  left: positioned.left,
                  top: positioned.top,
                  width: positioned.width,
                  height: positioned.height,
                  child: _PanelChromeFrame(
                    state: state,
                    registry: registry,
                    hostSize: hostSize,
                    allowDragResize: !state.isMaximized &&
                        state.visibility == FloatingPanelVisibility.open,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Clamps [bounds] inside [host] with minimum panel size.
@visibleForTesting
Rect clampFloatingPanelBounds(Rect bounds, Size host) {
  if (host.width <= 0 || host.height <= 0) return bounds;
  final width = bounds.width.clamp(_kMinPanelWidth, host.width).toDouble();
  final height = bounds.height.clamp(_kMinPanelHeight, host.height).toDouble();
  final left = bounds.left.clamp(0.0, math.max(0.0, host.width - width));
  final top = bounds.top.clamp(0.0, math.max(0.0, host.height - height));
  return Rect.fromLTWH(left.toDouble(), top.toDouble(), width, height);
}

class _PanelChromeFrame extends StatefulWidget {
  const _PanelChromeFrame({
    required this.state,
    required this.registry,
    required this.hostSize,
    required this.allowDragResize,
  });

  final FloatingWorkspaceState state;
  final FloatingSurfaceRegistry registry;
  final Size hostSize;
  final bool allowDragResize;

  @override
  State<_PanelChromeFrame> createState() => _PanelChromeFrameState();
}

class _PanelChromeFrameState extends State<_PanelChromeFrame> {
  Offset? _dragStartPointer;
  Rect? _dragStartBounds;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bucket = widget.state.activeBucket;
    final tabs = bucket.tabs;
    final activeId = bucket.activeTabId;
    final activeTab =
        tabs.firstWhereOrNull((t) => t.id == activeId) ?? tabs.firstOrNull;
    final surface =
        activeTab == null ? null : widget.registry[activeTab.surfaceId];

    return Material(
      elevation: 8,
      color: cs.workspaceCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TitleBar(
                onPanStart: widget.allowDragResize ? _onDragStart : null,
                onPanUpdate: widget.allowDragResize ? _onDragUpdate : null,
                onPanEnd: widget.allowDragResize ? _onDragEnd : null,
                tabBar: tabs.isEmpty
                    ? null
                    : FloatingWorkspaceTabBar(
                        tabs: tabs,
                        activeTabId: activeId,
                        onSelect: (id) {
                          context.read<FloatingWorkspaceCubit>().selectTab(id);
                          final tab = tabs.firstWhereOrNull((t) => t.id == id);
                          if (tab == null) return;
                          final s = widget.registry[tab.surfaceId];
                          if (s != null) unawaited(s.activate(tab));
                        },
                        onClose: (tab) {
                          unawaited(
                            closeFloatingTab(
                              cubit: context.read<FloatingWorkspaceCubit>(),
                              registry: widget.registry,
                              tab: tab,
                              context: context,
                            ),
                          );
                        },
                      ),
              ),
              Expanded(
                child: tabs.isEmpty
                    ? FloatingWorkspaceEmpty(
                        autofocus: true,
                        rows: _emptyRows(context),
                        onActivate: (id) => _onEmptyActivate(context, id),
                      )
                    : (surface == null || activeTab == null)
                    ? const SizedBox.shrink()
                    : KeyedSubtree(
                        key: ValueKey(activeTab.id),
                        child: surface.build(context, activeTab),
                      ),
              ),
            ],
          ),
          if (widget.allowDragResize) ..._resizeHandles(context),
        ],
      ),
    );
  }

  List<FloatingWorkspaceEmptyRow> _emptyRows(BuildContext context) {
    final l10n = context.l10n;
    return [
      for (final action in widget.registry.emptyActions)
        FloatingWorkspaceEmptyRow(
          id: action.commandId,
          icon: action.icon,
          label: _labelFor(l10n, action.labelKey),
          shortcutLabels: _shortcutLabels(context, action.commandId),
        ),
      FloatingWorkspaceEmptyRow(
        id: CommandIds.floatingMinimize,
        icon: Icons.remove,
        label: l10n.floatingWorkspaceMinimize,
        shortcutLabels: _shortcutLabels(context, CommandIds.floatingMinimize),
      ),
    ];
  }

  String _labelFor(AppLocalizations l10n, String labelKey) {
    return switch (labelKey) {
      'newTerminal' => l10n.floatingWorkspaceNewTerminal,
      'openFile' => l10n.floatingWorkspaceOpenFile,
      'minimize' => l10n.floatingWorkspaceMinimize,
      _ => labelKey,
    };
  }

  List<String> _shortcutLabels(BuildContext context, String commandId) {
    try {
      final overrides = context.read<ShortcutCubit>().state.overrides;
      final bindings = KeybindingResolver.effectiveBindings(
        catalog: CommandCatalog.v1,
        overrides: overrides,
      );
      var chords = bindings[commandId] ?? const <KeyChord>[];
      if (chords.isEmpty && commandId == CommandIds.floatingNewTerminal) {
        chords = bindings[CommandIds.togglePanel] ?? const [];
      }
      if (chords.isEmpty) return const [];
      return [
        for (final c in chords.take(1))
          formatKeyChord(c, isMacOS: defaultIsMacOS()),
      ];
    } catch (_) {
      return const [];
    }
  }

  void _onEmptyActivate(BuildContext context, String id) {
    context.read<CommandBus>().invoke(id);
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartPointer = details.globalPosition;
    _dragStartBounds = widget.state.panelBounds;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final start = _dragStartBounds;
    final pointer = _dragStartPointer;
    if (start == null || pointer == null) return;
    final delta = details.globalPosition - pointer;
    context.read<FloatingWorkspaceCubit>().setPanelBounds(
      clampFloatingPanelBounds(
        Rect.fromLTWH(
          start.left + delta.dx,
          start.top + delta.dy,
          start.width,
          start.height,
        ),
        widget.hostSize,
      ),
    );
  }

  void _onDragEnd(DragEndDetails details) {
    _dragStartPointer = null;
    _dragStartBounds = null;
  }

  List<Widget> _resizeHandles(BuildContext context) {
    return [
      for (final edge in _ResizeEdge.values)
        _ResizeHandle(
          edge: edge,
          onUpdate: (delta) => _applyResize(context, edge, delta),
        ),
    ];
  }

  void _applyResize(BuildContext context, _ResizeEdge edge, Offset delta) {
    final b = widget.state.panelBounds;
    var left = b.left;
    var top = b.top;
    var right = b.right;
    var bottom = b.bottom;

    if (edge.adjustsLeft) left += delta.dx;
    if (edge.adjustsRight) right += delta.dx;
    if (edge.adjustsTop) top += delta.dy;
    if (edge.adjustsBottom) bottom += delta.dy;

    var width = right - left;
    var height = bottom - top;
    if (width < _kMinPanelWidth) {
      if (edge.adjustsLeft) {
        left = right - _kMinPanelWidth;
      } else {
        right = left + _kMinPanelWidth;
      }
      width = _kMinPanelWidth;
    }
    if (height < _kMinPanelHeight) {
      if (edge.adjustsTop) {
        top = bottom - _kMinPanelHeight;
      } else {
        bottom = top + _kMinPanelHeight;
      }
      height = _kMinPanelHeight;
    }

    context.read<FloatingWorkspaceCubit>().setPanelBounds(
      clampFloatingPanelBounds(
        Rect.fromLTRB(left, top, left + width, top + height),
        widget.hostSize,
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.tabBar,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
  });

  final Widget? tabBar;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.workspaceSubtleSurface,
      child: SizedBox(
        height: _kTitleBarHeight,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: onPanStart,
                onPanUpdate: onPanUpdate,
                onPanEnd: onPanEnd,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: tabBar ?? const SizedBox.expand(),
                ),
              ),
            ),
            const FloatingWorkspaceChrome(),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

enum _ResizeEdge {
  n(adjustsTop: true),
  s(adjustsBottom: true),
  w(adjustsLeft: true),
  e(adjustsRight: true),
  nw(adjustsTop: true, adjustsLeft: true),
  ne(adjustsTop: true, adjustsRight: true),
  sw(adjustsBottom: true, adjustsLeft: true),
  se(adjustsBottom: true, adjustsRight: true);

  const _ResizeEdge({
    this.adjustsLeft = false,
    this.adjustsRight = false,
    this.adjustsTop = false,
    this.adjustsBottom = false,
  });

  final bool adjustsLeft;
  final bool adjustsRight;
  final bool adjustsTop;
  final bool adjustsBottom;
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.edge, required this.onUpdate});

  final _ResizeEdge edge;
  final ValueChanged<Offset> onUpdate;

  @override
  Widget build(BuildContext context) {
    final cursor = switch (edge) {
      _ResizeEdge.n || _ResizeEdge.s => SystemMouseCursors.resizeUpDown,
      _ResizeEdge.w || _ResizeEdge.e => SystemMouseCursors.resizeLeftRight,
      _ResizeEdge.nw ||
      _ResizeEdge.se => SystemMouseCursors.resizeUpLeftDownRight,
      _ResizeEdge.ne ||
      _ResizeEdge.sw => SystemMouseCursors.resizeUpRightDownLeft,
    };

    double? width;
    double? height;
    double? left;
    double? top;
    double? right;
    double? bottom;

    switch (edge) {
      case _ResizeEdge.n:
        height = _kResizeHandle;
        left = _kResizeHandle;
        right = _kResizeHandle;
        top = 0;
      case _ResizeEdge.s:
        height = _kResizeHandle;
        left = _kResizeHandle;
        right = _kResizeHandle;
        bottom = 0;
      case _ResizeEdge.w:
        width = _kResizeHandle;
        top = _kResizeHandle;
        bottom = _kResizeHandle;
        left = 0;
      case _ResizeEdge.e:
        width = _kResizeHandle;
        top = _kResizeHandle;
        bottom = _kResizeHandle;
        right = 0;
      case _ResizeEdge.nw:
        width = _kResizeHandle * 2;
        height = _kResizeHandle * 2;
        left = 0;
        top = 0;
      case _ResizeEdge.ne:
        width = _kResizeHandle * 2;
        height = _kResizeHandle * 2;
        right = 0;
        top = 0;
      case _ResizeEdge.sw:
        width = _kResizeHandle * 2;
        height = _kResizeHandle * 2;
        left = 0;
        bottom = 0;
      case _ResizeEdge.se:
        width = _kResizeHandle * 2;
        height = _kResizeHandle * 2;
        right = 0;
        bottom = 0;
    }

    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanUpdate: (details) => onUpdate(details.delta),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
