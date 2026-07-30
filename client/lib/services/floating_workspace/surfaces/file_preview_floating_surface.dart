import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../cubits/editor_cubit.dart';
import '../../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../../models/floating_workspace_tab.dart';
import '../../../pages/workbench/file_editor_surface.dart';
import '../../commands/command_ids.dart';
import '../floating_surface.dart';

/// Floating surface that hosts [FileEditorSurface] for one absolute path.
///
/// Domain open is driven by [WorkbenchEditorOpener.openFile]; [activate] is a
/// no-op so tab switches / rebuilds do not double-open.
class FilePreviewFloatingSurface extends FloatingSurface {
  FilePreviewFloatingSurface({
    required EditorCubit editor,
    required FloatingWorkspaceCubit floating,
  }) : _editor = editor,
       _floating = floating;

  final EditorCubit _editor;
  final FloatingWorkspaceCubit _floating;

  @override
  String get id => 'filePreview';

  @override
  FloatingEmptyAction? get emptyAction => const FloatingEmptyAction(
    commandId: CommandIds.floatingOpenFile,
    labelKey: 'openFile',
    icon: Icons.insert_drive_file_outlined,
  );

  @override
  bool get allowMultipleTabs => true;

  @override
  FloatingTab createTab({required String workspaceId, Object? payload}) {
    final path = payload is String ? payload.trim() : '';
    return FloatingTab(
      id: path.isEmpty ? 'file:' : 'file:$path',
      surfaceId: id,
      title: path.isEmpty ? 'File' : p.basename(path),
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
    return FileEditorSurface(workspaceId: workspaceId, path: path);
  }

  @override
  Future<void> activate(FloatingTab tab) async {
    // Opener already called EditorCubit.openFile; avoid double-open on rebuild.
  }

  @override
  Future<bool> canClose(FloatingTab tab) async {
    // Dirty discard UI needs panel BuildContext (Task 8). Allow close for now.
    return true;
  }

  @override
  void onTabClosed(FloatingTab tab) {
    final path = tab.payload;
    if (path is! String || path.isEmpty) return;
    final workspaceId = _floating.state.activeWorkspaceId;
    if (workspaceId.isEmpty) return;
    _editor.closeFile(workspaceId, path, force: true);
  }
}
