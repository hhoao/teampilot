// lib/widgets/workbench/workbench_tab_drag.dart
//
// Tab drag-and-drop split machinery for the workbench: pure drop-zone math,
// the drag controller + inherited scope, a generic drag source
// ([WorkbenchTabDraggable]), the per-group drop-region overlay
// ([WorkbenchTabDropRegions]), and the zone→cubit dispatch
// ([dispatchSplitDrop]). Tasks 5/6 wire these into the center and floating
// tab bars; this library ships the mechanism only.
//
// Position tracking note: touch pointers keep the hit-test path they had at
// pointer-down, so an overlay Listener that appears only once the drag has
// started would never see touch moves. The drag source's Listener therefore
// records the pointer position into the controller (it is always on the
// down path), and each drop region resolves that global position against its
// own render box. The painted indicator stays purely visual ([IgnorePointer])
// and never participates in hit-testing.
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';

/// Drop zone under the pointer inside a group body: one of the four 20% edge
/// bands, or the center remainder.
///
/// Corner precedence: horizontal edges win — while the pointer is within the
/// left/right 20% band the zone is left/right regardless of y; otherwise the
/// top/bottom bands apply; the remainder is the center.
enum SplitDropZone { right, left, up, down, center }

/// Fraction of the region width/height each edge band occupies.
const double _kDropEdgeBand = 0.2;

/// Computes the drop zone for [local] (region-local pointer offset) within
/// [size] using 20% edge bands. Degenerate sizes resolve to
/// [SplitDropZone.center].
SplitDropZone splitDropZoneForOffset(Offset local, Size size) {
  if (size.width <= 0 || size.height <= 0) return SplitDropZone.center;
  final fx = local.dx / size.width;
  if (fx < _kDropEdgeBand) return SplitDropZone.left;
  if (fx > 1 - _kDropEdgeBand) return SplitDropZone.right;
  final fy = local.dy / size.height;
  if (fy < _kDropEdgeBand) return SplitDropZone.up;
  if (fy > 1 - _kDropEdgeBand) return SplitDropZone.down;
  return SplitDropZone.center;
}

/// Fired when a drag ends over a drop region: [targetGroupId] is the region
/// the pointer was released over and [zone] the computed drop zone.
typedef WorkbenchTabDragDropCallback =
    void Function(String targetGroupId, SplitDropZone zone);

/// Zone → cubit action mapping for a tab drop:
///
/// - [SplitDropZone.center] → `moveTab` into the target group.
/// - edge zones → `splitInto`: the dragged tab moves into a *new* group
///   placed adjacent to the target group (left/right → `Axis.horizontal`,
///   up/down → `Axis.vertical`; left/up = before).
///
/// Dropping onto the tab's own group edge is rejected here — the reducer
/// would otherwise treat it as a source split — so the cubit emits nothing.
void dispatchSplitDrop(
  WorkbenchCubit workbench,
  String workspaceId, {
  required WorkbenchTabId tab,
  required String sourceGroupId,
  required String targetGroupId,
  required SplitDropZone zone,
  bool floating = false,
}) {
  switch (zone) {
    case SplitDropZone.center:
      workbench.moveTab(
        workspaceId,
        tab,
        targetGroupId,
        floating: floating,
      );
    case SplitDropZone.left:
      _dispatchEdge(
        workbench,
        workspaceId,
        tab: tab,
        sourceGroupId: sourceGroupId,
        targetGroupId: targetGroupId,
        axis: Axis.horizontal,
        before: true,
        floating: floating,
      );
    case SplitDropZone.right:
      _dispatchEdge(
        workbench,
        workspaceId,
        tab: tab,
        sourceGroupId: sourceGroupId,
        targetGroupId: targetGroupId,
        axis: Axis.horizontal,
        before: false,
        floating: floating,
      );
    case SplitDropZone.up:
      _dispatchEdge(
        workbench,
        workspaceId,
        tab: tab,
        sourceGroupId: sourceGroupId,
        targetGroupId: targetGroupId,
        axis: Axis.vertical,
        before: true,
        floating: floating,
      );
    case SplitDropZone.down:
      _dispatchEdge(
        workbench,
        workspaceId,
        tab: tab,
        sourceGroupId: sourceGroupId,
        targetGroupId: targetGroupId,
        axis: Axis.vertical,
        before: false,
        floating: floating,
      );
  }
}

void _dispatchEdge(
  WorkbenchCubit workbench,
  String workspaceId, {
  required WorkbenchTabId tab,
  required String sourceGroupId,
  required String targetGroupId,
  required Axis axis,
  required bool before,
  required bool floating,
}) {
  if (sourceGroupId == targetGroupId) return;
  workbench.splitInto(
    workspaceId,
    tab,
    targetGroupId,
    axis: axis,
    before: before,
    floating: floating,
  );
}

/// One registered drop target. [zoneAt] maps a global pointer position to
/// the drop zone it lands in within the region, or null when the position is
/// outside it.
class WorkbenchDropRegionHandle {
  const WorkbenchDropRegionHandle({required this.groupId, required this.zoneAt});

  final String groupId;
  final SplitDropZone? Function(Offset globalPosition) zoneAt;
}

/// Owns the in-flight tab drag: the dragged tab / its source group, the
/// drop callback supplied at drag start, the last known global pointer
/// position, and the registered drop regions.
///
/// Mounted once by the host page (Tasks 5/6) — directly or via
/// [WorkbenchTabDragHost] — above the split view; tab bars reach it through
/// [WorkbenchTabDragScope]. Only one drag may be active at a time; [begin]
/// is ignored while a drag is active.
class WorkbenchTabDragController extends ChangeNotifier {
  WorkbenchTabId? _draggedTab;
  String? _sourceGroupId;
  WorkbenchTabDragDropCallback? _onDrop;
  Offset? _globalPosition;
  final List<WorkbenchDropRegionHandle> _regions =
      <WorkbenchDropRegionHandle>[];

  /// The tab being dragged, or null when idle.
  WorkbenchTabId? get draggedTab => _draggedTab;

  /// The group the drag started from, or null when idle.
  String? get sourceGroupId => _sourceGroupId;

  /// The drop callback supplied to [begin], or null when idle.
  WorkbenchTabDragDropCallback? get onDrop => _onDrop;

  /// Last reported global pointer position during the active drag.
  Offset? get globalPosition => _globalPosition;

  /// Whether a drag is in flight.
  bool get isActive => _draggedTab != null;

  /// Begins a drag. Ignored when a drag is already active.
  void begin({
    required WorkbenchTabId tab,
    required String sourceGroupId,
    required WorkbenchTabDragDropCallback onDrop,
  }) {
    if (isActive) return;
    _draggedTab = tab;
    _sourceGroupId = sourceGroupId;
    _onDrop = onDrop;
    _globalPosition = null;
    notifyListeners();
  }

  /// Records the dragged pointer's global [position]. Ignored while idle.
  void updatePosition(Offset position) {
    if (!isActive) return;
    _globalPosition = position;
    notifyListeners();
  }

  /// Ends the drag. When [globalPosition] is given (pointer released), the
  /// registered region under the pointer computes its zone and receives
  /// [onDrop]; without a position (cancel) no drop fires. Idempotent.
  void end({Offset? globalPosition}) {
    if (!isActive) return;
    final drop = _onDrop;
    _draggedTab = null;
    _sourceGroupId = null;
    _onDrop = null;
    _globalPosition = null;
    notifyListeners();
    if (drop == null || globalPosition == null) return;
    // Iterate a copy: the drop callback mutates the tree (cubit emit) and
    // may register/unregister regions re-entrantly.
    for (final region in List<WorkbenchDropRegionHandle>.of(_regions)) {
      final zone = region.zoneAt(globalPosition);
      if (zone != null) {
        drop(region.groupId, zone);
        return;
      }
    }
  }

  /// Registers a drop region (called by [WorkbenchTabDropRegions]).
  void registerRegion(WorkbenchDropRegionHandle handle) =>
      _regions.add(handle);

  /// Unregisters a drop region.
  void unregisterRegion(WorkbenchDropRegionHandle handle) =>
      _regions.remove(handle);
}

/// Provides the [WorkbenchTabDragController] to the split-view subtree.
/// Drag state reads go through the convenience getters; widgets that must
/// rebuild while the drag evolves should listen to [controller] directly.
class WorkbenchTabDragScope extends InheritedWidget {
  const WorkbenchTabDragScope({
    required this.controller,
    required super.child,
    super.key,
  });

  final WorkbenchTabDragController controller;

  /// The tab being dragged, or null when idle.
  WorkbenchTabId? get draggedTab => controller.draggedTab;

  /// The group the drag started from, or null when idle.
  String? get sourceGroupId => controller.sourceGroupId;

  /// The drop callback of the active drag, or null when idle.
  WorkbenchTabDragDropCallback? get onDrop => controller.onDrop;

  /// Whether a drag is in flight.
  bool get isActive => controller.isActive;

  static WorkbenchTabDragScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WorkbenchTabDragScope>();

  @override
  bool updateShouldNotify(WorkbenchTabDragScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Hosts a [WorkbenchTabDragController] and wraps [child] in a
/// [WorkbenchTabDragScope]. Mount once above the split view (Tasks 5/6).
/// Pass [controller] to share an externally owned instance; otherwise one is
/// created and disposed here.
class WorkbenchTabDragHost extends StatefulWidget {
  const WorkbenchTabDragHost({required this.child, this.controller, super.key});

  final Widget child;
  final WorkbenchTabDragController? controller;

  @override
  State<WorkbenchTabDragHost> createState() => _WorkbenchTabDragHostState();
}

class _WorkbenchTabDragHostState extends State<WorkbenchTabDragHost> {
  WorkbenchTabDragController? _owned;

  WorkbenchTabDragController get _effective =>
      widget.controller ?? (_owned ??= WorkbenchTabDragController());

  @override
  void dispose() {
    _owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      WorkbenchTabDragScope(controller: _effective, child: widget.child);
}

/// Starts a workbench tab drag from [context]: looks up the nearest
/// [WorkbenchTabDragScope] and begins a drag on its controller. Does nothing
/// when no scope is mounted above [context] or a drag is already active.
void beginWorkbenchTabDrag(
  BuildContext context, {
  required WorkbenchTabId tab,
  required String sourceGroupId,
  required WorkbenchTabDragDropCallback onDrop,
}) {
  final scope = WorkbenchTabDragScope.maybeOf(context);
  if (scope == null) return;
  scope.controller.begin(
    tab: tab,
    sourceGroupId: sourceGroupId,
    onDrop: onDrop,
  );
}

/// Wraps one group's pane slot as a drop region. While a workbench tab drag
/// is active, paints the four-edge + center indicator for the zone under the
/// pointer (purely visual — [IgnorePointer]) and resolves the zone on
/// release: the drag controller reports the release position, the region
/// under it computes its zone via [splitDropZoneForOffset], and the drag's
/// `onDrop(groupId, zone)` fires.
class WorkbenchTabDropRegions extends StatefulWidget {
  const WorkbenchTabDropRegions({
    required this.groupId,
    required this.child,
    super.key,
  });

  final String groupId;
  final Widget child;

  @override
  State<WorkbenchTabDropRegions> createState() =>
      _WorkbenchTabDropRegionsState();
}

class _WorkbenchTabDropRegionsState extends State<WorkbenchTabDropRegions> {
  WorkbenchTabDragController? _controller;
  WorkbenchDropRegionHandle? _handle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = WorkbenchTabDragScope.maybeOf(context)?.controller;
    if (identical(controller, _controller)) return;
    _detach();
    _controller = controller;
    if (controller != null) {
      _handle = WorkbenchDropRegionHandle(
        groupId: widget.groupId,
        zoneAt: _zoneAt,
      );
      controller.registerRegion(_handle!);
    }
  }

  @override
  void didUpdateWidget(WorkbenchTabDropRegions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groupId == widget.groupId) return;
    final controller = _controller;
    final handle = _handle;
    if (controller == null || handle == null) return;
    controller.unregisterRegion(handle);
    _handle = WorkbenchDropRegionHandle(
      groupId: widget.groupId,
      zoneAt: _zoneAt,
    );
    controller.registerRegion(_handle!);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    final handle = _handle;
    _handle = null;
    if (handle != null) _controller?.unregisterRegion(handle);
    _controller = null;
  }

  /// The zone a global pointer [position] lands in within this region, or
  /// null when it is outside the region (or the region is not laid out).
  SplitDropZone? _zoneAt(Offset position) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return null;
    }
    final local = renderObject.globalToLocal(position);
    final size = renderObject.size;
    if (local.dx < 0 ||
        local.dy < 0 ||
        local.dx >= size.width ||
        local.dy >= size.height) {
      return null;
    }
    return splitDropZoneForOffset(local, size);
  }

  SplitDropZone? _activeZone(WorkbenchTabDragController controller) {
    final position = controller.globalPosition;
    if (!controller.isActive || position == null) return null;
    return _zoneAt(position);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return widget.child;
    return ListenableBuilder(
      listenable: controller,
      child: widget.child,
      builder: (context, child) {
        final content = child ?? widget.child;
        final zone = _activeZone(controller);
        if (zone == null) return content;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            content,
            Positioned.fill(
              child: IgnorePointer(child: _dropIndicator(context, zone)),
            ),
          ],
        );
      },
    );
  }

  Widget _dropIndicator(BuildContext context, SplitDropZone zone) {
    final accent = Theme.of(context).colorScheme.primary;
    switch (zone) {
      case SplitDropZone.center:
        return DecoratedBox(
          key: const Key('split_drop_indicator_center'),
          decoration: BoxDecoration(color: accent.withValues(alpha: 0.125)),
        );
      case SplitDropZone.right:
        return _edgeIndicator(
          key: const Key('split_drop_indicator_right'),
          accent: accent,
          alignment: Alignment.centerRight,
          insetPadding: const EdgeInsets.only(right: _kDropEdgeInset),
        );
      case SplitDropZone.left:
        return _edgeIndicator(
          key: const Key('split_drop_indicator_left'),
          accent: accent,
          alignment: Alignment.centerLeft,
          insetPadding: const EdgeInsets.only(left: _kDropEdgeInset),
        );
      case SplitDropZone.up:
        return _edgeIndicator(
          key: const Key('split_drop_indicator_up'),
          accent: accent,
          alignment: Alignment.topCenter,
          insetPadding: const EdgeInsets.only(top: _kDropEdgeInset),
          vertical: false,
        );
      case SplitDropZone.down:
        return _edgeIndicator(
          key: const Key('split_drop_indicator_down'),
          accent: accent,
          alignment: Alignment.bottomCenter,
          insetPadding: const EdgeInsets.only(bottom: _kDropEdgeInset),
          vertical: false,
        );
    }
  }

  Widget _edgeIndicator({
    required Key key,
    required Color accent,
    required Alignment alignment,
    required EdgeInsets insetPadding,
    bool vertical = true,
  }) => Align(
    key: key,
    alignment: alignment,
    child: Padding(
      padding: insetPadding,
      child: vertical
          ? SizedBox(
              width: _kDropEdgeWidth,
              child: DecoratedBox(decoration: BoxDecoration(color: accent)),
            )
          : SizedBox(
              height: _kDropEdgeWidth,
              child: DecoratedBox(decoration: BoxDecoration(color: accent)),
            ),
    ),
  );
}

/// Drop-indicator geometry: a 2px accent bar inset from the hovered edge.
const double _kDropEdgeWidth = 2;
const double _kDropEdgeInset = 2;

/// Generic drag source for workbench tabs. Wraps a tab widget and starts a
/// drag on the nearest [WorkbenchTabDragScope]:
///
/// - mouse: the drag begins immediately on pointer-down;
/// - touch/pen: the drag begins on long-press.
///
/// The wrapper's own `Listener` stays on the pointer's down path for the
/// whole gesture, so it feeds the controller position updates (and the
/// release position) regardless of where the pointer travels — including
/// touch pointers, whose hit-test path is locked at pointer-down.
///
/// [onDrop] fires when the drag ends over a drop region with that region's
/// group id and the computed [SplitDropZone]; wire it to
/// [dispatchSplitDrop] at the call site (Tasks 5/6).
class WorkbenchTabDraggable extends StatefulWidget {
  const WorkbenchTabDraggable({
    required this.tab,
    required this.sourceGroupId,
    required this.onDrop,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final WorkbenchTabId tab;
  final String sourceGroupId;
  final WorkbenchTabDragDropCallback onDrop;

  /// When false the wrapper is inert and [child] passes through untouched.
  final bool enabled;

  final Widget child;

  @override
  State<WorkbenchTabDraggable> createState() => _WorkbenchTabDraggableState();
}

class _WorkbenchTabDraggableState extends State<WorkbenchTabDraggable> {
  WorkbenchTabDragController? _controller;
  int? _pointer;

  /// Touch pointer waiting on its long-press (mouse drags begin on down).
  int? _pendingTouchPointer;

  bool get _dragging => _pointer != null;

  void _beginDrag(int pointer) {
    if (!widget.enabled || _dragging) return;
    final scope = WorkbenchTabDragScope.maybeOf(context);
    if (scope == null || scope.controller.isActive) return;
    beginWorkbenchTabDrag(
      context,
      tab: widget.tab,
      sourceGroupId: widget.sourceGroupId,
      onDrop: widget.onDrop,
    );
    _controller = scope.controller;
    _pointer = pointer;
    _pendingTouchPointer = null;
  }

  void _endDrag(Offset? globalPosition) {
    final controller = _controller;
    _controller = null;
    _pointer = null;
    _pendingTouchPointer = null;
    controller?.end(globalPosition: globalPosition);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_dragging) return;
    if (event.kind == PointerDeviceKind.mouse) {
      _beginDrag(event.pointer);
    } else {
      _pendingTouchPointer = event.pointer;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointer == event.pointer) {
      _controller?.updatePosition(event.position);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_pointer == event.pointer) {
      _endDrag(event.position);
    } else if (_pendingTouchPointer == event.pointer) {
      _pendingTouchPointer = null;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_pointer == event.pointer) {
      _endDrag(null);
    } else if (_pendingTouchPointer == event.pointer) {
      _pendingTouchPointer = null;
    }
  }

  @override
  void dispose() {
    // A drag still in flight when the source unmounts ends as a cancel.
    if (_dragging) _endDrag(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: GestureDetector(
        onLongPressStart: (_) {
          final pending = _pendingTouchPointer;
          if (pending != null) _beginDrag(pending);
        },
        child: widget.child,
      ),
    );
  }
}
