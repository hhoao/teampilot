import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../../models/floating_workspace_tab.dart';
import '../../../pages/preview/html_preview_pane.dart';
import '../floating_surface.dart';

/// Floating surface that hosts an embedded rendered html preview tab.
class HtmlPreviewFloatingSurface extends FloatingSurface {
  HtmlPreviewFloatingSurface({required FloatingWorkspaceCubit floating})
    : _floating = floating;

  final FloatingWorkspaceCubit _floating;

  @override
  String get id => 'htmlPreview';

  @override
  FloatingEmptyAction? get emptyAction => null;

  @override
  bool get allowMultipleTabs => true;

  @override
  FloatingTab createTab({required String workspaceId, Object? payload}) {
    final path = payload is String ? payload.trim() : '';
    return FloatingTab(
      id: path.isEmpty ? 'htmlPreview:' : 'htmlPreview:$path',
      surfaceId: id,
      title: path.isEmpty ? 'HTML Preview' : p.basename(path),
      payload: path.isEmpty ? null : path,
    );
  }

  @override
  Widget build(BuildContext context, FloatingTab tab) {
    final path = tab.payload;
    if (path is! String || path.isEmpty) {
      return const SizedBox.shrink();
    }
    final workspaceId = _floating.state.activeWorkspaceId;
    if (workspaceId.isEmpty) {
      return const SizedBox.shrink();
    }
    return HtmlPreviewPane(workspaceId: workspaceId, path: path);
  }

  @override
  Future<void> activate(FloatingTab tab) async {}
}
