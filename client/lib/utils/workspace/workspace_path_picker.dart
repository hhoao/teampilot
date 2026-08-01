import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../models/runtime_target.dart';
import '../../services/file_selection/show_local_file_selection.dart';
import '../../widgets/remote_directory_browser_dialog.dart';

/// Picks a directory path for a workspace, routed by [targetId]:
///
/// - `ssh:*` targets (Android's home target, or any desktop remote) open the
///   SFTP-backed [RemoteDirectoryBrowserDialog] (with a hand-fill fallback).
/// - local / wsl targets use [showLocalFileSelection] (desktop OS dialog or
///   mobile filesystem page).
Future<String?> pickWorkspaceDirectoryPath(
  BuildContext context, {
  required String targetId,
}) async {
  if (runtimeKindOfId(targetId) == RuntimeKind.ssh) {
    return showDialog<String>(
      context: context,
      builder: (_) => RemoteDirectoryBrowserDialog(targetId: targetId),
    );
  }
  final picked = await showLocalFileSelection(
    context,
    options: const TpFileSelectionOptions(
      selectionMode: TpSelectionMode.directories,
    ),
  );
  if (picked == null || picked.isEmpty) {
    return null;
  }
  return picked.first;
}
