import 'dart:io';

import 'package:file_picker/file_picker.dart' as fp;
import 'package:shared_ui/shared_ui.dart';

/// Native OS file/directory dialogs via [file_picker].
class TeamPilotDesktopPickerPort implements TpDesktopPickerPort {
  const TeamPilotDesktopPickerPort();

  @override
  Future<List<TpPickedEntry>?> pickFiles({
    bool allowMultiple = false,
    List<String>? allowedExtensions,
    String? dialogTitle,
    String? initialDirectory,
    int? maxSelectionCount,
  }) async {
    final (type, extensions) = _resolveFileType(allowedExtensions);

    final result = await fp.FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
      initialDirectory: _resolveInitialDirectory(initialDirectory),
      type: type,
      allowedExtensions: extensions,
      allowMultiple: allowMultiple,
      lockParentWindow: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    var entries = result.files
        .where((file) => file.path != null)
        .map(
          (file) => TpPickedEntry(
            path: file.path!,
            kind: TpPickedKind.file,
            displayName: file.name,
          ),
        )
        .toList();

    if (maxSelectionCount != null && entries.length > maxSelectionCount) {
      entries = entries.take(maxSelectionCount).toList();
    }

    return entries;
  }

  @override
  Future<List<TpPickedEntry>?> pickDirectory({
    String? dialogTitle,
    String? initialDirectory,
  }) async {
    final path = await fp.FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle,
      initialDirectory: _resolveInitialDirectory(initialDirectory),
      lockParentWindow: true,
    );
    if (path == null) {
      return null;
    }
    return [
      TpPickedEntry(path: path, kind: TpPickedKind.directory),
    ];
  }

  static String? _resolveInitialDirectory(String? path) {
    if (path == null || path.isEmpty) {
      return null;
    }
    final dir = Directory(path);
    if (dir.existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.existsSync()) {
      return parent.path;
    }
    return null;
  }

  static (fp.FileType, List<String>?) _resolveFileType(
    List<String>? allowedExtensions,
  ) {
    if (allowedExtensions == null || allowedExtensions.isEmpty) {
      return (fp.FileType.any, null);
    }

    final normalized = allowedExtensions
        .map((ext) => ext.toLowerCase().replaceFirst('.', ''))
        .toList();

    return (fp.FileType.custom, normalized);
  }
}
