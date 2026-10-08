import 'package:path/path.dart' as p;

import '../../../utils/workspace/workspace_path_utils.dart';
import '../../io/filesystem.dart';

const _usesPosixPaths = true;

final _posix = p.Context(style: p.Style.posix);

String? resolveSessionSshMcpRemoteCwd({
  String? cwd,
  required List<String> folderPaths,
}) {
  if (folderPaths.isEmpty) return null;

  final trimmed = cwd?.trim() ?? '';
  final String resolved;
  if (trimmed.isEmpty) {
    resolved = folderPaths.first;
  } else if (trimmed.startsWith('/') && !trimmed.startsWith('//')) {
    resolved = trimmed;
  } else {
    resolved = _posix.normalize(_posix.join(folderPaths.first, trimmed));
  }

  final normalized = normalizeWorkspacePath(
    resolved,
    usesPosixPaths: _usesPosixPaths,
  );
  if (normalized.isEmpty) return null;

  for (final folder in folderPaths) {
    if (workspacePathUnderFolder(
      normalized,
      folder,
      usesPosixPaths: _usesPosixPaths,
    )) {
      return normalized;
    }
  }
  return null;
}

bool sessionSshMcpRemotePathAllowed(String path, List<String> folderPaths) {
  if (folderPaths.isEmpty) return false;

  final trimmed = path.trim();
  if (trimmed.isEmpty || !trimmed.startsWith('/') || trimmed.startsWith('//')) {
    return false;
  }

  final normalized = normalizeWorkspacePath(
    trimmed,
    usesPosixPaths: _usesPosixPaths,
  );
  if (normalized.isEmpty) return false;

  for (final folder in folderPaths) {
    if (workspacePathUnderFolder(
      normalized,
      folder,
      usesPosixPaths: _usesPosixPaths,
    )) {
      return true;
    }
  }
  return false;
}

bool sessionSshMcpLocalPathAllowed(
  String path,
  List<String> roots, {
  required bool usesPosixPaths,
}) {
  if (roots.isEmpty) return false;

  final normalized = normalizeWorkspacePath(
    path.trim(),
    usesPosixPaths: usesPosixPaths,
  );
  if (normalized.isEmpty) return false;

  for (final root in roots) {
    if (workspacePathUnderFolder(
      normalized,
      root,
      usesPosixPaths: usesPosixPaths,
    )) {
      return true;
    }
  }
  return false;
}

String sessionSshMcpPosixQuote(String value) =>
    "'${value.replaceAll("'", r"'\''")}'";

/// Rejects [path] when it is a symlink whose resolved target leaves [roots].
Future<bool> sessionSshMcpLocalSymlinkAllowed({
  required Filesystem fs,
  required String path,
  required List<String> roots,
  required bool usesPosixPaths,
}) async {
  final ctx = fs.pathContext;
  final normalizedPath = ctx.normalize(path.trim());
  final normalizedRoots = [
    for (final root in roots)
      normalizeWorkspacePath(root.trim(), usesPosixPaths: usesPosixPaths),
  ];

  final target = await fs.readSymlinkTarget(normalizedPath);
  if (target == null) return true;

  final resolved = ctx.normalize(
    ctx.isAbsolute(target)
        ? target
        : ctx.join(ctx.dirname(normalizedPath), target),
  );
  for (final root in normalizedRoots) {
    if (workspacePathUnderFolder(
      resolved,
      root,
      usesPosixPaths: usesPosixPaths,
    )) {
      return true;
    }
  }
  return false;
}
