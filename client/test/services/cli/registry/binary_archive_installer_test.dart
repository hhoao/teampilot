import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/registry/installer/binary_archive_installer.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  test('downloads, verifies, extracts, chmods, and moves atomically', () async {
    final root = Directory.systemTemp.createTempSync('agy-bin-');
    final zipFile = File('${root.path}/adapter.zip');
    final archive = Archive()
      ..addFile(ArchiveFile('agy_acp_server.par', 3, [1, 2, 3]));
    await zipFile.writeAsBytes(ZipEncoder().encode(archive));
    final fs = LocalFilesystem();
    var chmodded = '';

    final installer = BinaryArchiveInstaller(
      fs: fs,
      fetch: (uri, {expectedSha256, onProgress, isCancelled}) async => zipFile,
      chmod: (path) async => chmodded = path,
    );
    final path = await installer.install(
      archiveUri: Uri.parse('https://example.invalid/adapter.zip'),
      sha256: 'ignored-by-fake-fetch',
      destDir: '${root.path}/toolchain/1.4.3',
      executableName: 'agy_acp_server.par',
    );

    expect(path, '${root.path}/toolchain/1.4.3/agy_acp_server.par');
    expect(File(path).readAsBytesSync(), [1, 2, 3]);
    expect(chmodded, path);
  });
}
