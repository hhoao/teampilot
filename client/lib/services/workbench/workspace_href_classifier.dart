sealed class WorkspaceHrefKind {
  const WorkspaceHrefKind();
}

final class WorkspaceHrefExternal extends WorkspaceHrefKind {
  const WorkspaceHrefExternal(this.uri);
  final Uri uri;
}

final class WorkspaceHrefLocalPath extends WorkspaceHrefKind {
  const WorkspaceHrefLocalPath(this.rawPath);
  final String rawPath;
}

final class WorkspaceHrefIgnored extends WorkspaceHrefKind {
  const WorkspaceHrefIgnored();
}

class WorkspaceHrefClassifier {
  const WorkspaceHrefClassifier();

  WorkspaceHrefKind classify(String href) {
    final raw = href.trim();
    if (raw.isEmpty) return const WorkspaceHrefIgnored();

    final uri = Uri.tryParse(raw);
    if (uri == null) return const WorkspaceHrefIgnored();

    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      if (uri.host.isEmpty) return const WorkspaceHrefIgnored();
      return WorkspaceHrefExternal(uri);
    }
    if (scheme == 'file') {
      if (uri.host.isNotEmpty) return const WorkspaceHrefIgnored();
      try {
        return WorkspaceHrefLocalPath(uri.toFilePath());
      } on UnsupportedError {
        return const WorkspaceHrefIgnored();
      }
    }
    // Uri treats `C:\repo\a.md` as scheme `c`; keep it as a local path.
    if (scheme.length == 1) {
      final afterColon = raw.indexOf(':') + 1;
      if (afterColon > 0 && afterColon < raw.length) {
        final next = raw[afterColon];
        if (next == '/' || next == r'\') {
          final path = raw.split('#').first.trim();
          if (path.isEmpty) return const WorkspaceHrefIgnored();
          return WorkspaceHrefLocalPath(path);
        }
      }
    }
    if (scheme.isNotEmpty) return const WorkspaceHrefIgnored();

    final path = raw.split('#').first.trim();
    if (path.isEmpty) return const WorkspaceHrefIgnored();
    return WorkspaceHrefLocalPath(path);
  }
}
