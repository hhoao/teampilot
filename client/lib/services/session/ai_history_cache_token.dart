import '../io/filesystem.dart';

/// Stable cache token from a transcript path + size (+ mtime when available).
Future<String> aiHistoryPathCacheToken({
  required Filesystem fs,
  required String path,
  required int byteLength,
}) async {
  final st = await fs.stat(path);
  final mtime = st.mtime?.toUtc().toIso8601String() ?? '';
  return '$path|$mtime|$byteLength';
}

/// Fingerprint of `*.txt` files in [dir] (sorted by basename).
///
/// Missing/unlistable dir or no `*.txt` → [emptySentinel] (stable).
Future<String> aiHistoryTxtDirCacheFingerprint({
  required Filesystem fs,
  required String dir,
  String emptySentinel = 'terminals:empty',
}) async {
  final stat = await fs.stat(dir);
  if (!stat.isDirectory) return emptySentinel;

  final paths = <String>[];
  try {
    for (final entry in await fs.listDir(dir)) {
      if (!entry.isDirectory && entry.name.endsWith('.txt')) {
        paths.add(fs.pathContext.join(dir, entry.name));
      }
    }
  } on Object {
    return emptySentinel;
  }

  if (paths.isEmpty) return emptySentinel;

  paths.sort((a, b) => fs.pathContext.basename(a).compareTo(
        fs.pathContext.basename(b),
      ));

  final parts = <String>[];
  for (final path in paths) {
    final st = await fs.stat(path);
    if (!st.isFile) continue;
    parts.add(
      await aiHistoryPathCacheToken(
        fs: fs,
        path: path,
        byteLength: st.size ?? 0,
      ),
    );
  }
  return parts.isEmpty ? emptySentinel : parts.join('\n');
}
