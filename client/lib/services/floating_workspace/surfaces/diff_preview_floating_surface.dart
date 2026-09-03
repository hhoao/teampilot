import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../cubits/editor_cubit.dart';
import '../../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../../cubits/workbench/workbench_tab.dart';
import '../../../models/diff_identity.dart';
import '../../../models/floating_workspace_tab.dart';
import '../../../pages/workbench/diff_editor_surface.dart';
import '../floating_surface.dart';

/// Floating surface that hosts [DiffEditorSurface] for one diff key.
///
/// Domain open is driven by [WorkbenchEditorOpener.openDiff]; [activate] is a
/// no-op so tab switches / rebuilds do not re-open.
class DiffPreviewFloatingSurface extends FloatingSurface {
  DiffPreviewFloatingSurface({
    required EditorCubit editor,
    required FloatingWorkspaceCubit floating,
  }) : _editor = editor,
       _floating = floating;

  final EditorCubit _editor;
  final FloatingWorkspaceCubit _floating;

  @override
  String get id => 'diffPreview';

  @override
  FloatingEmptyAction? get emptyAction => null;

  @override
  bool get allowMultipleTabs => true;

  @override
  FloatingTab createTab({required String workspaceId, Object? payload}) {
    final diffKey = payload is String ? payload.trim() : '';
    final parsed = diffKey.isEmpty
        ? null
        : WorkbenchTabId.parseDiffStorageKey(diffKey);
    final title = parsed == null ? 'Diff' : _diffTitle(parsed);
    return FloatingTab(
      id: diffKey.isEmpty ? 'diff:' : floatingDiffTabId(diffKey),
      surfaceId: id,
      title: title,
      payload: diffKey.isEmpty ? null : diffKey,
    );
  }

  @override
  Widget build(BuildContext context, FloatingTab tab) {
    final diffKey = tab.payload;
    if (diffKey is! String || diffKey.isEmpty) {
      return const SizedBox.shrink();
    }
    final workspaceId = _floating.state.activeWorkspaceId;
    if (workspaceId.isEmpty) {
      return const SizedBox.shrink();
    }
    return DiffEditorSurface(workspaceId: workspaceId, diffKey: diffKey);
  }

  @override
  Future<void> activate(FloatingTab tab) async {}

  @override
  Future<bool> canClose(FloatingTab tab, {BuildContext? context}) async => true;

  @override
  void onTabClosed(FloatingTab tab) {
    final diffKey = tab.payload;
    if (diffKey is! String || diffKey.isEmpty) return;
    final workspaceId = _floating.state.activeWorkspaceId;
    if (workspaceId.isEmpty) return;
    _editor.closeDiff(workspaceId, diffKey);
  }
}

/// Floating tab id for a workbench-compatible [diffKey].
String floatingDiffTabId(String diffKey) => 'diff:$diffKey';

String _diffTitle(DiffIdentity identity) {
  final base = p.basename(identity.absolutePath);
  return switch (identity) {
    ScmDiffIdentity(mode: ScmDiffMode.staged) => '$base (staged)',
    ScmDiffIdentity() => base,
    CompareDiffIdentity(:final left, :final right) =>
      '$base (${left.titleLabel()} ↔ ${right.titleLabel()})',
  };
}
