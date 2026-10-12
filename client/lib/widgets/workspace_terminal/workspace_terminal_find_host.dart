import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../l10n/l10n_extensions.dart';
import '../terminal_find_bar.dart';

/// Overlay find bar + shortcuts for one workspace-terminal session.
class WorkspaceTerminalFindHost extends StatefulWidget {
  const WorkspaceTerminalFindHost({
    required this.engine,
    required this.controller,
    required this.activeEntryId,
    required this.child,
    super.key,
  });

  final TerminalEngine engine;
  final TerminalController controller;
  final String activeEntryId;
  final Widget child;

  @override
  State<WorkspaceTerminalFindHost> createState() =>
      WorkspaceTerminalFindHostState();
}

class WorkspaceTerminalFindHostState extends State<WorkspaceTerminalFindHost> {
  var _findVisible = false;

  bool get findVisible => _findVisible;

  void openFind() {
    if (_findVisible) return;
    setState(() => _findVisible = true);
  }

  void _closeFind({required TerminalController controller}) {
    controller.searchClear();
    if (!_findVisible) return;
    setState(() => _findVisible = false);
  }

  /// The owning registry may dispose a closed entry's controller before this
  /// host sees the swap; clearing a disposed controller must not throw.
  static void _clearSearchSafely(TerminalController controller) {
    try {
      controller.searchClear();
    } catch (_) {}
  }

  @override
  void didUpdateWidget(WorkspaceTerminalFindHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final entryChanged = oldWidget.activeEntryId != widget.activeEntryId;
    final controllerChanged = oldWidget.controller != widget.controller;
    if (entryChanged || controllerChanged) {
      _clearSearchSafely(oldWidget.controller);
      _findVisible = false;
    }
  }

  @override
  void dispose() {
    _clearSearchSafely(widget.controller);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TerminalFindShortcuts(
      findVisible: _findVisible,
      onToggleFind: openFind,
      onFindNext: () {
        widget.controller.searchNext();
        setState(() {});
      },
      onFindPrevious: () {
        widget.controller.searchPrev();
        setState(() {});
      },
      onCloseFind: () => _closeFind(controller: widget.controller),
      child: Stack(
        children: [
          widget.child,
          if (_findVisible)
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: TerminalFindBar(
                engine: widget.engine,
                controller: widget.controller,
                searchLabel: context.l10n.terminalFind,
                noResultsLabel: context.l10n.terminalFindNoResults,
                onClose: () => _closeFind(controller: widget.controller),
              ),
            ),
        ],
      ),
    );
  }
}
