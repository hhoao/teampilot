import '../io/filesystem.dart';

/// One directory's worth of navigation state: the absolute [path] being shown,
/// its [parent] (null when [path] is a filesystem root), and the immediate
/// subdirectory names (basenames only, sorted).
class RemoteDirectoryListing {
  const RemoteDirectoryListing({
    required this.path,
    required this.parent,
    required this.directories,
  });

  final String path;
  final String? parent;
  final List<String> directories;
}

/// Pure, fs-injected directory navigator. POSIX-oriented but defers all path
/// math to the injected [Filesystem.pathContext], so it works for any backend
/// (local cwd, WSL, SFTP remote home). No Flutter imports — fully unit-testable
/// with a fake [Filesystem].
class RemoteDirectoryBrowser {
  RemoteDirectoryBrowser(this._fs);

  final Filesystem _fs;

  /// Resolve the directory to open first. Empty / `~` / `.` resolve to the
  /// backend's "here" via `resolveSymlink('.')` (remote home for SFTP, cwd for
  /// local); a `~/...` prefix expands against that home. Anything else is
  /// normalized with the backend path context.
  Future<String> resolveInitial(String? input) async {
    final trimmed = (input ?? '').trim();
    if (trimmed.isEmpty || trimmed == '~' || trimmed == '.') {
      return _home();
    }
    if (trimmed == '~/' || trimmed.startsWith('~/')) {
      final rest = trimmed.substring(2);
      final home = await _home();
      return rest.isEmpty ? home : _fs.pathContext.normalize(
        _fs.pathContext.join(home, rest),
      );
    }
    return _fs.pathContext.normalize(trimmed);
  }

  Future<String> _home() async {
    final resolved = await _fs.resolveSymlink('.');
    if (resolved != null && resolved.trim().isNotEmpty) return resolved;
    return _fs.pathContext.rootPrefix(_fs.pathContext.current).isNotEmpty
        ? _fs.pathContext.rootPrefix(_fs.pathContext.current)
        : '/';
  }

  /// List the subdirectories of [path] (directories only, sorted). Throws a
  /// [RemoteDirectoryBrowserException] when [path] is not an existing directory.
  /// [parent] is the enclosing directory, or null when [path] is a root.
  Future<RemoteDirectoryListing> list(
    String path, {
    bool includeHidden = false,
  }) async {
    final stat = await _fs.stat(path);
    if (!stat.exists || !stat.isDirectory) {
      throw RemoteDirectoryBrowserException('Not a directory: $path');
    }
    final entries = await _fs.listDir(path);
    final dirs = <String>[
      for (final e in entries)
        if (e.isDirectory && (includeHidden || !e.name.startsWith('.')))
          e.name,
    ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final parent = _fs.pathContext.dirname(path);
    return RemoteDirectoryListing(
      path: path,
      parent: parent == path ? null : parent,
      directories: dirs,
    );
  }

  /// Join a child directory [name] onto the current [path] using the backend's
  /// path semantics (so callers stay free of any path-context handling).
  String child(String path, String name) => _fs.pathContext.join(path, name);
}

/// Raised when a path cannot be listed (missing, not a directory).
class RemoteDirectoryBrowserException implements Exception {
  const RemoteDirectoryBrowserException(this.message);

  final String message;

  @override
  String toString() => 'RemoteDirectoryBrowserException: $message';
}
