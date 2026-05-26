import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/terminal/terminal_uri_opener.dart';

void main() {
  group('TerminalUriOpener.fixup', () {
    test('trims trailing punctuation from https URL', () {
      expect(
        TerminalUriOpener.fixup('https://example.com).'),
        'https://example.com',
      );
    });

    test('strips localhost from file:// URI', () {
      expect(
        TerminalUriOpener.fixup('file://localhost/tmp/a.txt'),
        'file:///tmp/a.txt',
      );
    });

    test('rejects remote file:// host', () {
      expect(
        TerminalUriOpener.fixup('file://other-host/tmp/a.txt'),
        isNull,
      );
    });
  });

  group('TerminalUriOpener.resolveLocalFilePath', () {
    test('returns absolute path for file URI', () {
      final expected = Platform.isWindows ? r'\tmp\a.txt' : '/tmp/a.txt';
      expect(
        TerminalUriOpener.resolveLocalFilePath('file:///tmp/a.txt'),
        expected,
      );
    });

    test('joins relative file path with working directory', () {
      final wd = Platform.isWindows ? r'C:\project' : '/project';
      expect(
        TerminalUriOpener.resolveLocalFilePath(
          'file:/src/main.dart',
          workingDirectory: wd,
        ),
        p.normalize(p.join(wd, 'src', 'main.dart')),
      );
    });
  });
}
