import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../services/workspace/workspace_tools_scope.dart';
import '../../services/workspace/workspace_tools_scope_registry.dart';

/// Re-publishes the active workspace [WorkspaceToolsScope] under the floating
/// panel.
///
/// [FloatingWorkspaceHost] stacks the panel beside [HomeWorkspaceBodyStack], so
/// InheritedWidget lookups from floating file preview miss the body scope.
/// Uses [WorkspaceToolsScopeRegistry.peek] so it never allocates a new cubit.
class FloatingWorkspaceToolsScopeBridge extends StatelessWidget {
  const FloatingWorkspaceToolsScopeBridge({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final workspaceId = context.select<FloatingWorkspaceCubit, String>(
      (c) => c.state.activeWorkspaceId.trim(),
    );
    if (workspaceId.isEmpty) return child;

    final registry = _maybeRegistry(context);
    if (registry == null) return child;

    // Scope cubits register lazily as workspace tabs initialize; listen so a
    // late registration re-publishes without waiting for another rebuild.
    return ListenableBuilder(
      listenable: registry,
      builder: (context, _) {
        final cubit = registry.peek(workspaceId);
        if (cubit == null) return child;
        return BlocProvider<WorkspaceToolsScopeCubit>.value(
          value: cubit,
          child: BlocBuilder<WorkspaceToolsScopeCubit, WorkspaceToolsScopeState>(
            builder: (context, state) =>
                WorkspaceToolsScope(state: state, child: child),
          ),
        );
      },
    );
  }
}

WorkspaceToolsScopeRegistry? _maybeRegistry(BuildContext context) {
  try {
    return context.read<WorkspaceToolsScopeRegistry>();
  } catch (_) {
    return null;
  }
}
