import 'package:flutter/widgets.dart';

import '../../services/session/session_history_pagination.dart';

/// Rebuilds [builder] only when [resolveSessionHistoryColumnWidth] changes.
///
/// Parent [LayoutBuilder]s often re-fire while the stepped column width is
/// unchanged (pane chrome, sibling layout). Skipping those ticks avoids
/// rewriting history [Theme] / markdown tokens for free.
class PinnedSessionHistoryColumnWidth extends StatefulWidget {
  const PinnedSessionHistoryColumnWidth({
    required this.availableWidth,
    required this.builder,
    super.key,
  });

  final double availableWidth;
  final Widget Function(BuildContext context, double columnWidth) builder;

  @override
  State<PinnedSessionHistoryColumnWidth> createState() =>
      _PinnedSessionHistoryColumnWidthState();
}

class _PinnedSessionHistoryColumnWidthState
    extends State<PinnedSessionHistoryColumnWidth> {
  double? _columnWidth;
  Widget? _child;

  @override
  Widget build(BuildContext context) {
    final next = resolveSessionHistoryColumnWidth(widget.availableWidth);
    if (_columnWidth == next && _child != null) {
      return _child!;
    }
    _columnWidth = next;
    _child = widget.builder(context, next);
    return _child!;
  }
}
