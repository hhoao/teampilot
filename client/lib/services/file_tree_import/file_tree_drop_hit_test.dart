import 'package:path/path.dart' as p;

enum FileTreeDropRowKind { folder, file, rootChrome, empty }

class FileTreeDropHit {
  const FileTreeDropHit({required this.destDir, this.rejectedReason});

  final String? destDir;
  final String? rejectedReason;

  bool get isValid => destDir != null && rejectedReason == null;
}

/// [pathContext] from dest mount. [sourcePaths] non-empty for in-tree reject checks.
FileTreeDropHit resolveFileTreeDropDest({
  required FileTreeDropRowKind kind,
  required String rowPath,
  required p.Context pathContext,
  List<String> sourcePaths = const [],
}) {
  final destDir = _resolveDestDir(
    kind: kind,
    rowPath: rowPath,
    pathContext: pathContext,
  );
  if (destDir == null) {
    return const FileTreeDropHit(destDir: null);
  }

  final normalizedDest = pathContext.normalize(destDir);
  if (sourcePaths.isNotEmpty &&
      _isOntoSelfOrDescendant(
        pathContext: pathContext,
        destDir: normalizedDest,
        sourcePaths: sourcePaths,
      )) {
    return const FileTreeDropHit(destDir: null, rejectedReason: 'ontoSelf');
  }

  return FileTreeDropHit(destDir: normalizedDest);
}

String? _resolveDestDir({
  required FileTreeDropRowKind kind,
  required String rowPath,
  required p.Context pathContext,
}) {
  switch (kind) {
    case FileTreeDropRowKind.folder:
    case FileTreeDropRowKind.rootChrome:
      return rowPath;
    case FileTreeDropRowKind.file:
      return pathContext.dirname(rowPath);
    case FileTreeDropRowKind.empty:
      return rowPath.isEmpty ? null : rowPath;
  }
}

bool _isOntoSelfOrDescendant({
  required p.Context pathContext,
  required String destDir,
  required List<String> sourcePaths,
}) {
  for (final source in sourcePaths) {
    final normalizedSource = pathContext.normalize(source);
    if (_pathsEqual(pathContext, normalizedSource, destDir)) {
      return true;
    }
    if (_isWithin(pathContext, parent: normalizedSource, child: destDir)) {
      return true;
    }
  }
  return false;
}

bool _pathsEqual(p.Context ctx, String a, String b) {
  final left = ctx.normalize(a);
  final right = ctx.normalize(b);
  if (ctx.equals(left, right)) return true;
  return left.toLowerCase() == right.toLowerCase();
}

bool _isWithin(p.Context ctx, {required String parent, required String child}) {
  try {
    return ctx.isWithin(parent, child);
  } catch (_) {
    final normalizedParent = parent.toLowerCase();
    final normalizedChild = child.toLowerCase();
    final sep = ctx.separator;
    return normalizedChild.startsWith('$normalizedParent$sep');
  }
}

/// Multi-root empty/gap: pick root whose band contains [localY], else nearest centerY.
String resolveNearestRootDest({
  required double localY,
  required List<({String rootPath, double top, double bottom})> rootBands,
}) {
  if (rootBands.isEmpty) {
    throw ArgumentError.value(rootBands, 'rootBands', 'must not be empty');
  }

  for (final band in rootBands) {
    if (localY >= band.top && localY <= band.bottom) {
      return band.rootPath;
    }
  }

  var nearest = rootBands.first;
  var nearestDistance = _centerDistance(localY, nearest);
  for (var i = 1; i < rootBands.length; i++) {
    final band = rootBands[i];
    final distance = _centerDistance(localY, band);
    if (distance < nearestDistance) {
      nearest = band;
      nearestDistance = distance;
    }
  }
  return nearest.rootPath;
}

double _centerDistance(
  double localY,
  ({String rootPath, double top, double bottom}) band,
) {
  final centerY = (band.top + band.bottom) / 2;
  return (localY - centerY).abs();
}
