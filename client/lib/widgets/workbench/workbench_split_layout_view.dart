// lib/widgets/workbench/workbench_split_layout_view.dart
//
// Shared recursive renderer for the workbench split-group layout. Renders a
// [WorkbenchGroupLayout] binary tree: branch nodes become Row/Column splits
// with draggable dividers, leaf nodes host one group pane built by
// [SplitGroupBuilder]. Both the center workbench and the floating panel embed
// this view with their own builders; group chrome (tab strip header)
// belongs to the callers.
//
// Rendering contract:
// - `maximizedGroupId != null && splitEnabled` → only that group renders,
//   full-size, still via [SplitGroupBuilder].
// - `!splitEnabled` → only the focused group (or `focusedGroupIdOverride`)
//   renders; no dividers.
// - Divider drags update a local [ValueNotifier] for the live preview and
//   fire `onResizeCommit(path, fraction)` exactly once on drag end, where
//   `path` is the resized branch's root-down sequence of second(=true) /
//   first(=false) choices. PTY resizes are bracketed around the gesture via
//   [WorkspaceTerminalHoldHandle].
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../cubits/workbench/tab_strip.dart';
import '../../cubits/workbench/workbench_split_layout.dart';
import '../workspace_terminal_panel.dart';

/// Builds the pane content of one group leaf (header + body chrome included).
typedef SplitGroupBuilder =
    Widget Function(BuildContext context, String groupId, TabStrip strip);

/// Key of the divider gesture handle for the branch at [path] (the sequence
/// of second(=true)/first(=false) choices from the root; empty = root).
Key workbenchSplitDividerKey(List<bool> path) =>
    ValueKey<String>('workbench-split-divider-${_pathKeyOf(path)}');

/// Visual divider thickness. Matches `ResizableSplitView.dividerThickness`
/// (1px line tracking `colorScheme.outlineVariant`).
const double _kDividerVisualThickness = 1;

/// Total hit-test extent of the divider handle (centered on the visual line,
/// wider than it) so the 1px line stays grabbable.
const double _kDividerHitExtent = 12;

String _pathKeyOf(List<bool> path) =>
    path.map((isSecond) => isSecond ? '1' : '0').join();

/// Recursive renderer for [WorkbenchGroupLayout]. See the library comment for
/// the rendering contract; the root [State] owns the divider drag state
/// machine (start → live notifier updates → single commit on end).
class WorkbenchSplitLayoutView extends StatefulWidget {
  const WorkbenchSplitLayoutView({
    required this.layout,
    required this.groupBuilder,
    this.holdHandle,
    this.splitEnabled = true,
    this.onResizeCommit,
    this.onGroupFocused,
    this.onDividerDoubleTap,
    this.minGroupExtent = 240,
    this.focusedGroupIdOverride,
    this.onPtyHoldBegin,
    this.onPtyHoldEnd,
    super.key,
  });

  final WorkbenchGroupLayout layout;

  /// Builds one group's pane. Called once per visible leaf.
  final SplitGroupBuilder groupBuilder;

  /// Bracket PTY resizes of embedded terminals while a divider is dragged.
  final WorkspaceTerminalHoldHandle? holdHandle;

  /// When false, only the focused group renders (narrow mode).
  final bool splitEnabled;

  /// Fired exactly once per divider drag, on drag end. The list carries the
  /// resized branch's path (root-down; `true` = second child) and final
  /// fraction FIRST, then one entry per nested branch whose far pane was
  /// pinned during the drag (see [_SplitDragSession.secondPixelsByPath]) —
  /// converted to a fraction — so the committed layout reproduces the
  /// drag-end pixel geometry.
  final void Function(
    List<(List<bool> path, double fraction)> commits,
  )?
  onResizeCommit;

  /// Fired when a group pane is tapped (translucent — inner content still
  /// receives taps).
  final void Function(String groupId)? onGroupFocused;

  /// Fired when a divider is double-tapped; the caller resolves the
  /// focused/maximized target and dispatches `toggleMaximizeGroup`.
  final VoidCallback? onDividerDoubleTap;

  /// Minimum main-axis extent each side of a branch keeps during a drag.
  final double minGroupExtent;

  /// When set (and alive), wins over [WorkbenchGroupLayout.focusedGroupId]
  /// in `!splitEnabled` mode.
  final String? focusedGroupIdOverride;

  /// Overrides the drag-start hold bracket (defaults to
  /// `holdHandle?.beginPtyHold()`). Injectable for tests.
  final VoidCallback? onPtyHoldBegin;

  /// Overrides the drag-end hold bracket (defaults to
  /// `holdHandle?.endPtyHold(flush: true)`). Injectable for tests.
  final VoidCallback? onPtyHoldEnd;

  @override
  State<WorkbenchSplitLayoutView> createState() =>
      _WorkbenchSplitLayoutViewState();
}

class _WorkbenchSplitLayoutViewState extends State<WorkbenchSplitLayoutView> {
  /// Active drag; null when idle. Branches rebuild off this notifier so drag
  /// updates never touch the rest of the tree.
  final ValueNotifier<_SplitDragSession?> _drag =
      ValueNotifier<_SplitDragSession?>(null);

  /// Main-axis extent of each branch from its most recent layout pass, keyed
  /// by path key. Feeds the min-extent clamp during drags (LayoutBuilder is
  /// allowed here: this view sits above pane content, not inside a panes
  /// `paneBuilder`).
  final Map<String, double> _branchExtents = <String, double>{};

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _beginDrag(List<bool> path, double startFraction) {
    _drag.value = _SplitDragSession(
      path: path,
      startFraction: startFraction,
      fraction: startFraction,
      secondPixelsByPath: _snapshotSecondPixels(path),
    );
    (widget.onPtyHoldBegin ?? _holdBeginDefault)();
  }

  /// Absolute drag-start content pixels of the SECOND side of every branch
  /// strictly below [dragPath] on the dragged divider's second subtree. Those
  /// branches stay pinned to these pixels during the drag: the pane directly
  /// adjacent to the divider absorbs the delta, farther panes don't move.
  Map<String, double> _snapshotSecondPixels(List<bool> dragPath) {
    final pins = <String, double>{};
    var node = widget.layout.root;
    var matched = true;
    for (final isSecond in dragPath) {
      if (node is! SplitBranch) {
        matched = false;
        break;
      }
      node = isSecond ? node.second : node.first;
    }
    if (!matched || node is! SplitBranch) return pins;
    // Walk the dragged branch's SECOND subtree: the divider's far side.
    void walk(SplitNode n, List<bool> subPath) {
      if (n is! SplitBranch) return;
      final key = _pathKeyOf([...dragPath, true, ...subPath]);
      final extent = _branchExtents[key];
      if (extent != null && extent > _kDividerVisualThickness) {
        final content = extent - _kDividerVisualThickness;
        pins[key] = n.firstFraction * content;
      }
      walk(n.first, [...subPath, false]);
      walk(n.second, [...subPath, true]);
    }

    walk(node.second, const <bool>[]);
    return pins;
  }

  void _holdBeginDefault() => widget.holdHandle?.beginPtyHold();

  void _holdEndDefault() => widget.holdHandle?.endPtyHold(flush: true);

  void _updateDrag(String pathKey, double delta) {
    final session = _drag.value;
    if (session == null || session.pathKey != pathKey) return;
    final extent = _branchExtents[pathKey];
    if (extent == null || !(extent > _kDividerVisualThickness)) return;
    final content = extent - _kDividerVisualThickness;
    // Each side keeps minGroupExtent of the branch's current extent; a host
    // too small to honor that collapses to an even split.
    final minFraction = (widget.minGroupExtent / content)
        .clamp(0.0, 0.5)
        .toDouble();
    final maxFraction = 1.0 - minFraction;
    final nextDelta = session.delta + delta;
    final firstExtent = session.startFraction * content + nextDelta;
    _drag.value = session.copyWith(
      delta: nextDelta,
      fraction: (firstExtent / content)
          .clamp(minFraction, maxFraction)
          .toDouble(),
    );
  }

  void _endDrag(String pathKey) {
    final session = _drag.value;
    if (session == null || session.pathKey != pathKey) return;
    _drag.value = null;
    final commits = <(List<bool>, double)>[
      (List<bool>.of(session.path), session.fraction),
    ];
    // Convert each pin (absolute second-side pixels) into the fraction that
    // reproduces it under the drag-end allocation: a pinned branch's parent
    // chain has known post-drag extents derivable from the session fraction
    // and the branch extents captured before the drag.
    for (final entry in session.secondPixelsByPath.entries) {
      final pinnedPath = _pathOf(entry.key);
      // The pinned branch's own content total after the drag:
      // parent chain allocations scaled by the dragged branch's fraction.
      final branchPath = [...session.path, true];
      // Compute this branch's post-drag content extent by walking from the
      // dragged branch's second side using current layout fractions.
      var extent = _branchExtents[pathKey];
      if (extent == null) continue;
      var content = extent - _kDividerVisualThickness;
      var secondTotal = content * (1 - session.fraction);
      // Descend from the dragged branch's second child to the pinned branch.
      var node = widget.layout.root;
      for (final isSecond in session.path) {
        if (node is! SplitBranch) break;
        node = isSecond ? node.second : node.first;
      }
      if (node is! SplitBranch) continue;
      var current = node.second;
      var remaining = pinnedPath.sublist(branchPath.length);
      var ok = true;
      for (final isSecond in remaining) {
        if (current is! SplitBranch) {
          ok = false;
          break;
        }
        final branchContent = secondTotal - _kDividerVisualThickness;
        if (branchContent <= 0) {
          ok = false;
          break;
        }
        final nextShare = isSecond
            ? 1 - current.firstFraction
            : current.firstFraction;
        secondTotal = (branchContent * nextShare).clamp(
          0.0,
          double.infinity,
        );
        current = isSecond ? current.second : current.first;
      }
      if (!ok || current is! SplitBranch) continue;
      final pinnedContent = secondTotal - _kDividerVisualThickness;
      if (pinnedContent <= 0) continue;
      commits.add((pinnedPath, 1 - entry.value / pinnedContent));
    }
    widget.onResizeCommit?.call(commits);
    (widget.onPtyHoldEnd ?? _holdEndDefault)();
  }

  /// Parses a path key ("010") back into its path.
  List<bool> _pathOf(String key) => [
    for (final ch in key.split(''))
      if (ch == '1') true else if (ch == '0') false,
  ];

  void _cancelDrag(String pathKey) {
    final session = _drag.value;
    if (session == null || session.pathKey != pathKey) return;
    _drag.value = null;
    (widget.onPtyHoldEnd ?? _holdEndDefault)();
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.layout;
    if (!widget.splitEnabled) {
      return _buildLeaf(_resolveSoleGroupId());
    }
    final maximized = layout.maximizedGroupId;
    if (maximized != null && layout.groups.containsKey(maximized)) {
      return _buildLeaf(maximized);
    }
    return _buildNode(layout.root, const <bool>[]);
  }

  /// The group that renders alone in `!splitEnabled` mode: the override when
  /// it names a live group, else the focused group, else the leftmost leaf.
  String _resolveSoleGroupId() {
    final groups = widget.layout.groups;
    final override = widget.focusedGroupIdOverride;
    if (override != null && groups.containsKey(override)) return override;
    final focused = widget.layout.focusedGroupId;
    if (groups.containsKey(focused)) return focused;
    return widget.layout.leafGroupIds.first;
  }

  Widget _buildLeaf(String groupId) => _LeafView(
    key: ValueKey('split-leaf-$groupId'),
    groupId: groupId,
    strip: widget.layout.groups[groupId] ?? const TabStrip(),
    groupBuilder: widget.groupBuilder,
    onGroupFocused: widget.onGroupFocused,
  );

  Widget _buildNode(SplitNode node, List<bool> path) => switch (node) {
    SplitLeaf() => _buildLeaf(node.groupId),
    SplitBranch() => _BranchView(
      branch: node,
      path: path,
      dragListenable: _drag,
      buildChild: _buildNode,
      minGroupExtent: widget.minGroupExtent,
      onExtentChanged: (extent) => _branchExtents[_pathKeyOf(path)] = extent,
      onDividerPanStart: () => _beginDrag(path, node.firstFraction),
      onDividerPanUpdate: (delta) => _updateDrag(_pathKeyOf(path), delta),
      onDividerPanEnd: () => _endDrag(_pathKeyOf(path)),
      onDividerPanCancel: () => _cancelDrag(_pathKeyOf(path)),
      onDividerDoubleTap: widget.onDividerDoubleTap,
    ),
  };
}

/// Immutable snapshot of an in-flight divider drag. [delta] accumulates
/// pointer movement along the branch axis; [fraction] is the clamped live
/// first-child share. [secondPixelsByPath] pins ABSOLUTE content pixels for
/// the second side of nested branches during the drag: the pane adjacent to
/// the dragged divider absorbs the whole delta and the far side stays at its
/// drag-start width (VSCode behavior) instead of every pane below resizing
/// proportionally.
@immutable
class _SplitDragSession {
  const _SplitDragSession({
    required this.path,
    required this.startFraction,
    required this.fraction,
    this.delta = 0,
    this.secondPixelsByPath = const {},
  });

  final List<bool> path;
  final double startFraction;
  final double fraction;
  final double delta;
  final Map<String, double> secondPixelsByPath;

  String get pathKey => _pathKeyOf(path);

  _SplitDragSession copyWith({
    double? fraction,
    double? delta,
    Map<String, double>? secondPixelsByPath,
  }) => _SplitDragSession(
    path: path,
    startFraction: startFraction,
    fraction: fraction ?? this.fraction,
    delta: delta ?? this.delta,
    secondPixelsByPath: secondPixelsByPath ?? this.secondPixelsByPath,
  );
}

/// One interior split: recursive first/second panes with a divider between.
///
/// [LayoutBuilder] captures the branch's main-axis extent (reported upward for
/// the min-extent clamp); the panes are laid out by the *live* fraction while
/// this branch is the drag target, else by [SplitBranch.firstFraction]. The
/// [ValueListenableBuilder.child] keeps non-dragged branches untouched.
class _BranchView extends StatelessWidget {
  const _BranchView({
    required this.branch,
    required this.path,
    required this.dragListenable,
    required this.buildChild,
    required this.onExtentChanged,
    required this.onDividerPanStart,
    required this.onDividerPanUpdate,
    required this.onDividerPanEnd,
    required this.onDividerPanCancel,
    required this.onDividerDoubleTap,
    required this.minGroupExtent,
  });

  final SplitBranch branch;
  final List<bool> path;
  final ValueListenable<_SplitDragSession?> dragListenable;
  final Widget Function(SplitNode node, List<bool> path) buildChild;
  final double minGroupExtent;
  final ValueChanged<double> onExtentChanged;
  final VoidCallback onDividerPanStart;
  final ValueChanged<double> onDividerPanUpdate;
  final VoidCallback onDividerPanEnd;
  final VoidCallback onDividerPanCancel;
  final VoidCallback? onDividerDoubleTap;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = branch.axis == Axis.horizontal;
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = isHorizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        if (!extent.isFinite || !(extent > _kDividerVisualThickness)) {
          // Unbounded / degenerate host: even split, no drag math.
          final children = [
            buildChild(branch.first, [...path, false]),
            _visualDivider(context),
            buildChild(branch.second, [...path, true]),
          ];
          return isHorizontal
              ? Row(mainAxisSize: MainAxisSize.min, children: children)
              : Column(mainAxisSize: MainAxisSize.min, children: children);
        }
        onExtentChanged(extent);
        return ValueListenableBuilder<_SplitDragSession?>(
          valueListenable: dragListenable,
          child: _panes(context, branch.firstFraction, extent),
          builder: (context, session, staticPanes) {
            if (session == null) return staticPanes!;
            if (session.pathKey != _pathKeyOf(path)) {
              // This branch is BELOW the dragged divider (its subtree may be
              // receiving a shrunken/grown allocation): pin the second side
              // to its drag-start pixels so the far pane absorbs nothing.
              final pinned = session.secondPixelsByPath[_pathKeyOf(path)];
              if (pinned != null) {
                return _panes(
                  context,
                  branch.firstFraction,
                  extent,
                  pinnedSecondPixels: pinned,
                );
              }
              return staticPanes!;
            }
            return _panes(context, session.fraction, extent);
          },
        );
      },
    );
  }

  Widget _panes(
    BuildContext context,
    double fraction,
    double extent, {
    double? pinnedSecondPixels,
  }) {
    final isHorizontal = branch.axis == Axis.horizontal;
    final content = extent - _kDividerVisualThickness;
    // Pinned drag layout: the second side keeps its drag-start pixels (the
    // far pane stays fixed) and the first side takes the remainder — it
    // absorbs the whole delta. minGroupExtent clamps the remainder from
    // below (the pin yields when the first pane would go under it).
    final pinned = pinnedSecondPixels;
    final firstExtent = pinned == null
        ? fraction.clamp(0.0, 1.0).toDouble() * content
        : (extent - _kDividerVisualThickness - pinned)
              .clamp(minGroupExtent, double.infinity)
              .toDouble();
    final second = pinned == null
        ? Expanded(child: buildChild(branch.second, [...path, true]))
        : SizedBox(
            width: isHorizontal ? pinned : null,
            height: isHorizontal ? null : pinned,
            child: buildChild(branch.second, [...path, true]),
          );
    final panes = [
      SizedBox(
        width: isHorizontal ? firstExtent : null,
        height: isHorizontal ? null : firstExtent,
        child: buildChild(branch.first, [...path, false]),
      ),
      _visualDivider(context),
      second,
    ];
    final flex = isHorizontal
        ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: panes)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: panes,
          );
    // Hit area centered on the divider, wider than the 1px visual line, above
    // the panes so divider gestures win over pane content. Clamped into the
    // stack bounds (Positioned rejects negative offsets) so extreme fractions
    // stay grabbable.
    final hitStart =
        (firstExtent + _kDividerVisualThickness / 2 - _kDividerHitExtent / 2)
            .clamp(0.0, (extent - _kDividerHitExtent).clamp(0.0, extent))
            .toDouble();
    final handle = Positioned(
      left: isHorizontal ? hitStart : 0,
      right: isHorizontal ? null : 0,
      top: isHorizontal ? 0 : hitStart,
      bottom: isHorizontal ? 0 : null,
      width: isHorizontal ? _kDividerHitExtent : null,
      height: isHorizontal ? null : _kDividerHitExtent,
      child: _Divider(
        key: workbenchSplitDividerKey(path),
        axis: branch.axis,
        onPanStart: onDividerPanStart,
        onPanUpdate: onDividerPanUpdate,
        onPanEnd: onDividerPanEnd,
        onPanCancel: onDividerPanCancel,
        onDoubleTap: onDividerDoubleTap,
      ),
    );
    return Stack(fit: StackFit.passthrough, children: [flex, handle]);
  }

  Widget _visualDivider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    // outlineVariant tracks the active palette; alpha follows
    // ResizableSplitView so the line reads on light and dark panes.
    final color = cs.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.6);
    return branch.axis == Axis.horizontal
        ? SizedBox(
            width: _kDividerVisualThickness,
            child: ColoredBox(color: color),
          )
        : SizedBox(
            height: _kDividerVisualThickness,
            child: ColoredBox(color: color),
          );
  }
}

/// Divider hit strip: resize cursor per axis + pan/double-tap gestures.
class _Divider extends StatelessWidget {
  const _Divider({
    required this.axis,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
    required this.onDoubleTap,
    super.key,
  });

  final Axis axis;
  final VoidCallback onPanStart;

  /// Called with movement along [axis] since the previous update.
  final ValueChanged<double> onPanUpdate;
  final VoidCallback onPanEnd;
  final VoidCallback onPanCancel;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final isHorizontal = axis == Axis.horizontal;
    return MouseRegion(
      cursor: isHorizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => onPanStart(),
        onPanUpdate: (details) =>
            onPanUpdate(isHorizontal ? details.delta.dx : details.delta.dy),
        onPanEnd: (_) => onPanEnd(),
        onPanCancel: onPanCancel,
        onDoubleTap: onDoubleTap,
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// One group leaf: pointer-down-to-focus around the caller's pane. Keyed by
/// group id so split edits reuse (rather than displace) the pane elements.
class _LeafView extends StatelessWidget {
  const _LeafView({
    super.key,
    required this.groupId,
    required this.strip,
    required this.groupBuilder,
    this.onGroupFocused,
  });

  final String groupId;
  final TabStrip strip;
  final SplitGroupBuilder groupBuilder;
  final void Function(String groupId)? onGroupFocused;

  @override
  Widget build(BuildContext context) {
    // A Listener (not a GestureDetector): pane content — terminals, chat
    // scroll views, editors — carries its own competing recognizers that
    // win the gesture arena, so a translucent onTap would never fire over
    // real content. Raw pointer-down focuses without entering the arena;
    // content keeps every gesture.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: onGroupFocused == null
          ? null
          : (_) => onGroupFocused!(groupId),
      child: ClipRect(
        child: KeyedSubtree(
          key: ValueKey('split-pane-$groupId'),
          child: groupBuilder(context, groupId, strip),
        ),
      ),
    );
  }
}

/// Focus highlight overlay shared by group chrome hosts (Tasks 5/6): a 2px
/// border in `colorScheme.primary` when [focused], nothing otherwise. The
/// overlay ignores pointer events so pane content stays interactive.
