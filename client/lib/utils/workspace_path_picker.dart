import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/runtime_target.dart';
import '../widgets/remote_directory_browser_dialog.dart';

/// Picks a directory path for a workspace, routed by [targetId]:
///
/// - `ssh:*` targets (Android's home target, or any desktop remote) open the
///   SFTP-backed [RemoteDirectoryBrowserDialog] (with a hand-fill fallback).
/// - local / wsl targets use the native desktop directory picker.
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
  return FilePicker.platform.getDirectoryPath();
}
