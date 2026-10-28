import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/installer/binary_archive_installer.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  Directory newRoot() {
    final root = Directory.systemTemp.createTempSync('agy-bin-');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    return root;
  }

  Future<File> writeZip(Directory root, List<ArchiveFile> files) async {
    final archive = Archive();
    for (final file in files) {
      archive.addFile(file);
    }
    final zip = File('${root.path}/adapter.zip');
    await zip.writeAsBytes(ZipEncoder().encode(archive));
    return zip;
  }

  /// Records the path the installer chmods and also applies the real POSIX
  /// mode, so the `test -x` assertion on the moved file is honest.
  Future<void> recordingChmod(String path, List<String> seen) async {
    seen.add(path);
    if (Platform.isWindows) return;
    final result = await Process.run('chmod', ['755', path]);
    expect(
      result.exitCode,
      0,
      reason: 'chmod failed for $path: ${result.stderr}',
    );
  }

  List<String> tempLeftovers(String parent) => Directory(parent)
      .listSync()
      .map((entity) => entity.path)
      .where((path) => path.contains('agy-acp-'))
      .toList();

  test('downloads, verifies, extracts, chmods, and moves atomically', () async {
    final root = newRoot();
    final zipFile = await writeZip(root, [
      ArchiveFile('agy_acp_server.par', 3, [1, 2, 3]),
    ]);
    final fs = LocalFilesystem();
    final chmodded = <String>[];

    final installer = BinaryArchiveInstaller(
      fs: fs,
      fetch: (uri, {expectedSha256, onProgress, isCancelled}) async => zipFile,
      chmod: (path) => recordingChmod(path, chmodded),
    );
    final path = await installer.install(
      archiveUri: Uri.parse('https://example.invalid/adapter.zip'),
      sha256: 'ignored-by-fake-fetch',
      destDir: '${root.path}/toolchain/1.4.3',
      executableName: 'agy_acp_server.par',
    );

    expect(path, '${root.path}/toolchain/1.4.3/agy_acp_server.par');
    expect(File(path).readAsBytesSync(), [1, 2, 3]);
    // chmod runs on the staged file, before the atomic move.
    expect(chmodded, hasLength(1));
    expect(chmodded.single, contains('/staging/'));
    expect(chmodded.single, endsWith('/agy_acp_server.par'));
    if (!Platform.isWindows) {
      final executable = await Process.run('test', ['-x', path]);
      expect(executable.exitCode, 0, reason: '$path is not executable');
    }
    expect(tempLeftovers('${root.path}/toolchain'), isEmpty);
  });

  test('rejects archive entries that escape destDir', () async {
    final root = newRoot();
    final zipFile = await writeZip(root, [
      ArchiveFile('../escape.txt', 3, [1, 2, 3]),
    ]);
    final installer = BinaryArchiveInstaller(
      fs: LocalFilesystem(),
      fetch: (uri, {expectedSha256, onProgress, isCancelled}) async => zipFile,
      chmod: (path) async {},
    );

    await expectLater(
      installer.install(
        archiveUri: Uri.parse('https://example.invalid/adapter.zip'),
        sha256: 'ignored-by-fake-fetch',
        destDir: '${root.path}/toolchain/1.4.3',
        executableName: 'agy_acp_server.par',
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('../escape.txt'),
        ),
      ),
    );

    expect(
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('escape.txt')),
      isEmpty,
    );
    expect(Directory('${root.path}/toolchain/1.4.3').existsSync(), isFalse);
    expect(tempLeftovers('${root.path}/toolchain'), isEmpty);
  });

  test(
    'missing executable leaves the existing destination untouched',
    () async {
      final root = newRoot();
      final zipFile = await writeZip(root, [
        ArchiveFile('other.bin', 1, [9]),
      ]);
      final destDir = '${root.path}/toolchain/1.4.3';
      Directory(destDir).createSync(recursive: true);
      File('$destDir/previous.par').writeAsStringSync('previous');
      final installer = BinaryArchiveInstaller(
        fs: LocalFilesystem(),
        fetch: (uri, {expectedSha256, onProgress, isCancelled}) async =>
            zipFile,
        chmod: (path) async {},
      );

      await expectLater(
        installer.install(
          archiveUri: Uri.parse('https://example.invalid/adapter.zip'),
          sha256: 'ignored-by-fake-fetch',
          destDir: destDir,
          executableName: 'agy_acp_server.par',
          extraExecutables: const ['extra.bin'],
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(File('$destDir/previous.par').readAsStringSync(), 'previous');
      expect(File('$destDir/other.bin').existsSync(), isFalse);
      expect(tempLeftovers('${root.path}/toolchain'), isEmpty);
    },
  );

  test(
    'reinstall replaces the destination and chmods extra executables',
    () async {
      final root = newRoot();
      final zipFile = await writeZip(root, [
        ArchiveFile('agy_acp_server.par', 2, [7, 8]),
        ArchiveFile('bin/helper', 1, [4]),
      ]);
      final destDir = '${root.path}/toolchain/1.4.3';
      Directory(destDir).createSync(recursive: true);
      File('$destDir/stale.txt').writeAsStringSync('stale');
      final chmodded = <String>[];
      final installer = BinaryArchiveInstaller(
        fs: LocalFilesystem(),
        fetch: (uri, {expectedSha256, onProgress, isCancelled}) async =>
            zipFile,
        chmod: (path) => recordingChmod(path, chmodded),
      );

      final path = await installer.install(
        archiveUri: Uri.parse('https://example.invalid/adapter.zip'),
        sha256: 'ignored-by-fake-fetch',
        destDir: destDir,
        executableName: 'agy_acp_server.par',
        extraExecutables: const ['bin/helper'],
      );

      expect(File(path).readAsBytesSync(), [7, 8]);
      expect(File('$destDir/stale.txt').existsSync(), isFalse);
      expect(chmodded, hasLength(2));
      expect(chmodded.every((path) => path.contains('/staging/')), isTrue);
      expect(chmodded, contains(endsWith('agy_acp_server.par')));
      expect(chmodded, contains(endsWith('bin/helper')));
      if (!Platform.isWindows) {
        for (final name in ['agy_acp_server.par', 'bin/helper']) {
          final executable = await Process.run('test', [
            '-x',
            '$destDir/$name',
          ]);
          expect(executable.exitCode, 0, reason: '$name is not executable');
        }
      }
    },
  );

  test('chmodExecutable throws when chmod fails', () async {
    await expectLater(
      chmodExecutable('${Directory.systemTemp.path}/agy-bin-missing/par'),
      throwsA(isA<ProcessException>()),
    );
  }, skip: Platform.isWindows);
}
