import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../../io/filesystem.dart';
import '../../../io/local_filesystem.dart';

typedef BinaryArchiveFetcher =
    Future<File> Function(
      Uri uri, {
      String? expectedSha256,
      void Function(int received, int? total)? onProgress,
      bool Function()? isCancelled,
    });
typedef BinaryArchiveExtractor =
    Future<void> Function({required File archive, required String destDir});
typedef BinaryChmod = Future<void> Function(String path);

Future<void> extractZipArchive({
  required File archive,
  required String destDir,
}) async {
  final bytes = await archive.readAsBytes();
  final decoded = ZipDecoder().decodeBytes(bytes);
  final fs = LocalFilesystem();
  for (final entry in decoded) {
    if (!entry.isFile) continue;
    final out = p.join(destDir, entry.name);
    await fs.ensureDir(p.dirname(out));
    await fs.writeBytes(out, entry.content as List<int>);
  }
}

Future<void> chmodExecutable(String path) async {
  if (Platform.isWindows) return;
  await Process.run('chmod', ['755', path]);
}

final class BinaryArchiveInstaller {
  const BinaryArchiveInstaller({
    required this.fs,
    required this.fetch,
    this.extract = extractZipArchive,
    this.chmod = chmodExecutable,
  });

  final Filesystem fs;
  final BinaryArchiveFetcher fetch;
  final BinaryArchiveExtractor extract;
  final BinaryChmod chmod;

  Future<String> install({
    required Uri archiveUri,
    required String sha256,
    required String destDir,
    required String executableName,
    List<String> extraExecutables = const [],
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final parent = fs.pathContext.dirname(destDir);
    await fs.ensureDir(parent);
    final temp = await fs.createTempDir(prefix: 'agy-acp-', parent: parent);
    final staging = fs.pathContext.join(temp, 'staging');
    await fs.ensureDir(staging);
    try {
      final archive = await fetch(
        archiveUri,
        expectedSha256: sha256,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
      await extract(archive: archive, destDir: staging);
      // Verify every executable before the atomic move so an incomplete
      // archive never lands at destDir.
      final executables = [executableName, ...extraExecutables];
      for (final name in executables) {
        final path = fs.pathContext.join(staging, name);
        if (!(await fs.stat(path)).isFile) {
          throw FileSystemException('Archive is missing $name', path);
        }
      }
      if ((await fs.stat(destDir)).exists) {
        await fs.removeRecursive(destDir);
      }
      await fs.rename(staging, destDir);
      // chmod the installed paths (not the staging ones) so the returned path
      // is the executable and callers tuning permissions see final paths.
      for (final name in executables) {
        await chmod(fs.pathContext.join(destDir, name));
      }
      return fs.pathContext.join(destDir, executableName);
    } finally {
      if ((await fs.stat(temp)).exists) await fs.removeRecursive(temp);
    }
  }
}
