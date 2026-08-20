import 'package:path/path.dart' as p;

import '../io/filesystem.dart';
import 'catalog_kind.dart';

/// Rejects import paths that are not an allowed root or a descendant of one.
///
/// [path] is normalized with [Filesystem.pathContext]. A symlink whose
/// resolved target leaves every allowed root is also rejected.
Future<void> assertSafeImportPath({
  required Filesystem fs,
  required String path,
  required List<String> allowedRoots,
}) async {
  final ctx = fs.pathContext;
  final normalizedPath = ctx.normalize(path);
  final normalizedRoots = [
    for (final root in allowedRoots) ctx.normalize(root),
  ];

  if (!_isInsideAllowed(ctx, normalizedPath, normalizedRoots)) {
    throw CatalogException(
      'unsafe_path',
      'Path is outside allowed import roots: $path',
    );
  }

  await _assertSymlinkTargetInside(
    fs: fs,
    ctx: ctx,
    path: normalizedPath,
    normalizedRoots: normalizedRoots,
  );

  final entries = await fs.listDirRecursive(normalizedPath);
  for (final entry in entries) {
    final child = ctx.normalize(ctx.join(normalizedPath, entry.name));
    await _assertSymlinkTargetInside(
      fs: fs,
      ctx: ctx,
      path: child,
      normalizedRoots: normalizedRoots,
    );
  }
}

Future<void> _assertSymlinkTargetInside({
  required Filesystem fs,
  required p.Context ctx,
  required String path,
  required List<String> normalizedRoots,
}) async {
  final target = await fs.readSymlinkTarget(path);
  if (target == null) return;

  final resolved = ctx.normalize(
    ctx.isAbsolute(target) ? target : ctx.join(ctx.dirname(path), target),
  );
  if (!_isInsideAllowed(ctx, resolved, normalizedRoots)) {
    throw CatalogException(
      'unsafe_path',
      'Symlink target is outside allowed import roots: $path',
    );
  }
}

bool _isInsideAllowed(
  p.Context ctx,
  String normalizedPath,
  List<String> normalizedRoots,
) {
  final separator = ctx.separator;
  for (final root in normalizedRoots) {
    if (normalizedPath == root) return true;
    final prefix = root.endsWith(separator) ? root : '$root$separator';
    if (normalizedPath.startsWith(prefix)) return true;
  }
  return false;
}

/// Rejects catalog `directory` names and `files` keys that can escape the
/// install root (`..`, `/`, `\`, or empty).
void assertSafeCatalogEntryName(String name, {String field = 'path'}) {
  if (name.isEmpty ||
      name.contains('/') ||
      name.contains('\\') ||
      name == '.' ||
      name == '..' ||
      name.contains('..')) {
    throw CatalogException(
      'unsafe_path',
      '$field is not a safe relative name: $name',
    );
  }
}
