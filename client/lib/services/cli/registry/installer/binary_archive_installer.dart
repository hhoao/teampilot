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
  final root = p.normalize(p.absolute(destDir));
  for (final entry in decoded) {
    if (!entry.isFile) continue;
    final name = entry.name;
    final out = p.normalize(p.join(root, name));
    // Reject zip-slip: absolute entry names and names that normalize outside
    // the extraction root (e.g. `../escape.txt`).
    if (p.isAbsolute(name) || !p.isWithin(root, out)) {
      throw FormatException('Unsafe archive entry: $name');
    }
    await fs.ensureDir(p.dirname(out));
    await fs.writeBytes(out, entry.content as List<int>);
  }
}

Future<void> chmodExecutable(String path) async {
  if (Platform.isWindows) return;
  final args = ['755', path];
  final result = await Process.run('chmod', args);
  if (result.exitCode != 0) {
    throw ProcessException(
      'chmod',
      args,
      '${result.stderr}'.trim(),
      result.exitCode,
    );
  }
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
      // Verify and chmod every executable in staging, before the atomic move:
      // an incomplete archive never lands at destDir, and the mode is carried
      // over by the rename so there is no window where destDir holds a
      // non-executable file.
      final executables = [executableName, ...extraExecutables];
      for (final name in executables) {
        final path = fs.pathContext.join(staging, name);
        if (!(await fs.stat(path)).isFile) {
          throw FileSystemException('Archive is missing $name', path);
        }
        await chmod(path);
      }
      if ((await fs.stat(destDir)).exists) {
        await fs.removeRecursive(destDir);
      }
      await fs.rename(staging, destDir);
      return fs.pathContext.join(destDir, executableName);
    } finally {
      if ((await fs.stat(temp)).exists) await fs.removeRecursive(temp);
    }
  }
}
