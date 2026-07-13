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
