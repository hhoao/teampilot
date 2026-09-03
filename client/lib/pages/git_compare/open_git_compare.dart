import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../cubits/workbench/workbench_cubit.dart';
import '../../cubits/workbench/workbench_tab.dart';
import '../../models/git_compare.dart';

/// Opens (or activates) the Git Compare floating tab for [spec].
///
/// Ensures the floating panel is visible, focuses [workspaceId], then adds the
/// gitCompare tab to that workspace's floating strip.
void openGitCompareTab(
  BuildContext context, {
  required String workspaceId,
  required GitCompareSpec spec,
}) {
  final floating = context.read<FloatingWorkspaceCubit>();
  floating.ensureOpen();
  floating.setActiveWorkspace(workspaceId);
  context
      .read<WorkbenchCubit>()
      .openFloating(workspaceId, WorkbenchTabId.gitCompare(spec));
}
