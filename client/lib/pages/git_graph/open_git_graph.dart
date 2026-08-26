import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';

/// Opens (or activates) the Git Graph floating tab for [repoRoot].
///
/// Ensures the floating panel is visible, focuses [workspaceId], then adds the
/// gitGraph tab to that workspace's floating strip.
void openGitGraphTab(
  BuildContext context, {
  required String workspaceId,
  required String repoRoot,
}) {
  final floating = context.read<FloatingWorkspaceCubit>();
  floating.ensureOpen();
  floating.setActiveWorkspace(workspaceId);
  context
      .read<WorkbenchCubit>()
      .openFloating(workspaceId, WorkbenchTabId.gitGraph(repoRoot));
}
