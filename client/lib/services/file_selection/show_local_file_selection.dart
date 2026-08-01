import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import 'teampilot_file_selection_deps.dart';

/// Opens local file/directory selection and returns absolute paths.
///
/// SSH remote directory browsing stays on [RemoteDirectoryBrowserDialog].
Future<List<String>?> showLocalFileSelection(
  BuildContext context, {
  TpFileSelectionOptions options = const TpFileSelectionOptions(),
  TpFileSelectionDeps? deps,
}) async {
  final picked = await showTpFileSelection(
    context: context,
    deps: deps ?? teampilotFileSelectionDeps(),
    options: options,
  );
  if (picked == null) {
    return null;
  }
  return picked.map((entry) => entry.path).toList(growable: false);
}
