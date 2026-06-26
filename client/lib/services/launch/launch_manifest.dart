import 'package:path/path.dart' as p;

/// A single filesystem mutation staged for batch apply at launch time.
sealed class LaunchManifestEntry {
  const LaunchManifestEntry();
}

final class ManifestEnsureDir extends LaunchManifestEntry {
  const ManifestEnsureDir(this.path);

  final String path;
}

final class ManifestWriteFile extends LaunchManifestEntry {
  const ManifestWriteFile(this.path, this.content);

  final String path;
  final String content;
}

final class ManifestSymlink extends LaunchManifestEntry {
  const ManifestSymlink({required this.linkPath, required this.target});

  final String linkPath;
  final String target;
}

final class ManifestCopyFile extends LaunchManifestEntry {
  const ManifestCopyFile({required this.source, required this.destination});

  final String source;
  final String destination;
}

final class ManifestCopyTree extends LaunchManifestEntry {
  const ManifestCopyTree({required this.source, required this.destination});

  final String source;
  final String destination;
}

final class ManifestRemoveRecursive extends LaunchManifestEntry {
  const ManifestRemoveRecursive(this.path);

  final String path;
}

final class ManifestRename extends LaunchManifestEntry {
  const ManifestRename({required this.from, required this.to});

  final String from;
  final String to;
}

/// Staged launch filesystem mutations. Built during session prep, flushed once
/// before the PTY starts (local executor or SSH batch).
class LaunchManifest {
  LaunchManifest({p.Context? pathContext})
    : pathContext = pathContext ?? p.Context(style: p.Style.posix);

  final p.Context pathContext;
  final List<LaunchManifestEntry> entries = [];

  /// Config file bodies only (last write per path wins).
  Map<String, String> get files {
    final out = <String, String>{};
    for (final entry in entries) {
      if (entry is ManifestWriteFile) {
        out[entry.path] = entry.content;
      }
    }
    return Map.unmodifiable(out);
  }

  void ensureDir(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    entries.add(ManifestEnsureDir(trimmed));
  }

  void writeFile(String path, String content) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    entries.add(ManifestWriteFile(trimmed, content));
  }

  void symlink({required String linkPath, required String target}) {
    final link = linkPath.trim();
    if (link.isEmpty) return;
    entries.add(ManifestSymlink(linkPath: link, target: target));
  }

  void copyFile({required String source, required String destination}) {
    final src = source.trim();
    final dest = destination.trim();
    if (src.isEmpty || dest.isEmpty) return;
    entries.add(ManifestCopyFile(source: src, destination: dest));
  }

  void copyTree({required String source, required String destination}) {
    final src = source.trim();
    final dest = destination.trim();
    if (src.isEmpty || dest.isEmpty) return;
    entries.add(ManifestCopyTree(source: src, destination: dest));
  }

  void removeRecursive(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return;
    entries.add(ManifestRemoveRecursive(trimmed));
  }

  void rename({required String from, required String to}) {
    final src = from.trim();
    final dest = to.trim();
    if (src.isEmpty || dest.isEmpty) return;
    entries.add(ManifestRename(from: src, to: dest));
  }

  LaunchManifest copyWithEntries(List<LaunchManifestEntry> next) {
    final copy = LaunchManifest(pathContext: pathContext);
    copy.entries.addAll(next);
    return copy;
  }
}
