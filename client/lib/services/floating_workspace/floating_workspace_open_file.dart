import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';

import '../../cubits/floating_workspace/floating_workspace_cubit.dart';
import '../../models/workspace.dart';
import '../workbench/workbench_editor_opener.dart';

typedef FloatingWorkspaceFilePicker =
    Future<FilePickerResult?> Function({
      FileType type,
      bool allowMultiple,
      String? initialDirectory,
    });

/// Opens a native file picker rooted at the active workspace folder (best-effort)
/// and routes the selection through [WorkbenchEditorOpener.openFile].
Future<void> pickAndOpenFloatingWorkspaceFile({
  required FloatingWorkspaceCubit floating,
  required WorkbenchEditorOpener opener,
  required List<Workspace> workspaces,
  FloatingWorkspaceFilePicker? pickFiles,
}) async {
  final workspaceId = floating.state.activeWorkspaceId.trim();
  if (workspaceId.isEmpty) return;

  final root =
      workspaces
          .where((w) => w.workspaceId == workspaceId)
          .map((w) => w.firstFolderPath.trim())
          .where((p) => p.isNotEmpty)
          .firstOrNull ??
      '';

  final picker =
      pickFiles ??
      ({
        type = FileType.any,
        allowMultiple = false,
        initialDirectory,
      }) => FilePicker.platform.pickFiles(
        type: type,
        allowMultiple: allowMultiple,
        initialDirectory: initialDirectory,
      );

  final result = await picker(
    type: FileType.any,
    allowMultiple: false,
    initialDirectory: root.isEmpty ? null : root,
  );
  final path = result?.files.firstOrNull?.path?.trim() ?? '';
  if (path.isEmpty) return;

  await opener.openFile(workspaceId, path);
}
