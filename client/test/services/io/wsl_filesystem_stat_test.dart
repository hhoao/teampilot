import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/io/wsl_filesystem.dart';

void main() {
  group('WslFilesystem.stat', () {
    test('parses size and mtime from stat -c output', () async {
      List<String>? capturedArgs;
      final fs = WslFilesystem(
        processRunner: (executable, arguments) async {
          expect(executable, 'wsl.exe');
          capturedArgs = arguments;
          return ProcessResult(
            0,
            0,
            'regular file|42|1700000000\n',
            '',
          );
        },
      );

      final stat = await fs.stat('/tmp/partial.bin');

      expect(capturedArgs, ['stat', '-c', '%F|%s|%Y', '--', '/tmp/partial.bin']);
      expect(stat.kind, FsEntityKind.file);
      expect(stat.size, 42);
      expect(
        stat.mtime,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );
    });

    test('returns notFound when stat fails', () async {
      final fs = WslFilesystem(
        processRunner: (_, __) async =>
            ProcessResult(0, 1, '', 'No such file'),
      );
      final stat = await fs.stat('/missing');
      expect(stat.kind, FsEntityKind.notFound);
      expect(stat.size, isNull);
    });

    test('parses directory without requiring size for resume', () async {
      final fs = WslFilesystem(
        processRunner: (_, __) async =>
            ProcessResult(0, 0, 'directory|4096|1700000001\n', ''),
      );
      final stat = await fs.stat('/tmp');
      expect(stat.kind, FsEntityKind.directory);
      expect(stat.size, 4096);
    });
  });
}
