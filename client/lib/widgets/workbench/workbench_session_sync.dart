import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/workbench/workbench_cubit.dart';

/// Keeps [WorkbenchCubit] session tabs aligned with chat session ids / selection.
class WorkbenchSessionSync extends StatefulWidget {
  const WorkbenchSessionSync({
    required this.workspaceId,
    required this.sessionIds,
    required this.child,
    this.activeSessionId,
    this.composeActive = false,
    super.key,
  });

  final String workspaceId;
  final List<String> sessionIds;
  final String? activeSessionId;
  final bool composeActive;
  final Widget child;

  @override
  State<WorkbenchSessionSync> createState() => _WorkbenchSessionSyncState();
}

class _WorkbenchSessionSyncState extends State<WorkbenchSessionSync> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant WorkbenchSessionSync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspaceId != widget.workspaceId ||
        oldWidget.activeSessionId != widget.activeSessionId ||
        oldWidget.composeActive != widget.composeActive ||
        !_listEquals(oldWidget.sessionIds, widget.sessionIds)) {
      _sync();
    }
  }

  void _sync() {
    context.read<WorkbenchCubit>().syncSessions(
      widget.workspaceId,
      widget.sessionIds,
      preferredActiveSessionId: widget.activeSessionId,
      composeActive: widget.composeActive,
    );
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
