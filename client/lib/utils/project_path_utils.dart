import 'package:path/path.dart' as p;

/// Normalizes a filesystem path for stable comparison and storage.
///
/// Remote/SSH paths starting with `~` are kept as trimmed text only.
String normalizeProjectPath(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty || trimmed.startsWith('~')) return trimmed;
  if (trimmed.startsWith('/') && !trimmed.startsWith('//')) {
    return p.Context(style: p.Style.posix).normalize(trimmed);
  }
  return p.normalize(trimmed);
}

bool projectPathsEqual(String a, String b) {
  return normalizeProjectPath(a) == normalizeProjectPath(b);
}

bool projectPathsContains(Iterable<String> paths, String target) {
  final normalized = normalizeProjectPath(target);
  for (final existing in paths) {
    if (normalizeProjectPath(existing) == normalized) return true;
  }
  return false;
}
