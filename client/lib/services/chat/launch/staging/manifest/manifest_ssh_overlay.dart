import 'dart:convert';
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
///
/// [TarEncoder] emits GNU `@LongLink` members with typeflag `0` (regular
/// file). GNU tar then extracts the truncated 100-byte name, so session
/// settings paths like `workspace/workspaces/<uuid>/sessions/<uuid>/...`
/// never land. Write typeflag `L` so extract restores the full path.
Uint8List encodeLaunchOverlayGzip(Archive archive) {
  final output = OutputMemoryStream();
  for (final entry in archive) {
    _writeGnuTarEntry(output, entry);
  }
  output.writeBytes(Uint8List(1024));
  return GZipEncoder().encodeBytes(output.getBytes());
}

void _writeGnuTarEntry(OutputMemoryStream output, ArchiveFile entry) {
  if (entry.name.length > 100) {
    final nameBytes = Uint8List.fromList([...utf8.encode(entry.name), 0]);
    final longLink = TarFile()
      ..filename = '././@LongLink'
      ..typeFlag = 'L'
      ..mode = 0
      ..ownerId = 0
      ..groupId = 0
      ..lastModTime = 0
      ..fileSize = nameBytes.length
      ..contentBytes = nameBytes;
    longLink.write(output);
  }

  final ts = TarFile()
    ..filename = entry.name
    ..mode = entry.mode
    ..ownerId = entry.ownerId
    ..groupId = entry.groupId
    ..lastModTime = entry.lastModTime;
  if (!entry.isFile) {
    ts.typeFlag = TarFile.directory;
  } else if (entry.symbolicLink != null) {
    ts.typeFlag = TarFile.symbolicLink;
    ts.nameOfLinkedFile = entry.symbolicLink;
  } else {
    ts.fileSize = entry.size;
    ts.contentBytes = entry.getContent()?.toUint8List();
  }
  ts.write(output);
}

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
