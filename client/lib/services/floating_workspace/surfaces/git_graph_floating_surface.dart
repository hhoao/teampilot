import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;

import '../../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../../models/floating_workspace_tab.dart';
import '../../../pages/git_graph/git_graph_pane.dart';
import '../floating_surface.dart';

/// 浮动面板中的 Git Graph 页。payload = 仓库根绝对路径；
/// 每仓库一个标签页（allowMultipleTabs）。
class GitGraphFloatingSurface extends FloatingSurface {
  GitGraphFloatingSurface();

  static const String surfaceId = 'gitGraph';

  @override
  String get id => surfaceId;

  @override
  FloatingEmptyAction? get emptyAction => null;

  @override
  bool get allowMultipleTabs => true;

  @override
  FloatingTab createTab({required String workspaceId, Object? payload}) {
    final root = payload is String ? payload.trim() : '';
    return FloatingTab(
      id: root.isEmpty ? '$surfaceId:' : '$surfaceId:$root',
      surfaceId: surfaceId,
      title: root.isEmpty ? 'Git Graph' : '${p.basename(root)} · Graph',
      payload: root.isEmpty ? null : root,
    );
  }

  @override
  Widget build(BuildContext context, FloatingTab tab) {
    final root = tab.payload;
    if (root is! String || root.isEmpty) return const SizedBox.shrink();
    final workspaceId =
        context.read<FloatingWorkspaceCubit>().state.activeWorkspaceId;
    if (workspaceId.isEmpty) return const SizedBox.shrink();
    return GitGraphPane(workspaceId: workspaceId, repoRoot: root);
  }

  @override
  Future<void> activate(FloatingTab tab) async {}
}
