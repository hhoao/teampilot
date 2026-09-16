import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Path relative to [workRoot], or null if [absolutePath] is outside it.
String? manifestOverlayRelativePath({
  required String absolutePath,
  required String workRoot,
  required p.Context pathContext,
}) {
  final root = pathContext.normalize(workRoot);
  final path = pathContext.normalize(absolutePath);
  if (!pathContext.isWithin(root, path) && path != root) {
    return null;
  }
  final relative = pathContext.relative(path, from: root);
  if (relative.isEmpty ||
      relative.startsWith('/') ||
      pathContext.split(relative).contains('..')) {
    return null;
  }
  return relative;
}

/// Gzip-compressed tar of [archive] for SSH overlay stdin.
Uint8List encodeLaunchOverlayGzip(Archive archive) =>
    GZipEncoder().encodeBytes(TarEncoder().encodeBytes(archive));

/// Short extract pipeline: `mkdir -p <workRoot> && gzip -dc | tar -x -C <workRoot>`.
String launchOverlayExtractCommand(String workRoot) {
  final root = workRoot.trim();
  if (root.isEmpty) {
    throw StateError('overlay extract requires a non-empty work root');
  }
  final quoted = _shellQuote(root);
  return 'mkdir -p $quoted && gzip -dc | tar -x -C $quoted';
}

void addOverlayFile(
  Archive archive, {
  required String relativePath,
  required List<int> bytes,
}) {
  // Follow-up: copyTree file members stay 0644 (ArchiveFile default); executable
  // bits from the source tree are not preserved on tar extract.
  archive.add(ArchiveFile(relativePath, bytes.length, bytes));
}

void addOverlayDir(Archive archive, {required String relativePath}) {
  archive.add(
    ArchiveFile(relativePath, 0, const <int>[])
      ..isFile = false
      ..mode = 0x1ed,
  );
}

String _shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";
