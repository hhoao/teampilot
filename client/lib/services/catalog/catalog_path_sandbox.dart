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
