/// Minimal file-access abstraction for the pure-Dart fallback engine.
/// The app adapts its `Filesystem` (e.g. SftpFilesystem) to this interface.
abstract interface class SearchFileReader {
  /// Lists immediate children of [path]. Returns [] when unreadable.
  Future<List<SearchDirEntry>> listDir(String path);

  /// Reads [path] as text lines (without line terminators).
  /// Returns null when the file is unreadable or binary (NUL byte).
  Future<List<String>?> readLines(String path);
}

class SearchDirEntry {
  const SearchDirEntry({
    required this.name,
    required this.isDirectory,
    this.size,
  });

  final String name;
  final bool isDirectory;
  final int? size;
}
