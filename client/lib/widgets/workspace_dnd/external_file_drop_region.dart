import 'dart:io' show Platform;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../services/workspace_dnd/path_namespace.dart';
import '../../services/workspace_dnd/workspace_drop_target.dart';
import '../../services/workspace_dnd/workspace_file_ref.dart';

/// Receives files dragged in from the OS (Finder/Explorer/Files) and feeds them
/// to a [WorkspaceDropTarget] — the *external* drag source, peer to the in-app
/// [DraggableFileRow]. OS drops bypass Flutter's drag system, so this wraps the
/// platform `DropTarget` (desktop_drop) instead of a `DragTarget`, but converts
/// the dropped paths into the same [WorkspaceDragPayload] and reuses the same
/// ingestor — projection, quoting, cross-namespace rejection all apply.
///
/// Desktop-only: on mobile (where TeamPilot runs over SSH) it is a passthrough.
///
/// When [onDropPayload] is non-null, that handler owns ingest and
/// [target.consume] is **not** called (Compose/Terminal keep the default path).
class ExternalFileDropRegion extends StatefulWidget {
  const ExternalFileDropRegion({
    required this.target,
    required this.child,
    this.onOutcome,
    this.onDropPayload,
    this.onDragPositionChanged,
    this.showPanelHighlight = true,
    super.key,
  });

  final WorkspaceDropTarget target;
  final Widget child;
  final ValueChanged<DropOutcome>? onOutcome;

  /// Custom OS-drop handler. When set, skips [WorkspaceDropTarget.consume].
  final Future<void> Function(
    WorkspaceDragPayload payload,
    DropDoneDetails details,
  )?
  onDropPayload;

  /// Local pointer while an OS drag is over this region; `null` on exit/done.
  final ValueChanged<Offset?>? onDragPositionChanged;

  /// Full-region highlight border. Disable when the child paints its own.
  final bool showPanelHighlight;

  static bool get _isDesktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  State<ExternalFileDropRegion> createState() => _ExternalFileDropRegionState();
}

class _ExternalFileDropRegionState extends State<ExternalFileDropRegion> {
  bool _highlighted = false;

  /// OS files live on the host the app runs on, so their namespace is the local
  /// machine regardless of the storage backend. A drop on a remote terminal is
  /// then correctly seen as cross-namespace and refused.
  static PathNamespace get _hostNamespace => Platform.isWindows
      ? const PathNamespace.localWindows()
      : const PathNamespace.localPosix();

  Future<void> _onDrop(DropDoneDetails detail) async {
    final ns = _hostNamespace;
    final refs = [
      for (final item in detail.files)
        WorkspaceFileRef(
          nativePath: item.path,
          namespace: ns,
          isDirectory: item is DropItemDirectory,
        ),
    ];
    if (_highlighted) setState(() => _highlighted = false);
    widget.onDragPositionChanged?.call(null);
    if (refs.isEmpty) return;
    final payload = WorkspaceDragPayload(
      kind: DragPayloadKind.workspaceFile,
      refs: refs,
    );
    if (!widget.target.accepts(payload.kind)) return;

    final custom = widget.onDropPayload;
    if (custom != null) {
      await custom(payload, detail);
      return;
    }

    final outcome = await widget.target.consume(payload);
    widget.onOutcome?.call(outcome);
  }

  @override
  Widget build(BuildContext context) {
    // Mobile never wraps (constant, no remount churn).
    if (!ExternalFileDropRegion._isDesktop) return widget.child;

    // desktop_drop dispatches one OS drop to *every* mounted DropTarget whose
    // bounds contain the point (Flutter's own DragTarget hit-tests to a single
    // visible target instead). Background workspace tabs are kept alive in an
    // IndexedStack, all laid out at the same rect, so without gating each would
    // fire and the path would be injected once per open tab. The shell marks
    // only the foreground workspace's subtree with TickerMode.enabled, so use
    // that to keep exactly one region listening. The DropTarget always stays in
    // the tree (only `enable` toggles) so the wrapped TerminalView never remounts.
    final enabled = TickerMode.valuesOf(context).enabled;
    final cs = Theme.of(context).colorScheme;
    return DropTarget(
      enable: enabled,
      onDragEntered: (details) {
        if (!_highlighted) setState(() => _highlighted = true);
        widget.onDragPositionChanged?.call(details.localPosition);
      },
      onDragUpdated: (details) {
        widget.onDragPositionChanged?.call(details.localPosition);
      },
      onDragExited: (_) {
        if (_highlighted) setState(() => _highlighted = false);
        widget.onDragPositionChanged?.call(null);
      },
      onDragDone: _onDrop,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (enabled && widget.showPanelHighlight && _highlighted)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.primary, width: 2),
                    color: cs.primary.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
