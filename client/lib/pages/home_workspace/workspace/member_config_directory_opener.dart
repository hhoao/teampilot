import 'package:flutter/material.dart';

import '../../../l10n/l10n_extensions.dart';
import '../../../services/io/runtime_folder_opener.dart';
import '../../../services/storage/runtime_context.dart';
import '../../../widgets/remote_directory_browser_dialog.dart';

/// Opens a member CONFIG_DIR — native file manager locally, in-app SFTP browser
/// on ssh/wsl work planes.
Future<void> openMemberConfigDirectory(
  BuildContext context, {
  required String path,
  RuntimeContext? workContext,
}) async {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return;

  final ctx = workContext;
  if (ctx != null && ctx.mode != StorageBackendMode.native) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => RemoteDirectoryBrowserDialog(
        targetId: ctx.target.id,
        initialPath: trimmed,
        browseOnly: true,
        title: dialogContext.l10n.memberDetailBrowseConfigDirTitle,
      ),
    );
    return;
  }

  await RuntimeFolderOpener().reveal(path: trimmed, workContext: ctx);
}
