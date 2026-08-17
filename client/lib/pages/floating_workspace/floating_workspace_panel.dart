import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/floating_workspace/floating_panel_visibility.dart';
import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/floating_workspace/floating_workspace_projection.dart';
import '../../cubits/floating_workspace/floating_workspace_state.dart';
import '../../cubits/shortcut_cubit.dart';
import '../../cubits/workbench/tab_strip.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
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
import '../../services/floating_workspace/floating_terminal_pty_hold_scope.dart';
import '../../services/floating_workspace/floating_workspace_toggle_metrics.dart';
import '../../widgets/workbench/workbench_shell_run_sync.dart';
import '../../widgets/workspace_terminal_panel.dart';
import 'floating_workspace_chrome.dart';
import 'floating_workspace_close_shortcut.dart';
import 'floating_workspace_empty.dart';
import 'floating_workspace_new_terminal_menu.dart';
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
  late final FloatingWorkspaceProjection<_FloatingPanelView> _projection;

  @override
  void initState() {
    super.initState();
    final floating = context.read<FloatingWorkspaceCubit>();
    final workbench = context.read<WorkbenchCubit>();
    // Combines the two change planes: chrome (FloatingWorkspaceCubit) and the
    // floating strip (WorkbenchCubit bar.floating). Only the active workspace's
    // strip is projected so unrelated bar mutations do not rebuild the panel.
    _projection = FloatingWorkspaceProjection<_FloatingPanelView>(
      floating,
      workbench,
      (floating, workbench) => _FloatingPanelView(
        state: floating.state,
        strip: workbench.state.bar(floating.state.activeWorkspaceId).floating,
      ),
      initial: _FloatingPanelView(
        state: floating.state,
        strip: workbench.state.bar(floating.state.activeWorkspaceId).floating,
      ),
    );
  }

  @override
  void dispose() {
    _projection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_FloatingPanelView>(
      valueListenable: _projection,
      builder: (context, view, _) => _buildForView(context, view),
    );
  }

  Widget _buildForView(BuildContext context, _FloatingPanelView view) {
    final state = view.state;
    final strip = view.strip;
    final hasTabs = strip.order.isNotEmpty;
    final keepAliveMinimized =
        state.visibility == FloatingPanelVisibility.minimized && hasTabs;

    if (state.visibility == FloatingPanelVisibility.hidden ||
        (state.visibility == FloatingPanelVisibility.minimized && !hasTabs)) {
      return const SizedBox.shrink();
    }

    final registry = context.read<FloatingSurfaceRegistry>();
    final workspaceId = state.activeWorkspaceId.trim();
    final tabs = <FloatingTab>[];
    final barIdByTabId = <String, WorkbenchTabId>{};
    String? activeTabId;
    for (final barId in strip.order) {
      final tab = resolveFloatingTabForId(
        registry: registry,
        workspaceId: workspaceId,
        id: barId,
      );
      if (tab == null) continue;
      tabs.add(tab);
      barIdByTabId[tab.id] = barId;
      if (barId == strip.activeId) activeTabId = tab.id;
    }

    Widget child = FloatingWorkspaceCloseShortcut(
      registry: registry,
      autofocus: state.visibility == FloatingPanelVisibility.open,
      child: _FloatingWorkspacePanelBody(
        key: const Key('floating_workspace_panel'),
        state: state,
        workspaceId: workspaceId,
        tabs: tabs,
        activeTabId: activeTabId,
        barIdByTabId: barIdByTabId,
        registry: registry,
      ),
    );

    if (keepAliveMinimized) {
      // Keep PTY/editor state alive while chrome is hidden.
      child = Visibility(
        key: const Key('floating_workspace_panel_keep_alive'),
        visible: false,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: false,
        child: IgnorePointer(child: child),
      );
    }

    return child;
  }
}

/// Snapshot the panel needs each rebuild: chrome state + the floating strip of
/// the active workspace.
class _FloatingPanelView extends Equatable {
  const _FloatingPanelView({required this.state, required this.strip});

  final FloatingWorkspaceState state;
  final TabStrip strip;

  @override
  List<Object?> get props => [state, strip];
}

class _FloatingWorkspacePanelBody extends StatefulWidget {
  const _FloatingWorkspacePanelBody({
    required this.state,
    required this.workspaceId,
    required this.tabs,
    required this.activeTabId,
    required this.barIdByTabId,
    required this.registry,
    super.key,
  });

  final FloatingWorkspaceState state;
  final String workspaceId;
  final List<FloatingTab> tabs;
  final String? activeTabId;
  final Map<String, WorkbenchTabId> barIdByTabId;
  final FloatingSurfaceRegistry registry;

  @override
  State<_FloatingWorkspacePanelBody> createState() =>
      _FloatingWorkspacePanelBodyState();
}

class _FloatingWorkspacePanelBodyState
    extends State<_FloatingWorkspacePanelBody> {
  /// Local geometry while dragging/resizing so the panel tracks the pointer
  /// without waiting on Bloc rebuilds / persistence.
  Rect? _gestureBounds;
  final _terminalHold = WorkspaceTerminalHoldHandle();

  void _beginGesture(Rect bounds) {
    _gestureBounds = bounds;
  }

  void _updateGesture(Rect bounds) {
    if (_gestureBounds == bounds) return;
    setState(() => _gestureBounds = bounds);
  }

  void _endGesture(Rect bounds) {
    // Prefer live gesture geometry: child onEnd often still sees the pre-rebuild
    // [panelBounds] one frame behind the last [onGestureUpdate].
    final finalBounds = _gestureBounds ?? bounds;
    context.read<FloatingWorkspaceCubit>().setPanelRect(
      finalBounds,
      _lastHostSize ?? Size(finalBounds.width, finalBounds.height),
    );
    if (_gestureBounds != null) {
      setState(() => _gestureBounds = null);
    }
  }

  Size? _lastHostSize;

  Rect _resolvePlacedRect(FloatingWorkspaceState state, Size hostSize) {
    final legacy = state.legacyAbsoluteBounds;
    if (legacy != null) {
      final clamped = clampFloatingPanelBounds(legacy, hostSize);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final cubit = context.read<FloatingWorkspaceCubit>();
        if (cubit.state.legacyAbsoluteBounds != null) {
          cubit.setPanelRect(clamped, hostSize);
        }
      });
      return clamped;
    }
    final placement =
        state.panelPlacement ??
        defaultFloatingPanelPlacement(toggleOffset: state.toggleOffset);
    return placement.resolve(
      hostSize,
      minWidth: _kMinPanelWidth,
      minHeight: _kMinPanelHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final insetsListenable = context.read<FloatingMaximizeInsets>().listenable;
    return ValueListenableBuilder<EdgeInsets?>(
      valueListenable: insetsListenable,
      builder: (context, insets, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final hostSize = Size(constraints.maxWidth, constraints.maxHeight);
            _lastHostSize = hostSize;
            final safe =
                insets ??
                FloatingMaximizeInsets.cardSafeArea(
                  isMobile: TpSidebarScope.maybeOf(context)?.isMobile ?? false,
                );

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
              final raw = _gestureBounds ?? _resolvePlacedRect(state, hostSize);
              positioned = clampFloatingPanelBounds(raw, hostSize);
              if (_gestureBounds == null &&
                  !state.hasPlacedPanel &&
                  state.visibility == FloatingPanelVisibility.open &&
                  hostSize.width > 0 &&
                  hostSize.height > 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!context.mounted) return;
                  final cubit = context.read<FloatingWorkspaceCubit>();
                  if (!cubit.state.hasPlacedPanel) {
                    cubit.setPanelRect(positioned, hostSize);
                  }
                });
              }
            }

            return Stack(
              children: [
                Positioned(
                  left: positioned.left,
                  top: positioned.top,
                  width: positioned.width,
                  height: positioned.height,
                  child: FloatingTerminalPtyHoldScope(
                    holdHandle: _terminalHold,
                    child: _PanelChromeFrame(
                      state: state,
                      workspaceId: widget.workspaceId,
                      tabs: widget.tabs,
                      activeTabId: widget.activeTabId,
                      barIdByTabId: widget.barIdByTabId,
                      registry: widget.registry,
                      hostSize: hostSize,
                      panelBounds: positioned,
                      allowTitleDrag:
                          state.visibility == FloatingPanelVisibility.open,
                      allowEdgeResize:
                          !state.isMaximized &&
                          state.visibility == FloatingPanelVisibility.open,
                      onGestureBegin: _beginGesture,
                      onGestureUpdate: _updateGesture,
                      onGestureEnd: _endGesture,
                    ),
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

/// Default open placement: bottom-right insets cleared above the toggle.
@visibleForTesting
FloatingPanelPlacement defaultFloatingPanelPlacement({
  Offset toggleOffset = kFloatingWorkspaceToggleDefaultOffset,
  double preferredWidth = 720,
  double preferredHeight = 480,
}) {
  final rightInset = (-toggleOffset.dx).clamp(0.0, double.infinity).toDouble();
  final bottomInset =
      ((-toggleOffset.dy) +
              kFloatingWorkspaceToggleSize +
              kFloatingWorkspacePanelToggleGap)
          .clamp(0.0, double.infinity)
          .toDouble();
  return FloatingPanelPlacement(
    width: preferredWidth,
    height: preferredHeight,
    rightInset: rightInset,
    bottomInset: bottomInset,
  );
}

/// Default open placement resolved against [host] (tests / first paint).
@visibleForTesting
Rect defaultFloatingPanelBounds(
  Size host, {
  Offset toggleOffset = kFloatingWorkspaceToggleDefaultOffset,
  double preferredWidth = 720,
  double preferredHeight = 480,
}) {
  return defaultFloatingPanelPlacement(
    toggleOffset: toggleOffset,
    preferredWidth: preferredWidth,
    preferredHeight: preferredHeight,
  ).resolve(host, minWidth: _kMinPanelWidth, minHeight: _kMinPanelHeight);
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

/// Follow-the-pointer restore rect when dragging out of maximize.
@visibleForTesting
Rect restoreFloatingPanelBoundsFromMaximize({
  required Rect maxRect,
  required Size hostSize,
  required Offset hostLocalPointer,
  required double restoredWidth,
  required double restoredHeight,
  double titleBarHeight = _kTitleBarHeight,
}) {
  final fracX = maxRect.width <= 0
      ? 0.5
      : ((hostLocalPointer.dx - maxRect.left) / maxRect.width).clamp(0.0, 1.0);
  final left = hostLocalPointer.dx - fracX * restoredWidth;
  final top = hostLocalPointer.dy - titleBarHeight / 2;
  return clampFloatingPanelBounds(
    Rect.fromLTWH(left, top, restoredWidth, restoredHeight),
    hostSize,
  );
}

/// Restore size only (no legacy post-frame migration side effects).
@visibleForTesting
Size floatingPanelRestoreSize(FloatingWorkspaceState state, Size hostSize) {
  final legacy = state.legacyAbsoluteBounds;
  if (legacy != null) {
    final clamped = clampFloatingPanelBounds(legacy, hostSize);
    return Size(clamped.width, clamped.height);
  }
  final placement =
      state.panelPlacement ??
      defaultFloatingPanelPlacement(toggleOffset: state.toggleOffset);
  final resolved = placement.resolve(
    hostSize,
    minWidth: _kMinPanelWidth,
    minHeight: _kMinPanelHeight,
  );
  return Size(resolved.width, resolved.height);
}

class _PanelChromeFrame extends StatefulWidget {
  const _PanelChromeFrame({
    required this.state,
    required this.workspaceId,
    required this.tabs,
    required this.activeTabId,
    required this.barIdByTabId,
    required this.registry,
    required this.hostSize,
    required this.panelBounds,
    required this.allowTitleDrag,
    required this.allowEdgeResize,
    required this.onGestureBegin,
    required this.onGestureUpdate,
    required this.onGestureEnd,
  });

  final FloatingWorkspaceState state;
  final String workspaceId;
  final List<FloatingTab> tabs;
  final String? activeTabId;
  final Map<String, WorkbenchTabId> barIdByTabId;
  final FloatingSurfaceRegistry registry;
  final Size hostSize;
  final Rect panelBounds;
  final bool allowTitleDrag;
  final bool allowEdgeResize;
  final ValueChanged<Rect> onGestureBegin;
  final ValueChanged<Rect> onGestureUpdate;
  final ValueChanged<Rect> onGestureEnd;

  @override
  State<_PanelChromeFrame> createState() => _PanelChromeFrameState();
}

class _PanelChromeFrameState extends State<_PanelChromeFrame> {
  Offset? _dragStartPointer;
  Rect? _dragStartBounds;
  Offset? _resizeStartPointer;
  Rect? _resizeStartBounds;
  _ResizeEdge? _activeResizeEdge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final tabs = widget.tabs;
    final activeId = widget.activeTabId;

    final shadow = BoxDecoration(
      borderRadius: BorderRadius.circular(10),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.48 : 0.16),
          blurRadius: isDark ? 28 : 22,
          offset: Offset(0, isDark ? 12 : 8),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
          blurRadius: isDark ? 10 : 8,
          offset: const Offset(0, 2),
        ),
      ],
    );

    // Shadow layer is separate from tab/body content so Empty→first-tab does
    // not re-blur the soft shadow (that work sits outside layout/paint probes).
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: DecoratedBox(
            decoration: shadow,
            child: const SizedBox.expand(),
          ),
        ),
        // Avoid Material/_InkFeatures on Empty→first-tab; ClipRRect is enough.
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.hardEdge,
          child: ColoredBox(
            color: cs.surface,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.7),
                ),
              ),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _TitleBar(
                        onPanStart: widget.allowTitleDrag ? _onDragStart : null,
                        onPanUpdate: widget.allowTitleDrag
                            ? _onDragUpdate
                            : null,
                        onPanEnd: widget.allowTitleDrag ? _onDragEnd : null,
                        onDoubleTap: widget.allowTitleDrag
                            ? () {
                                context
                                    .read<FloatingWorkspaceCubit>()
                                    .setMaximized(!widget.state.isMaximized);
                              }
                            : null,
                        onOpenFile: () {
                          context.read<CommandBus>().invoke(
                            CommandIds.floatingOpenFile,
                          );
                        },
                        tabBar: FloatingWorkspaceTabBar(
                          tabs: tabs,
                          activeTabId: activeId,
                          onSelect: (id) {
                            final tab = tabs.firstWhereOrNull(
                              (t) => t.id == id,
                            );
                            if (tab == null) return;
                            final barId = widget.barIdByTabId[id];
                            if (barId != null) {
                              context
                                  .read<WorkbenchCubit>()
                                  .activate(widget.workspaceId, barId);
                            }
                            final s = widget.registry[tab.surfaceId];
                            if (s != null) {
                              unawaited(s.activate(tab));
                            }
                          },
                          onClose: (tab) {
                            final barId = widget.barIdByTabId[tab.id];
                            if (barId == null) return;
                            unawaited(
                              closeFloatingTab(
                                workbench:
                                    context.read<WorkbenchCubit>(),
                                workspaceId: widget.workspaceId,
                                registry: widget.registry,
                                id: barId,
                                tab: tab,
                                context: context,
                              ),
                            );
                          },
                          onCloseOthers: (tab) {
                            final barId = widget.barIdByTabId[tab.id];
                            if (barId == null) return;
                            unawaited(
                              closeOtherFloatingTabs(
                                workbench:
                                    context.read<WorkbenchCubit>(),
                                workspaceId: widget.workspaceId,
                                registry: widget.registry,
                                keepId: barId,
                                context: context,
                              ),
                            );
                          },
                          onCloseRight: (tab) {
                            final barId = widget.barIdByTabId[tab.id];
                            if (barId == null) return;
                            unawaited(
                              closeFloatingTabsToTheRight(
                                workbench:
                                    context.read<WorkbenchCubit>(),
                                workspaceId: widget.workspaceId,
                                registry: widget.registry,
                                fromId: barId,
                                context: context,
                              ),
                            );
                          },
                          onCloseAll: () {
                            unawaited(
                              closeAllFloatingTabs(
                                workbench:
                                    context.read<WorkbenchCubit>(),
                                workspaceId: widget.workspaceId,
                                registry: widget.registry,
                                context: context,
                              ),
                            );
                          },
                          onReorder: (oldIndex, newIndex) {
                            context.read<WorkbenchCubit>().reorderFloating(
                              widget.workspaceId,
                              oldIndex,
                              newIndex,
                            );
                          },
                        ),
                      ),
                      Expanded(
                        child: RepaintBoundary(
                          child: _FloatingPanelBodySlot(
                            tabs: tabs,
                            activeTabId: activeId,
                            registry: widget.registry,
                            empty: FloatingWorkspaceEmpty(
                              autofocus: tabs.isEmpty,
                              rows: _emptyRows(context),
                              onActivate: (id) => _onEmptyActivate(context, id),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.allowEdgeResize) ..._resizeHandles(),
                ],
              ),
            ),
          ),
        ),
      ],
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
        icon: Icons.horizontal_rule,
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
    if (id == CommandIds.floatingNewTerminal) {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null && box.hasSize
          ? box.localToGlobal(box.size.center(Offset.zero))
          : Offset.zero;
      unawaited(
        showFloatingNewTerminalMenu(context: context, globalPosition: origin),
      );
      return;
    }
    context.read<CommandBus>().invoke(id);
  }

  void _onDragStart(DragStartDetails details) {
    if (widget.state.isMaximized) {
      final size = floatingPanelRestoreSize(widget.state, widget.hostSize);
      final panelBox = context.findRenderObject() as RenderBox?;
      final Offset hostLocal;
      if (panelBox != null && panelBox.hasSize) {
        final inPanel = panelBox.globalToLocal(details.globalPosition);
        hostLocal = Offset(
          widget.panelBounds.left + inPanel.dx,
          widget.panelBounds.top + inPanel.dy,
        );
      } else {
        hostLocal = details.globalPosition;
      }
      final restored = restoreFloatingPanelBoundsFromMaximize(
        maxRect: widget.panelBounds,
        hostSize: widget.hostSize,
        hostLocalPointer: hostLocal,
        restoredWidth: size.width,
        restoredHeight: size.height,
      );
      _dragStartPointer = details.globalPosition;
      _dragStartBounds = restored;
      widget.onGestureBegin(restored);
      context.read<FloatingWorkspaceCubit>().setMaximized(false);
      return;
    }

    _dragStartPointer = details.globalPosition;
    _dragStartBounds = widget.panelBounds;
    widget.onGestureBegin(widget.panelBounds);
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final start = _dragStartBounds;
    final pointer = _dragStartPointer;
    if (start == null || pointer == null) return;
    final delta = details.globalPosition - pointer;
    widget.onGestureUpdate(
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
    widget.onGestureEnd(widget.panelBounds);
    _dragStartPointer = null;
    _dragStartBounds = null;
  }

  List<Widget> _resizeHandles() {
    return [
      for (final edge in _ResizeEdge.values)
        _ResizeHandle(
          edge: edge,
          onStart: (details) {
            _activeResizeEdge = edge;
            _resizeStartPointer = details.globalPosition;
            _resizeStartBounds = widget.panelBounds;
            FloatingTerminalPtyHoldScope.maybeOf(context)?.beginPtyHold();
            widget.onGestureBegin(widget.panelBounds);
          },
          onUpdate: (details) => _applyResize(edge, details.globalPosition),
          onEnd: (_) {
            FloatingTerminalPtyHoldScope.maybeOf(
              context,
            )?.endPtyHold(flush: true);
            widget.onGestureEnd(widget.panelBounds);
            _activeResizeEdge = null;
            _resizeStartPointer = null;
            _resizeStartBounds = null;
          },
        ),
    ];
  }

  void _applyResize(_ResizeEdge edge, Offset globalPosition) {
    final startBounds = _resizeStartBounds;
    final startPointer = _resizeStartPointer;
    if (startBounds == null || startPointer == null) return;
    if (_activeResizeEdge != edge) return;

    final delta = globalPosition - startPointer;
    var left = startBounds.left;
    var top = startBounds.top;
    var right = startBounds.right;
    var bottom = startBounds.bottom;

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

    widget.onGestureUpdate(
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
    required this.onOpenFile,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onDoubleTap,
  });

  final Widget tabBar;
  final VoidCallback onOpenFile;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: SizedBox(
        height: _kTitleBarHeight,
        child: Stack(
          children: [
            // Full-bleed drag / double-tap; tabs + chrome sit above and win hits.
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: GestureDetector(
                  key: const Key('floating_workspace_title_drag'),
                  behavior: HitTestBehavior.opaque,
                  onPanStart: onPanStart,
                  onPanUpdate: onPanUpdate,
                  onPanEnd: onPanEnd,
                  onDoubleTap: onDoubleTap,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            // Orca-style: [shrink-wrap tabs | + | empty drag | chrome].
            // "+" is outside the scroll viewport; when tabs fit it follows the
            // last tab, when they overflow the strip hits max width and scrolls.
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        fit: FlexFit.loose,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: 1,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 0),
                            child: tabBar,
                          ),
                        ),
                      ),
                      FloatingWorkspaceAddButton(onOpenFile: onOpenFile),
                    ],
                  ),
                ),
                // Keep a drag affordance between "+" and window chrome.
                const IgnorePointer(child: SizedBox(width: 28)),
                const FloatingWorkspaceChrome(),
                const SizedBox(width: 4),
              ],
            ),
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
  const _ResizeHandle({
    required this.edge,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final _ResizeEdge edge;
  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;

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
          onPanStart: onStart,
          onPanUpdate: onUpdate,
          onPanEnd: onEnd,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Empty launcher or tab bodies (not both — avoid rebuild Empty on ensureTab).
class _FloatingPanelBodySlot extends StatelessWidget {
  const _FloatingPanelBodySlot({
    required this.tabs,
    required this.activeTabId,
    required this.registry,
    required this.empty,
  });

  final List<FloatingTab> tabs;
  final String? activeTabId;
  final FloatingSurfaceRegistry registry;
  final Widget empty;

  @override
  Widget build(BuildContext context) {
    if (tabs.isEmpty) return empty;
    return _FloatingTabBodyStack(
      tabs: tabs,
      activeTabId: activeTabId,
      registry: registry,
    );
  }
}

/// Keeps every open floating tab mounted; inactive tabs skip layout/paint.
///
/// Avoids disposing the previous surface on tab change (e.g. file → terminal).
/// Not sufficient alone: first terminal open still janks with no prior file.
/// Mirror [HomeWorkspaceBodyStack] keep-alive.
class _FloatingTabBodyStack extends StatelessWidget {
  const _FloatingTabBodyStack({
    required this.tabs,
    required this.activeTabId,
    required this.registry,
  });

  final List<FloatingTab> tabs;
  final String? activeTabId;
  final FloatingSurfaceRegistry registry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        for (final tab in tabs)
          TpKeepAliveLayer(
            key: ValueKey(tab.id),
            active: tab.id == activeTabId,
            child: ExcludeSemantics(
              excluding: tab.id != activeTabId,
              child: TickerMode(
                enabled: tab.id == activeTabId,
                child: IgnorePointer(
                  ignoring: tab.id != activeTabId,
                  child: TpDeferredForegroundMount(
                    active: tab.id == activeTabId,
                    retainWhenInactive: true,
                    placeholder: ColoredBox(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    builder: (context) => _buildTabBody(context, tab),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTabBody(BuildContext context, FloatingTab tab) {
    final surface = registry[tab.surfaceId];
    if (surface == null) return const SizedBox.shrink();
    return surface.build(context, tab);
  }
}
