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
      return WorkspaceHrefLocalPath(uri.toFilePath());
    }
    if (scheme.isNotEmpty) return const WorkspaceHrefIgnored();

    final path = raw.split('#').first.trim();
    if (path.isEmpty) return const WorkspaceHrefIgnored();
    return WorkspaceHrefLocalPath(path);
  }
}
