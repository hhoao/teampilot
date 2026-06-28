/// Formatting helpers for [printPerformanceSummary].
library;

/// Separator used in flame-tree breadcrumb paths.
const hotPathSeparator = ' › ';

/// Shortens a flame-tree breadcrumb for one-line summary output.
///
/// Prefers the subtree from the first `BUILD` phase; otherwise keeps the tail.
String shortenHotPath(String path, {int tailSegments = 4}) {
  final parts = path.split(hotPathSeparator);
  if (parts.length <= 1) return path;

  final buildIdx = parts.indexWhere((p) => p.toUpperCase() == 'BUILD');
  if (buildIdx >= 0 && buildIdx < parts.length - 1) {
    return parts.sublist(buildIdx).join(hotPathSeparator);
  }

  if (parts.length <= tailSegments) return path;
  return '…${hotPathSeparator}${parts.sublist(parts.length - tailSegments).join(hotPathSeparator)}';
}

String formatFrameList(Iterable<int> frameNumbers, {int maxShown = 4}) {
  final sorted = [...frameNumbers]..sort();
  if (sorted.isEmpty) return '';
  if (sorted.length <= maxShown) {
    return sorted.map((n) => '#$n').join(', ');
  }
  final head = sorted.take(maxShown).map((n) => '#$n').join(', ');
  return '$head +${sorted.length - maxShown}';
}
