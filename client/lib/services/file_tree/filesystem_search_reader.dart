import 'dart:convert';

import 'package:teampilot_search/teampilot_search.dart';

import '../io/filesystem.dart';

/// Adapts the app's [Filesystem] (e.g. [SftpFilesystem]) to the package's
/// [SearchFileReader] so remote workspaces use the fallback engine.
///
/// `FsDirEntry` does not expose a `size`, so [SearchDirEntry.size] is always
/// null: [TpSearchOptions.maxFileSize] is not enforced by the SSH adapter
/// in v1 (matching lines are still capped via `kFallbackMaxLineBytes`).
class FilesystemSearchReader implements SearchFileReader {
  const FilesystemSearchReader(this.fs);

  final Filesystem fs;

  @override
  Future<List<SearchDirEntry>> listDir(String path) async {
    try {
      final entries = await fs.listDir(path);
      return entries
          .map((e) => SearchDirEntry(
                name: e.name,
                isDirectory: e.isDirectory,
                size: null,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<String>?> readLines(String path) async {
    try {
      final text = await fs.readString(path);
      if (text == null) return null;
      if (text.contains('\u0000')) return null; // binary
      return const LineSplitter().convert(text);
    } catch (_) {
      return null;
    }
  }
}
